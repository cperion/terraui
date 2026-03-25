-- lib/sdl_gl_backend.t
-- SDL3 + OpenGL + SDL_ttf backend/session used by AOT demos.
--
-- This module owns:
--   * SDL window + GL context lifetime
--   * text backend session state
--   * built-in rect/border/text/scissor replay
--   * packet collection / replay generation for a concrete Frame type
--
-- The demo/app still owns:
--   * image resources and image draw policy
--   * custom command draw policy
--   * higher-level app state

local TerraUI = require("lib/terraui_schema")
local Decl = TerraUI.types.Decl
local compile = require("lib/compile")

local M = {}

local new_backend = terralib.memoize(function(font_path)
    local C = terralib.includecstring [[
#include <SDL3/SDL.h>
#include <SDL3/SDL_opengl.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
]]

    local TEXT_CACHE_CAP = 256
    local TEXT_KEY_CAP = 256
    local MEASURE_FONT_CACHE_CAP = 16

    local Packet, ScissorRect, TextCacheEntry, MeasureFontEntry, TextBackendSession, Session
    local fetch_measure_font, clear_measure_font_cache, measure_text_width, measure_text_height_for_width
    local color, to_byte, gl_color, gl_quad, gl_line_rect, draw_rect, draw_border
    local upload_texture_rgba, draw_textured_quad, build_text_key
    local find_text_cache, store_text_cache, fetch_text_texture, draw_text
    local packet_before, begin_frame, apply_scissor, init, shutdown, pump_input

    struct Packet {
        kind: int32
        index: int32
        z: float
        seq: uint32
    }

    struct ScissorRect {
        x: int32
        y: int32
        w: int32
        h: int32
    }

    struct TextCacheEntry {
        used: bool
        tex: uint32
        w: int32
        h: int32
        key: int8[TEXT_KEY_CAP]
    }

    struct MeasureFontEntry {
        used: bool
        size10: int32
        font: &C.TTF_Font
    }

    struct TextBackendSession {
        render_font: &C.TTF_Font
        measure_font_cache_cursor: int32
        measure_font_cache: MeasureFontEntry[MEASURE_FONT_CACHE_CAP]
        text_cache_cursor: int32
        text_cache: TextCacheEntry[TEXT_CACHE_CAP]
    }

    struct Session {
        window: &C.SDL_Window
        glctx: C.SDL_GLContext
        text: TextBackendSession
    }

    local SDL_WINDOW_OPENGL = 0x0000000000000002ULL
    local SDL_WINDOW_HIDDEN = 0x0000000000000008ULL
    local SDL_WINDOW_RESIZABLE = 0x0000000000000020ULL
    local SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x0000000000002000ULL
    local SDL_EVENT_QUIT = 0x100
    local SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x210
    local SDL_EVENT_MOUSE_MOTION = 0x400
    local SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401
    local SDL_EVENT_MOUSE_BUTTON_UP = 0x402
    local SDL_EVENT_MOUSE_WHEEL = 0x403
    local SDL_BUTTON_LEFT = 1

    terra fetch_measure_font(session: &TextBackendSession, font_size: float) : &C.TTF_Font
        var size10 = [int32](font_size * 10.0f)
        for i = 0, MEASURE_FONT_CACHE_CAP do
            if session.measure_font_cache[i].used and session.measure_font_cache[i].size10 == size10 then
                return session.measure_font_cache[i].font
            end
        end

        var slot: int32 = -1
        for i = 0, MEASURE_FONT_CACHE_CAP do
            if not session.measure_font_cache[i].used then
                slot = i
                break
            end
        end
        if slot < 0 then
            slot = session.measure_font_cache_cursor % MEASURE_FONT_CACHE_CAP
            if session.measure_font_cache[slot].used and session.measure_font_cache[slot].font ~= nil then
                C.TTF_CloseFont(session.measure_font_cache[slot].font)
            end
        end

        var font = C.TTF_OpenFont([font_path], font_size)
        if font == nil then return nil end

        session.measure_font_cache[slot].used = true
        session.measure_font_cache[slot].size10 = size10
        session.measure_font_cache[slot].font = font
        session.measure_font_cache_cursor = (slot + 1) % MEASURE_FONT_CACHE_CAP
        return font
    end

    terra clear_measure_font_cache(session: &TextBackendSession)
        for i = 0, MEASURE_FONT_CACHE_CAP do
            if session.measure_font_cache[i].used and session.measure_font_cache[i].font ~= nil then
                C.TTF_CloseFont(session.measure_font_cache[i].font)
                session.measure_font_cache[i].font = nil
            end
            session.measure_font_cache[i].used = false
            session.measure_font_cache[i].size10 = 0
        end
        session.measure_font_cache_cursor = 0
    end

    terra measure_text_width(session: &TextBackendSession, text: rawstring, font_size: float, align: int32) : float
        if session == nil or text == nil then return 0 end
        var font = fetch_measure_font(session, font_size)
        if font == nil then return 0 end

        if align == compile.TEXT_ALIGN_CENTER then
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_CENTER)
        elseif align == compile.TEXT_ALIGN_RIGHT then
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_RIGHT)
        else
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_LEFT)
        end

        var w: int32 = 0
        var h: int32 = 0
        var ok = C.TTF_GetStringSize(font, text, C.strlen(text), &w, &h)
        if not ok then return 0 end
        return [float](w)
    end

    terra measure_text_height_for_width(session: &TextBackendSession, text: rawstring, font_size: float, wrap: int32, align: int32, max_width: float) : float
        if session == nil or text == nil then return 0 end
        var font = fetch_measure_font(session, font_size)
        if font == nil then return 0 end

        if align == compile.TEXT_ALIGN_CENTER then
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_CENTER)
        elseif align == compile.TEXT_ALIGN_RIGHT then
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_RIGHT)
        else
            C.TTF_SetFontWrapAlignment(font, C.TTF_HORIZONTAL_ALIGN_LEFT)
        end

        var wrap_w = [int32](max_width)
        if wrap_w < 1 then wrap_w = 1 end

        var w: int32 = 0
        var h: int32 = 0
        var ok: bool
        if wrap == compile.TEXT_WRAP_WORDS then
            ok = C.TTF_GetStringSizeWrapped(font, text, C.strlen(text), wrap_w, &w, &h)
        elseif wrap == compile.TEXT_WRAP_NEWLINES then
            ok = C.TTF_GetStringSizeWrapped(font, text, C.strlen(text), 1000000, &w, &h)
        else
            ok = C.TTF_GetStringSize(font, text, C.strlen(text), &w, &h)
        end
        if not ok then return 0 end
        return [float](h)
    end

    local text_backend = { key = "sdl-ttf:" .. font_path }
    function text_backend:measure_width(ctx, spec)
        local align = compile.TEXT_ALIGN_LEFT
        if spec.align == Decl.TextAlignCenter then
            align = compile.TEXT_ALIGN_CENTER
        elseif spec.align == Decl.TextAlignRight then
            align = compile.TEXT_ALIGN_RIGHT
        end
        local session_q = `[&TextBackendSession]([ctx.frame_sym].text_backend_state)
        return `measure_text_width([session_q], [spec.content:compile_string(ctx)], [spec.font_size:compile_number(ctx)], [align])
    end
    function text_backend:measure_height_for_width(ctx, spec, max_width)
        local wrap = compile.TEXT_WRAP_NONE
        if spec.wrap == Decl.WrapWords then
            wrap = compile.TEXT_WRAP_WORDS
        elseif spec.wrap == Decl.WrapNewlines then
            wrap = compile.TEXT_WRAP_NEWLINES
        end

        local align = compile.TEXT_ALIGN_LEFT
        if spec.align == Decl.TextAlignCenter then
            align = compile.TEXT_ALIGN_CENTER
        elseif spec.align == Decl.TextAlignRight then
            align = compile.TEXT_ALIGN_RIGHT
        end

        local session_q = `[&TextBackendSession]([ctx.frame_sym].text_backend_state)
        return `measure_text_height_for_width([session_q], [spec.content:compile_string(ctx)], [spec.font_size:compile_number(ctx)], [wrap], [align], [max_width])
    end

    terra color(r: float, g: float, b: float, a: float) : compile.Color
        return compile.Color { r, g, b, a }
    end

    terra to_byte(v: float) : int32
        var x = [int32](v * 255.0f)
        if x < 0 then return 0 end
        if x > 255 then return 255 end
        return x
    end

    terra gl_color(c: compile.Color, opacity: float)
        C.glColor4f(c.r, c.g, c.b, c.a * opacity)
    end

    terra gl_quad(x: float, y: float, w: float, h: float)
        C.glBegin(C.GL_QUADS)
        C.glVertex2f(x, y)
        C.glVertex2f(x + w, y)
        C.glVertex2f(x + w, y + h)
        C.glVertex2f(x, y + h)
        C.glEnd()
    end

    terra gl_line_rect(x: float, y: float, w: float, h: float)
        C.glBegin(C.GL_LINE_LOOP)
        C.glVertex2f(x, y)
        C.glVertex2f(x + w, y)
        C.glVertex2f(x + w, y + h)
        C.glVertex2f(x, y + h)
        C.glEnd()
    end

    terra draw_rect(cmd: compile.RectCmd)
        gl_color(cmd.color, cmd.opacity)
        gl_quad(cmd.x, cmd.y, cmd.w, cmd.h)
    end

    terra draw_border(cmd: compile.BorderCmd)
        gl_color(cmd.color, cmd.opacity)
        if cmd.left > 0 then gl_quad(cmd.x, cmd.y, cmd.left, cmd.h) end
        if cmd.top > 0 then gl_quad(cmd.x, cmd.y, cmd.w, cmd.top) end
        if cmd.right > 0 then gl_quad(cmd.x + cmd.w - cmd.right, cmd.y, cmd.right, cmd.h) end
        if cmd.bottom > 0 then gl_quad(cmd.x, cmd.y + cmd.h - cmd.bottom, cmd.w, cmd.bottom) end
    end

    terra upload_texture_rgba(width: int32, height: int32, pixels: &opaque, linear: bool) : uint32
        var tex: uint32 = 0
        C.glGenTextures(1, &tex)
        C.glBindTexture(C.GL_TEXTURE_2D, tex)
        if linear then
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_LINEAR)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_LINEAR)
        else
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_NEAREST)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_NEAREST)
        end
        -- Textures are sampled with GL_LINEAR. Clamp-to-edge avoids edge
        -- bleed against the implicit border color, which can shave a pixel
        -- off glyph tops/edges on tightly packed text surfaces.
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_CLAMP_TO_EDGE)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_CLAMP_TO_EDGE)
        C.glTexImage2D(C.GL_TEXTURE_2D, 0, C.GL_RGBA, width, height, 0, C.GL_RGBA, C.GL_UNSIGNED_BYTE, pixels)
        return tex
    end

    terra draw_textured_quad(tex: uint32, x: float, y: float, w: float, h: float, c: compile.Color)
        C.glEnable(C.GL_TEXTURE_2D)
        C.glBindTexture(C.GL_TEXTURE_2D, tex)
        C.glColor4f(c.r, c.g, c.b, c.a)
        C.glBegin(C.GL_QUADS)
        C.glTexCoord2f(0.0, 0.0); C.glVertex2f(x, y)
        C.glTexCoord2f(1.0, 0.0); C.glVertex2f(x + w, y)
        C.glTexCoord2f(1.0, 1.0); C.glVertex2f(x + w, y + h)
        C.glTexCoord2f(0.0, 1.0); C.glVertex2f(x, y + h)
        C.glEnd()
        C.glDisable(C.GL_TEXTURE_2D)
    end

    terra build_text_key(cmd: compile.TextCmd, out: &int8)
        var font_id = cmd.font_id
        if font_id == nil then font_id = "default" end
        C.snprintf(out, TEXT_KEY_CAP, "%s|%s|%d|%d|%d|%d|%d|%d|%d|%d",
            cmd.text,
            font_id,
            [int32](cmd.font_size * 10.0f),
            [int32](cmd.w),
            cmd.wrap,
            cmd.align,
            to_byte(cmd.color.r),
            to_byte(cmd.color.g),
            to_byte(cmd.color.b),
            to_byte(cmd.color.a))
    end

    terra find_text_cache(session: &TextBackendSession, key: &int8) : int32
        for i = 0, TEXT_CACHE_CAP do
            if session.text_cache[i].used and C.strcmp([&int8](&session.text_cache[i].key[0]), key) == 0 then
                return i
            end
        end
        return -1
    end

    terra store_text_cache(session: &TextBackendSession, key: &int8, tex: uint32, w: int32, h: int32) : int32
        var slot: int32 = -1
        for i = 0, TEXT_CACHE_CAP do
            if not session.text_cache[i].used then
                slot = i
                break
            end
        end
        if slot < 0 then
            slot = session.text_cache_cursor % TEXT_CACHE_CAP
            if session.text_cache[slot].used and session.text_cache[slot].tex ~= 0 then
                C.glDeleteTextures(1, &session.text_cache[slot].tex)
            end
        end
        session.text_cache_cursor = (slot + 1) % TEXT_CACHE_CAP
        session.text_cache[slot].used = true
        session.text_cache[slot].tex = tex
        session.text_cache[slot].w = w
        session.text_cache[slot].h = h
        C.snprintf([&int8](&session.text_cache[slot].key[0]), TEXT_KEY_CAP, "%s", key)
        return slot
    end

    terra fetch_text_texture(session: &TextBackendSession, cmd: compile.TextCmd, out_w: &int32, out_h: &int32) : uint32
        if session == nil or session.render_font == nil or cmd.text == nil then return 0 end

        var key: int8[TEXT_KEY_CAP]
        build_text_key(cmd, [&int8](&key[0]))

        var cached = find_text_cache(session, [&int8](&key[0]))
        if cached >= 0 then
            @out_w = session.text_cache[cached].w
            @out_h = session.text_cache[cached].h
            return session.text_cache[cached].tex
        end

        if not C.TTF_SetFontSize(session.render_font, cmd.font_size) then return 0 end

        if cmd.align == compile.TEXT_ALIGN_CENTER then
            C.TTF_SetFontWrapAlignment(session.render_font, C.TTF_HORIZONTAL_ALIGN_CENTER)
        elseif cmd.align == compile.TEXT_ALIGN_RIGHT then
            C.TTF_SetFontWrapAlignment(session.render_font, C.TTF_HORIZONTAL_ALIGN_RIGHT)
        else
            C.TTF_SetFontWrapAlignment(session.render_font, C.TTF_HORIZONTAL_ALIGN_LEFT)
        end

        var col: C.SDL_Color
        col.r = [uint8](to_byte(cmd.color.r))
        col.g = [uint8](to_byte(cmd.color.g))
        col.b = [uint8](to_byte(cmd.color.b))
        col.a = [uint8](to_byte(cmd.color.a))

        var surf: &C.SDL_Surface = nil
        var wrap_w = [int32](cmd.w)
        if wrap_w < 1 then wrap_w = 1 end
        if cmd.wrap == compile.TEXT_WRAP_WORDS then
            surf = C.TTF_RenderText_Blended_Wrapped(session.render_font, cmd.text, C.strlen(cmd.text), col, wrap_w)
        elseif cmd.wrap == compile.TEXT_WRAP_NEWLINES then
            surf = C.TTF_RenderText_Blended_Wrapped(session.render_font, cmd.text, C.strlen(cmd.text), col, 1000000)
        else
            surf = C.TTF_RenderText_Blended(session.render_font, cmd.text, C.strlen(cmd.text), col)
        end

        if surf == nil then return 0 end
        var rgba_surf = C.SDL_ConvertSurface(surf, C.SDL_PIXELFORMAT_ABGR8888)
        C.SDL_DestroySurface(surf)
        if rgba_surf == nil then return 0 end

        C.SDL_LockSurface(rgba_surf)
        var tex = upload_texture_rgba(rgba_surf.w, rgba_surf.h, rgba_surf.pixels, true)
        C.SDL_UnlockSurface(rgba_surf)

        @out_w = rgba_surf.w
        @out_h = rgba_surf.h
        store_text_cache(session, [&int8](&key[0]), tex, rgba_surf.w, rgba_surf.h)
        C.SDL_DestroySurface(rgba_surf)
        return tex
    end

    terra draw_text(session: &Session, cmd: compile.TextCmd)
        var w: int32 = 0
        var h: int32 = 0
        var tex = fetch_text_texture(&session.text, cmd, &w, &h)
        if tex == 0 then return end

        var draw_x = cmd.x
        if cmd.wrap == compile.TEXT_WRAP_NONE then
            if cmd.align == compile.TEXT_ALIGN_CENTER then
                draw_x = cmd.x + (cmd.w - [float](w)) * 0.5f
            elseif cmd.align == compile.TEXT_ALIGN_RIGHT then
                draw_x = cmd.x + (cmd.w - [float](w))
            end
        end

        draw_x = C.floorf(draw_x)
        -- Vertically center text within its content box so labels and
        -- buttons with explicit heights don't push text to the top edge.
        var draw_y = C.floorf(cmd.y + (cmd.h - [float](h)) * 0.5f)
        draw_textured_quad(tex, draw_x, draw_y, [float](w), [float](h), color(1.0f, 1.0f, 1.0f, 1.0f))
    end

    terra packet_before(a: Packet, b: Packet) : bool
        if a.z < b.z then return true end
        if a.z > b.z then return false end
        return a.seq < b.seq
    end

    terra begin_frame(session: &Session, vw: int32, vh: int32)
        C.glViewport(0, 0, vw, vh)
        C.glClearColor(0.05, 0.06, 0.08, 1.0)
        C.glClear(C.GL_COLOR_BUFFER_BIT)
        C.glMatrixMode(C.GL_PROJECTION)
        C.glLoadIdentity()
        C.glOrtho(0.0, [double](vw), [double](vh), 0.0, -1.0, 1.0)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glLoadIdentity()
    end

    terra apply_scissor(enabled: bool, rect: ScissorRect)
        if enabled then
            C.glEnable(C.GL_SCISSOR_TEST)
            C.glScissor(rect.x, rect.y, rect.w, rect.h)
        else
            C.glDisable(C.GL_SCISSOR_TEST)
        end
    end

    terra init(session: &Session, title: rawstring, width: int32, height: int32, hidden: bool) : int
        clear_measure_font_cache(&session.text)
        if not C.SDL_Init(C.SDL_INIT_VIDEO) then return 1 end
        if not C.TTF_Init() then
            C.SDL_Quit()
            return 2
        end
        C.SDL_GL_SetAttribute(C.SDL_GL_DOUBLEBUFFER, 1)
        C.SDL_GL_SetAttribute(C.SDL_GL_DEPTH_SIZE, 0)

        var flags = [uint64]([SDL_WINDOW_OPENGL + SDL_WINDOW_RESIZABLE + SDL_WINDOW_HIGH_PIXEL_DENSITY])
        if hidden then flags = flags + [uint64]([SDL_WINDOW_HIDDEN]) end

        session.window = C.SDL_CreateWindow(title, width, height, flags)
        if session.window == nil then
            C.TTF_Quit()
            C.SDL_Quit()
            return 3
        end

        session.glctx = C.SDL_GL_CreateContext(session.window)
        if session.glctx == nil then
            C.SDL_DestroyWindow(session.window)
            C.TTF_Quit()
            C.SDL_Quit()
            return 4
        end

        C.SDL_GL_SetSwapInterval(1)
        session.text.render_font = C.TTF_OpenFont([font_path], 16.0)
        if session.text.render_font == nil then
            C.SDL_GL_DestroyContext(session.glctx)
            C.SDL_DestroyWindow(session.window)
            C.TTF_Quit()
            C.SDL_Quit()
            return 5
        end

        C.glDisable(C.GL_DEPTH_TEST)
        C.glEnable(C.GL_BLEND)
        C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        session.text.text_cache_cursor = 0
        return 0
    end

    terra shutdown(session: &Session)
        for i = 0, TEXT_CACHE_CAP do
            if session.text.text_cache[i].used and session.text.text_cache[i].tex ~= 0 then
                C.glDeleteTextures(1, &session.text.text_cache[i].tex)
            end
        end
        clear_measure_font_cache(&session.text)
        if session.text.render_font ~= nil then C.TTF_CloseFont(session.text.render_font) end
        if session.glctx ~= nil then C.SDL_GL_DestroyContext(session.glctx) end
        if session.window ~= nil then C.SDL_DestroyWindow(session.window) end
        C.TTF_Quit()
        C.SDL_Quit()
    end

    terra pump_input(session: &Session, input: &compile.InputState, viewport_w: &float, viewport_h: &float, quit: &bool)
        input.mouse_pressed = false
        input.mouse_released = false
        input.wheel_dx = 0
        input.wheel_dy = 0

        var have_mouse_pos = false
        var event_mouse_x: float = input.mouse_x
        var event_mouse_y: float = input.mouse_y

        var ev: C.SDL_Event
        while C.SDL_PollEvent(&ev) do
            if ev.type == [SDL_EVENT_QUIT] or ev.type == [SDL_EVENT_WINDOW_CLOSE_REQUESTED] then
                @quit = true
            elseif ev.type == [SDL_EVENT_MOUSE_MOTION] then
                event_mouse_x = ev.motion.x
                event_mouse_y = ev.motion.y
                have_mouse_pos = true
            elseif ev.type == [SDL_EVENT_MOUSE_BUTTON_DOWN] and ev.button.button == [SDL_BUTTON_LEFT] then
                input.mouse_down = true
                input.mouse_pressed = true
                event_mouse_x = ev.button.x
                event_mouse_y = ev.button.y
                have_mouse_pos = true
            elseif ev.type == [SDL_EVENT_MOUSE_BUTTON_UP] and ev.button.button == [SDL_BUTTON_LEFT] then
                input.mouse_down = false
                input.mouse_released = true
                event_mouse_x = ev.button.x
                event_mouse_y = ev.button.y
                have_mouse_pos = true
            elseif ev.type == [SDL_EVENT_MOUSE_WHEEL] then
                var wx = ev.wheel.x
                var wy = ev.wheel.y
                if ev.wheel.integer_x ~= 0 then wx = [float](ev.wheel.integer_x) end
                if ev.wheel.integer_y ~= 0 then wy = [float](ev.wheel.integer_y) end
                if ev.wheel.direction == C.SDL_MOUSEWHEEL_FLIPPED then
                    wx = -wx
                    wy = -wy
                end
                -- SDL docs:
                --   x > 0 => scrolled right
                --   y > 0 => scrolled away from the user
                --   FLIPPED means the reported values are opposite and should be negated.
                -- After normalizing FLIPPED, keep SDL's canonical wheel signs here.
                input.wheel_dx = input.wheel_dx + wx
                input.wheel_dy = input.wheel_dy + wy
                event_mouse_x = ev.wheel.mouse_x
                event_mouse_y = ev.wheel.mouse_y
                have_mouse_pos = true
            end
        end

        if have_mouse_pos then
            input.mouse_x = event_mouse_x
            input.mouse_y = event_mouse_y
        else
            var mx: float, my: float
            C.SDL_GetMouseState(&mx, &my)
            input.mouse_x = mx
            input.mouse_y = my
        end

        var vw: int, vh: int
        C.SDL_GetWindowSizeInPixels(session.window, &vw, &vh)
        @viewport_w = [float](vw)
        @viewport_h = [float](vh)
    end

    local function make_replay(frame_t, max_packets, max_scissors, app_t, draw_image_fn, draw_custom_fn)
        local PacketArrayT = Packet[max_packets]
        local ScissorArrayT = ScissorRect[max_scissors]

        local push_packets = terra(frame: &frame_t, packets: &Packet, base: int32, kind: int32, count: int32) : int32
            var n = base
            if kind == 1 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.rects[i].z
                    packets[n].seq = frame.rects[i].seq
                    n = n + 1
                end
            elseif kind == 2 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.borders[i].z
                    packets[n].seq = frame.borders[i].seq
                    n = n + 1
                end
            elseif kind == 3 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.texts[i].z
                    packets[n].seq = frame.texts[i].seq
                    n = n + 1
                end
            elseif kind == 4 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.images[i].z
                    packets[n].seq = frame.images[i].seq
                    n = n + 1
                end
            elseif kind == 5 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.scissors[i].z
                    packets[n].seq = frame.scissors[i].seq
                    n = n + 1
                end
            elseif kind == 6 then
                for i = 0, count - 1 do
                    packets[n].kind = kind
                    packets[n].index = i
                    packets[n].z = frame.customs[i].z
                    packets[n].seq = frame.customs[i].seq
                    n = n + 1
                end
            end
            return n
        end

        local collect_packets = terra(frame: &frame_t, packets: &Packet) : int32
            var n: int32 = 0
            n = push_packets(frame, packets, n, 1, frame.rect_count)
            n = push_packets(frame, packets, n, 2, frame.border_count)
            n = push_packets(frame, packets, n, 3, frame.text_count)
            n = push_packets(frame, packets, n, 4, frame.image_count)
            n = push_packets(frame, packets, n, 5, frame.scissor_count)
            n = push_packets(frame, packets, n, 6, frame.custom_count)

            for i = 1, n - 1 do
                var key = packets[i]
                var j = i
                while j > 0 and packet_before(key, packets[j - 1]) do
                    packets[j] = packets[j - 1]
                    j = j - 1
                end
                packets[j] = key
            end
            return n
        end

        return terra(session: &Session, app: &app_t, frame: &frame_t)
            var packets: PacketArrayT
            var scissor_stack: ScissorArrayT
            var scissor_count: int32 = 0
            var packet_count = collect_packets(frame, &packets[0])
            var vw = [int32](frame.viewport_w)
            var vh = [int32](frame.viewport_h)

            begin_frame(session, vw, vh)

            for i = 0, packet_count - 1 do
                var p = packets[i]
                if p.kind == 5 then
                    var cmd = frame.scissors[p.index]
                    if cmd.is_begin then
                        var x0 = [int32](C.floorf(cmd.x0))
                        var x1 = [int32](C.ceilf(cmd.x1))
                        var y0 = [int32](C.floorf(frame.viewport_h - cmd.y1))
                        var y1 = [int32](C.ceilf(frame.viewport_h - cmd.y0))
                        scissor_stack[scissor_count].x = x0
                        scissor_stack[scissor_count].y = y0
                        scissor_stack[scissor_count].w = x1 - x0
                        scissor_stack[scissor_count].h = y1 - y0
                        scissor_count = scissor_count + 1
                        apply_scissor(true, scissor_stack[scissor_count - 1])
                    else
                        if scissor_count > 0 then scissor_count = scissor_count - 1 end
                        if scissor_count > 0 then
                            apply_scissor(true, scissor_stack[scissor_count - 1])
                        else
                            var z: ScissorRect
                            apply_scissor(false, z)
                        end
                    end
                elseif p.kind == 1 then
                    draw_rect(frame.rects[p.index])
                elseif p.kind == 2 then
                    draw_border(frame.borders[p.index])
                elseif p.kind == 3 then
                    draw_text(session, frame.texts[p.index])
                elseif p.kind == 4 then
                    [draw_image_fn](app, frame.images[p.index])
                elseif p.kind == 6 then
                    [draw_custom_fn](app, frame.customs[p.index])
                end
            end

            if scissor_count > 0 then
                var z: ScissorRect
                apply_scissor(false, z)
            end
        end
    end

    local swap_window = terra(session: &Session)
        C.SDL_GL_SwapWindow(session.window)
    end

    return {
        C = C,
        Session = Session,
        TextBackendSession = TextBackendSession,
        text_backend = text_backend,
        color = color,
        gl_color = gl_color,
        gl_quad = gl_quad,
        gl_line_rect = gl_line_rect,
        upload_texture_rgba = upload_texture_rgba,
        draw_textured_quad = draw_textured_quad,
        draw_text = draw_text,
        init = init,
        shutdown = shutdown,
        pump_input = pump_input,
        make_replay = make_replay,
        swap_window = swap_window,
    }
end)

function M.new(font_path)
    return new_backend(assert(font_path, "font_path required"))
end

return M
