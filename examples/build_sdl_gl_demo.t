local terraui = require("lib/terraui")
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")

local function split_ws(s)
    local t = terralib.newlist()
    for w in tostring(s):gmatch("%S+") do t:insert(w) end
    return t
end

local function sh(cmd)
    local p = assert(io.popen(cmd, "r"))
    local out = p:read("*a") or ""
    p:close()
    return out
end

local out_path = (arg and arg[1]) or "examples/sdl_gl_demo"
local font_path = ((arg and arg[2]) or sh("fc-match -f '%{file}\n' monospace | head -1")):gsub("%s+$", "")
assert(#font_path > 0, "could not resolve a font path via fc-match")

local link_flags = split_ws((sh("pkg-config --libs sdl3 sdl3-ttf") or "") .. " -lGL")

local C = terralib.includecstring [[
#include <SDL3/SDL.h>
#include <SDL3/SDL_opengl.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
]]

local ui = terraui.dsl()

local function rgba(r,g,b,a) return ui.rgba(r,g,b,a) end
local function panel(props)
    props = props or {}
    props.background = props.background or rgba(0.12, 0.13, 0.15, 1.0)
    props.border = props.border or ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.22, 0.24, 0.28, 1.0) }
    props.padding = props.padding or 10
    props.gap = props.gap or 8
    return props
end
local function button(text, action)
    return ui.button {
        text = text,
        action = action,
        padding = { left = 10, top = 7, right = 10, bottom = 7 },
        background = rgba(0.23, 0.38, 0.69, 1),
        border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.42, 0.58, 0.86, 1) },
        radius = ui.radius(4),
        text_color = rgba(1, 1, 1, 1),
        font_size = 15,
    }
end
local function label(text, props)
    props = props or {}
    props.text = text
    props.text_color = props.text_color or rgba(0.92, 0.93, 0.95, 1)
    props.font_size = props.font_size or 15
    return ui.label(props)
end

local decl = ui.component("sdl_gl_demo") {
    root = ui.column {
        id = ui.stable("root"),
        width = ui.grow(),
        height = ui.grow(),
        background = rgba(0.08, 0.09, 0.11, 1),
    } {
        ui.row {
            id = ui.stable("toolbar"),
            height = ui.fixed(46),
            padding = { left = 12, top = 8, right = 12, bottom = 8 },
            gap = 8,
            align_y = ui.align_y.center,
            background = rgba(0.10, 0.11, 0.14, 1),
            border = ui.border { bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
        } {
            button("Inspect", "inspect"),
            button("Apply", "apply"),
            button("Export", "export"),
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            label("TerraUI AOT SDL+OpenGL demo", { text_color = rgba(0.68, 0.72, 0.78, 1), font_size = 14 }),
        },

        ui.row {
            id = ui.stable("main"),
            width = ui.grow(),
            height = ui.grow(),
            gap = 12,
            padding = 12,
        } {
            ui.scroll_region(panel {
                id = ui.stable("assets"),
                width = ui.fixed(240),
                height = ui.grow(),
                vertical = true,
                scroll_y = 26,
            }) {
                label("Assets", { font_size = 20 }),
                button("Terrain", "asset:terrain"),
                button("Water", "asset:water"),
                button("Roads", "asset:roads"),
                button("Buildings", "asset:buildings"),
                button("Labels", "asset:labels"),
                button("Vegetation", "asset:vegetation"),
                button("Lighting", "asset:lighting"),
                button("Weather", "asset:weather"),
                button("Vehicles", "asset:vehicles"),
                button("Transit", "asset:transit"),
                button("Utilities", "asset:utilities"),
            },

            ui.column {
                id = ui.stable("center"),
                width = ui.grow(),
                height = ui.grow(),
                gap = 10,
            } {
                label("Preview", { font_size = 22 }),
                ui.image_view {
                    id = ui.stable("preview"),
                    image = "checker",
                    width = ui.fixed(420),
                    height = ui.fixed(250),
                    aspect_ratio = 1.68,
                    background = rgba(0.12, 0.13, 0.15, 1),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.26, 0.28, 0.33, 1) },
                    tint = rgba(1,1,1,1),
                },
                ui.row(panel {
                    id = ui.stable("status"),
                    width = ui.fit(),
                    height = ui.fit(),
                    gap = 16,
                }) {
                    label("Renderer: TerraUI kernel -> Terra AOT -> SDL3 -> OpenGL"),
                    label("Input: pointer + action output"),
                },
                ui.tooltip {
                    id = ui.stable("tooltip"),
                    target = ui.float.by_id("preview"),
                    element_point = ui.attach.left_bottom,
                    parent_point = ui.attach.right_top,
                    offset_x = 10,
                    offset_y = -10,
                    z_index = 20,
                    padding = { left = 10, top = 8, right = 10, bottom = 8 },
                    background = rgba(0.95, 0.80, 0.30, 0.95),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.55, 0.40, 0.10, 1) },
                } {
                    label("Floating tooltip attached to preview", {
                        text_color = rgba(0.18, 0.14, 0.08, 1),
                        font_size = 14,
                    }),
                },
            },

            ui.column(panel {
                id = ui.stable("inspector"),
                width = ui.fixed(280),
                height = ui.grow(),
            }) {
                label("Inspector", { font_size = 20 }),
                label("Type: Static-tree kernel"),
                label("Layout: Clay-like row/column flow"),
                label("Render: split streams merged by (z, seq)"),
                label("Text: measured in kernel, rendered in backend"),
                label("Clip: scissor stack replay"),
                label("Float: tooltip attached by stable id"),
                label("Build: ahead-of-time executable"),
            },
        },
    },
}

local bound = bind.bind_component(decl)
local planned = plan.plan_component(bound)
local kernel = compile.compile_component(planned)
local Frame = kernel:frame_type()
local init_q = kernel.kernels.init_fn
local run_q = kernel.kernels.run_fn

local max_packets = #planned.paints + #planned.texts + #planned.images + (#planned.clips * 2) + #planned.customs
if max_packets < 1 then max_packets = 1 end
local max_scissors = #planned.clips
if max_scissors < 1 then max_scissors = 1 end

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

struct DemoApp {
    window: &C.SDL_Window
    glctx: C.SDL_GLContext
    font: &C.TTF_Font
    checker_tex: uint32
}

local PacketArrayT = Packet[max_packets]
local ScissorArrayT = ScissorRect[max_scissors]

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

terra packet_before(a: Packet, b: Packet) : bool
    if a.z < b.z then return true end
    if a.z > b.z then return false end
    return a.seq < b.seq
end

terra push_packets(frame: &Frame, packets: &Packet, base: int32, kind: int32, count: int32) : int32
    var n = base
    if kind == 1 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.rects[i].z
            packets[n].seq = frame.rects[i].seq
            n = n + 1
        end
    elseif kind == 2 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.borders[i].z
            packets[n].seq = frame.borders[i].seq
            n = n + 1
        end
    elseif kind == 3 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.texts[i].z
            packets[n].seq = frame.texts[i].seq
            n = n + 1
        end
    elseif kind == 4 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.images[i].z
            packets[n].seq = frame.images[i].seq
            n = n + 1
        end
    elseif kind == 5 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.scissors[i].z
            packets[n].seq = frame.scissors[i].seq
            n = n + 1
        end
    elseif kind == 6 then
        for i = 0, count do
            packets[n].kind = kind
            packets[n].index = i
            packets[n].z = frame.customs[i].z
            packets[n].seq = frame.customs[i].seq
            n = n + 1
        end
    end
    return n
end

terra collect_packets(frame: &Frame, packets: &Packet) : int32
    var n: int32 = 0
    n = push_packets(frame, packets, n, 1, frame.rect_count)
    n = push_packets(frame, packets, n, 2, frame.border_count)
    n = push_packets(frame, packets, n, 3, frame.text_count)
    n = push_packets(frame, packets, n, 4, frame.image_count)
    n = push_packets(frame, packets, n, 5, frame.scissor_count)
    n = push_packets(frame, packets, n, 6, frame.custom_count)

    for i = 1, n do
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
    C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_CLAMP)
    C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_CLAMP)
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

terra draw_text(app: &DemoApp, cmd: compile.TextCmd)
    if app.font == nil or cmd.text == nil then return end

    var col: C.SDL_Color
    col.r = [uint8](cmd.color.r * 255.0)
    col.g = [uint8](cmd.color.g * 255.0)
    col.b = [uint8](cmd.color.b * 255.0)
    col.a = [uint8](cmd.color.a * 255.0)

    var surf = C.TTF_RenderText_Blended(app.font, cmd.text, C.strlen(cmd.text), col)
    if surf == nil then return end
    var rgba = C.SDL_ConvertSurface(surf, C.SDL_PIXELFORMAT_ABGR8888)
    C.SDL_DestroySurface(surf)
    if rgba == nil then return end

    C.SDL_LockSurface(rgba)
    var tex = upload_texture_rgba(rgba.w, rgba.h, rgba.pixels, true)
    C.SDL_UnlockSurface(rgba)

    draw_textured_quad(tex, cmd.x, cmd.y, [float](rgba.w), [float](rgba.h), cmd.color)
    C.glDeleteTextures(1, &tex)
    C.SDL_DestroySurface(rgba)
end

terra draw_image(app: &DemoApp, cmd: compile.ImageCmd)
    if cmd.image_id ~= nil and (C.strcmp(cmd.image_id, "checker") == 0 or C.strcmp(cmd.image_id, "preview") == 0) then
        draw_textured_quad(app.checker_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    else
        var c = cmd.tint
        C.glColor4f(c.r, 0.2, 0.8, c.a)
        gl_quad(cmd.x, cmd.y, cmd.w, cmd.h)
    end
end

terra draw_custom(cmd: compile.CustomCmd)
    C.glColor4f(1.0, 0.4, 0.1, 1.0)
    C.glBegin(C.GL_LINE_LOOP)
    C.glVertex2f(cmd.x, cmd.y)
    C.glVertex2f(cmd.x + cmd.w, cmd.y)
    C.glVertex2f(cmd.x + cmd.w, cmd.y + cmd.h)
    C.glVertex2f(cmd.x, cmd.y + cmd.h)
    C.glEnd()
end

terra init_checker_texture(app: &DemoApp)
    var pixels: uint8[64 * 64 * 4]
    for y = 0, 64 do
        for x = 0, 64 do
            var idx = (y * 64 + x) * 4
            var dark = ((x / 8) + (y / 8)) % 2 == 0
            if dark then
                pixels[idx + 0] = 70
                pixels[idx + 1] = 76
                pixels[idx + 2] = 88
                pixels[idx + 3] = 255
            else
                pixels[idx + 0] = 170
                pixels[idx + 1] = 176
                pixels[idx + 2] = 188
                pixels[idx + 3] = 255
            end
        end
    end
    app.checker_tex = upload_texture_rgba(64, 64, [&opaque](&pixels[0]), false)
end

terra app_init(app: &DemoApp, hidden: bool) : int
    if not C.SDL_Init(C.SDL_INIT_VIDEO) then return 1 end
    if not C.TTF_Init() then
        C.SDL_Quit()
        return 2
    end
    C.SDL_GL_SetAttribute(C.SDL_GL_DOUBLEBUFFER, 1)
    C.SDL_GL_SetAttribute(C.SDL_GL_DEPTH_SIZE, 0)

    var flags = [uint64]([SDL_WINDOW_OPENGL + SDL_WINDOW_RESIZABLE + SDL_WINDOW_HIGH_PIXEL_DENSITY])
    if hidden then flags = flags + [uint64]([SDL_WINDOW_HIDDEN]) end

    app.window = C.SDL_CreateWindow("TerraUI SDL+OpenGL Demo", 1280, 800, flags)
    if app.window == nil then
        C.TTF_Quit()
        C.SDL_Quit()
        return 3
    end

    app.glctx = C.SDL_GL_CreateContext(app.window)
    if app.glctx == nil then
        C.SDL_DestroyWindow(app.window)
        C.TTF_Quit()
        C.SDL_Quit()
        return 4
    end

    C.SDL_GL_SetSwapInterval(1)
    app.font = C.TTF_OpenFont([font_path], 16.0)
    if app.font == nil then
        C.SDL_GL_DestroyContext(app.glctx)
        C.SDL_DestroyWindow(app.window)
        C.TTF_Quit()
        C.SDL_Quit()
        return 5
    end

    C.glDisable(C.GL_DEPTH_TEST)
    C.glEnable(C.GL_BLEND)
    C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
    init_checker_texture(app)
    return 0
end

terra app_shutdown(app: &DemoApp)
    if app.checker_tex ~= 0 then C.glDeleteTextures(1, &app.checker_tex) end
    if app.font ~= nil then C.TTF_CloseFont(app.font) end
    if app.glctx ~= nil then C.SDL_GL_DestroyContext(app.glctx) end
    if app.window ~= nil then C.SDL_DestroyWindow(app.window) end
    C.TTF_Quit()
    C.SDL_Quit()
end

terra pump_input(app: &DemoApp, frame: &Frame, quit: &bool)
    frame.input.mouse_pressed = false
    frame.input.mouse_released = false
    frame.input.wheel_dx = 0
    frame.input.wheel_dy = 0

    var mx: float, my: float
    C.SDL_GetMouseState(&mx, &my)
    frame.input.mouse_x = mx
    frame.input.mouse_y = my

    var ev: C.SDL_Event
    while C.SDL_PollEvent(&ev) do
        if ev.type == [SDL_EVENT_QUIT] or ev.type == [SDL_EVENT_WINDOW_CLOSE_REQUESTED] then
            @quit = true
        elseif ev.type == [SDL_EVENT_MOUSE_MOTION] then
            frame.input.mouse_x = ev.motion.x
            frame.input.mouse_y = ev.motion.y
        elseif ev.type == [SDL_EVENT_MOUSE_BUTTON_DOWN] and ev.button.button == [SDL_BUTTON_LEFT] then
            frame.input.mouse_down = true
            frame.input.mouse_pressed = true
            frame.input.mouse_x = ev.button.x
            frame.input.mouse_y = ev.button.y
        elseif ev.type == [SDL_EVENT_MOUSE_BUTTON_UP] and ev.button.button == [SDL_BUTTON_LEFT] then
            frame.input.mouse_down = false
            frame.input.mouse_released = true
            frame.input.mouse_x = ev.button.x
            frame.input.mouse_y = ev.button.y
        elseif ev.type == [SDL_EVENT_MOUSE_WHEEL] then
            frame.input.wheel_dx = ev.wheel.x
            frame.input.wheel_dy = ev.wheel.y
            frame.input.mouse_x = ev.wheel.mouse_x
            frame.input.mouse_y = ev.wheel.mouse_y
        end
    end

    var vw: int, vh: int
    C.SDL_GetWindowSizeInPixels(app.window, &vw, &vh)
    frame.viewport_w = [float](vw)
    frame.viewport_h = [float](vh)
end

terra begin_frame(vw: int32, vh: int32)
    C.glViewport(0, 0, vw, vh)
    C.glClearColor(0.06, 0.07, 0.09, 1.0)
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

terra replay(app: &DemoApp, frame: &Frame)
    var packets: PacketArrayT
    var scissor_stack: ScissorArrayT
    var scissor_count: int32 = 0
    var packet_count = collect_packets(frame, &packets[0])
    var vw = [int32](frame.viewport_w)
    var vh = [int32](frame.viewport_h)

    begin_frame(vw, vh)

    for i = 0, packet_count do
        var p = packets[i]
        if p.kind == 5 then
            var cmd = frame.scissors[p.index]
            if cmd.is_begin then
                scissor_stack[scissor_count].x = [int32](cmd.x0)
                scissor_stack[scissor_count].y = [int32](frame.viewport_h - cmd.y1)
                scissor_stack[scissor_count].w = [int32](cmd.x1 - cmd.x0)
                scissor_stack[scissor_count].h = [int32](cmd.y1 - cmd.y0)
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
            draw_text(app, frame.texts[p.index])
        elseif p.kind == 4 then
            draw_image(app, frame.images[p.index])
        elseif p.kind == 6 then
            draw_custom(frame.customs[p.index])
        end
    end

    if scissor_count > 0 then
        var z: ScissorRect
        apply_scissor(false, z)
    end
    C.SDL_GL_SwapWindow(app.window)
end

terra maybe_handle_action(app: &DemoApp, frame: &Frame)
    if frame.action_name == nil then return end
    if C.strcmp(frame.action_name, "inspect") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Inspect")
    elseif C.strcmp(frame.action_name, "apply") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Apply")
    elseif C.strcmp(frame.action_name, "export") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Export")
    elseif C.strcmp(frame.action_name, "asset:terrain") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Terrain")
    elseif C.strcmp(frame.action_name, "asset:water") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Water")
    elseif C.strcmp(frame.action_name, "asset:roads") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Roads")
    elseif C.strcmp(frame.action_name, "asset:buildings") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Buildings")
    elseif C.strcmp(frame.action_name, "asset:labels") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Labels")
    elseif C.strcmp(frame.action_name, "asset:vegetation") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Vegetation")
    elseif C.strcmp(frame.action_name, "asset:lighting") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Lighting")
    elseif C.strcmp(frame.action_name, "asset:weather") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Weather")
    elseif C.strcmp(frame.action_name, "asset:vehicles") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Vehicles")
    elseif C.strcmp(frame.action_name, "asset:transit") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Transit")
    elseif C.strcmp(frame.action_name, "asset:utilities") == 0 then
        C.SDL_SetWindowTitle(app.window, "TerraUI Demo - Utilities")
    end
end

terra main(argc: int, argv: &rawstring)
    var max_frames: int = -1
    var hidden = false
    if argc > 1 then
        max_frames = C.atoi(argv[1])
    end
    if argc > 2 and C.strcmp(argv[2], "hidden") == 0 then
        hidden = true
    end

    var app: DemoApp
    app.window = nil
    app.glctx = nil
    app.font = nil
    app.checker_tex = 0

    var rc = app_init(&app, hidden)
    if rc ~= 0 then
        return rc
    end

    var frame: Frame
    [init_q](&frame)

    var quit = false
    var frames = 0
    while not quit and (max_frames < 0 or frames < max_frames) do
        pump_input(&app, &frame, &quit)
        [run_q](&frame)
        maybe_handle_action(&app, &frame)
        replay(&app, &frame)
        frames = frames + 1
    end

    app_shutdown(&app)
    return 0
end

terralib.saveobj(out_path, "executable", { main = main }, link_flags)
print("built demo:", out_path)
print("font:", font_path)
