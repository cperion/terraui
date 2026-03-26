local terraui = require("lib/terraui")
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")
local sdl_gl_backend = require("lib/sdl_gl_backend")

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

local link_flags = split_ws((sh("pkg-config --libs sdl3 sdl3-ttf") or "") .. " -lGL -lm")
local sdl = sdl_gl_backend.new(font_path)
local C = sdl.C

-- UI definition is shared with the Love2D demo
local decl = require("examples/demo_ui_def")

local ui = terraui.dsl()
local function rgba(r,g,b,a) return ui.rgba(r,g,b,a) end


struct DemoApp {
    backend: sdl.Session
    checker_tex: uint32
    terrain_tex: uint32
    water_tex: uint32
    roads_tex: uint32
    blueprint_tex: uint32
    heatmap_tex: uint32

    selected_tool: rawstring
    selected_asset: rawstring
    status_primary: rawstring
    status_secondary: rawstring
    hint_text: rawstring
    preview_image: rawstring
    preview_title: rawstring
    detail_a: rawstring
    detail_b: rawstring
    footer_text: rawstring
    mode_summary: rawstring
    mode_line_1: rawstring
    mode_line_2: rawstring
    mode_line_3: rawstring
    asset_meta_1: rawstring
    asset_meta_2: rawstring
    asset_meta_3: rawstring
    event_1: rawstring
    event_2: rawstring
    event_3: rawstring
    progress_a: float
    progress_b: float
    accent: compile.Color
    tick: int32
    debug_mode: int32      -- 0=off, 1=bounds, 2=bounds+padding, 3=full
    debug_hover: int32     -- node index under mouse (-1 for none)
}

local bound = bind.bind_component(decl, { text_backend = sdl.text_backend })
local planned = plan.plan_component(bound)
local kernel = compile.compile_component(planned, { text_backend = sdl.text_backend })
local Frame = kernel:frame_type()
local init_q = kernel.init_fn
local layout_q = kernel.run_fn
local hit_test_q = kernel.run_fn
local input_q = kernel.run_fn
local run_q = kernel.run_fn

local max_packets = #planned.paints + #planned.texts + #planned.images + (#planned.clips * 2) + #planned.customs
if max_packets < 1 then max_packets = 1 end
local max_scissors = #planned.clips
if max_scissors < 1 then max_scissors = 1 end
local node_count = #planned.nodes
local debug_scroll_log_path = "/tmp/terraui-scroll-debug.log"
local debug_geom_log_path = "/tmp/terraui-geom-debug.log"

terra debug_scroll_input(frame: &Frame)
    var f = C.fopen([debug_scroll_log_path], "a")
    if f ~= nil then
        C.fprintf(f, "[scroll-debug] mouse=(%.1f, %.1f) down=%d pressed=%d released=%d wheel=(%.3f, %.3f) viewport=(%.1f, %.1f) hot=%d active=%d\n",
            frame.input.mouse_x, frame.input.mouse_y,
            frame.input.mouse_down, frame.input.mouse_pressed, frame.input.mouse_released,
            frame.input.wheel_dx, frame.input.wheel_dy,
            frame.viewport_w, frame.viewport_h,
            frame.hit.hot, frame.hit.active)
        C.fflush(f)
        C.fclose(f)
    end
end

terra debug_scroll_state(frame: &Frame, label: rawstring)
    var f = C.fopen([debug_scroll_log_path], "a")
    if f == nil then return end
    C.fprintf(f, "[scroll-debug] %s rects=%d borders=%d texts=%d scissors=%d\n", label, frame.rect_count, frame.border_count, frame.text_count, frame.scissor_count)
    for i = 0, [node_count - 1] do
        var max_x = frame.nodes[i].content_extent_w - frame.nodes[i].content_w
        var max_y = frame.nodes[i].content_extent_h - frame.nodes[i].content_h
        if max_x < 0.0f then max_x = 0.0f end
        if max_y < 0.0f then max_y = 0.0f end
        if frame.nodes[i].scroll_need_x or frame.nodes[i].scroll_need_y or
           frame.nodes[i].scroll_x ~= 0.0f or frame.nodes[i].scroll_y ~= 0.0f or
           max_x > 0.0f or max_y > 0.0f then
            var in_rect = frame.input.mouse_x >= frame.nodes[i].x and frame.input.mouse_x <= frame.nodes[i].x + frame.nodes[i].w and frame.input.mouse_y >= frame.nodes[i].y and frame.input.mouse_y <= frame.nodes[i].y + frame.nodes[i].h
            var in_clip = frame.input.mouse_x >= frame.nodes[i].clip_x0 and frame.input.mouse_x <= frame.nodes[i].clip_x1 and frame.input.mouse_y >= frame.nodes[i].clip_y0 and frame.input.mouse_y <= frame.nodes[i].clip_y1
            C.fprintf(f, "  node=%d rect=(%.1f, %.1f %.1f x %.1f) clip=(%.1f, %.1f -> %.1f, %.1f) content=(%.1f, %.1f %.1f x %.1f) extent=(%.1f, %.1f) need=(%d,%d) scroll=(%.1f, %.1f) max=(%.1f, %.1f) visible=%d enabled=%d in_rect=%d in_clip=%d\n",
                i,
                frame.nodes[i].x, frame.nodes[i].y, frame.nodes[i].w, frame.nodes[i].h,
                frame.nodes[i].clip_x0, frame.nodes[i].clip_y0, frame.nodes[i].clip_x1, frame.nodes[i].clip_y1,
                frame.nodes[i].content_x, frame.nodes[i].content_y, frame.nodes[i].content_w, frame.nodes[i].content_h,
                frame.nodes[i].content_extent_w, frame.nodes[i].content_extent_h,
                frame.nodes[i].scroll_need_x, frame.nodes[i].scroll_need_y,
                frame.nodes[i].scroll_x, frame.nodes[i].scroll_y,
                max_x, max_y,
                frame.nodes[i].visible, frame.nodes[i].enabled, in_rect, in_clip)
        end
    end
    if C.strcmp(label, "after run") == 0 then
        for i = 0, frame.border_count - 1 do
            if frame.borders[i].y < 140.0f then
                C.fprintf(f, "  border=%d rect=(%.1f, %.1f %.1f x %.1f) sides=(%.1f, %.1f, %.1f, %.1f) z=%.1f seq=%u\n",
                    i,
                    frame.borders[i].x, frame.borders[i].y, frame.borders[i].w, frame.borders[i].h,
                    frame.borders[i].left, frame.borders[i].top, frame.borders[i].right, frame.borders[i].bottom,
                    frame.borders[i].z, frame.borders[i].seq)
            end
        end
        for i = 0, frame.text_count - 1 do
            if frame.texts[i].y < 140.0f then
                C.fprintf(f, "  text=%d rect=(%.1f, %.1f %.1f x %.1f) size=%.1f text=%s\n",
                    i,
                    frame.texts[i].x, frame.texts[i].y, frame.texts[i].w, frame.texts[i].h,
                    frame.texts[i].font_size,
                    terralib.select(frame.texts[i].text ~= nil, frame.texts[i].text, "<nil>"))
            end
        end
    end
    C.fflush(f)
    C.fclose(f)
end

terra debug_geom_state(frame: &Frame, label: rawstring)
    var f = C.fopen([debug_scroll_log_path], "a")
    if f == nil then return end
    C.fprintf(f, "[geom-debug] %s viewport=(%.1f x %.1f) rects=%d borders=%d texts=%d scissors=%d\n",
        label, frame.viewport_w, frame.viewport_h, frame.rect_count, frame.border_count, frame.text_count, frame.scissor_count)
    for i = 0, [node_count - 1] do
        if frame.nodes[i].x < frame.viewport_w and frame.nodes[i].y < frame.viewport_h and frame.nodes[i].w > 0.0f and frame.nodes[i].h > 0.0f then
            if frame.nodes[i].y < 220.0f or frame.nodes[i].x > 900.0f then
                C.fprintf(f, "  node=%d rect=(%.1f, %.1f %.1f x %.1f) content=(%.1f, %.1f %.1f x %.1f) clip=(%.1f, %.1f -> %.1f, %.1f)\n",
                    i,
                    frame.nodes[i].x, frame.nodes[i].y, frame.nodes[i].w, frame.nodes[i].h,
                    frame.nodes[i].content_x, frame.nodes[i].content_y, frame.nodes[i].content_w, frame.nodes[i].content_h,
                    frame.nodes[i].clip_x0, frame.nodes[i].clip_y0, frame.nodes[i].clip_x1, frame.nodes[i].clip_y1)
            end
        end
    end
    for i = 0, frame.border_count - 1 do
        if frame.borders[i].y < 220.0f or frame.borders[i].x > 900.0f then
            C.fprintf(f, "  border=%d rect=(%.1f, %.1f %.1f x %.1f) sides=(%.1f, %.1f, %.1f, %.1f) z=%.1f seq=%u\n",
                i,
                frame.borders[i].x, frame.borders[i].y, frame.borders[i].w, frame.borders[i].h,
                frame.borders[i].left, frame.borders[i].top, frame.borders[i].right, frame.borders[i].bottom,
                frame.borders[i].z, frame.borders[i].seq)
        end
    end
    for i = 0, frame.text_count - 1 do
        if frame.texts[i].y < 220.0f or frame.texts[i].x > 900.0f then
            C.fprintf(f, "  text=%d rect=(%.1f, %.1f %.1f x %.1f) size=%.1f wrap=%d align=%d text=%s\n",
                i,
                frame.texts[i].x, frame.texts[i].y, frame.texts[i].w, frame.texts[i].h,
                frame.texts[i].font_size, frame.texts[i].wrap, frame.texts[i].align,
                terralib.select(frame.texts[i].text ~= nil, frame.texts[i].text, "<nil>"))
        end
    end
    C.fflush(f)
    C.fclose(f)
end

terra color(r: float, g: float, b: float, a: float) : compile.Color
    return sdl.color(r, g, b, a)
end

terra clamp01(x: float) : float
    if x < 0.0f then return 0.0f end
    if x > 1.0f then return 1.0f end
    return x
end

terra lerp_color(a: compile.Color, b: compile.Color, t: float) : compile.Color
    var u = clamp01(t)
    return color(
        a.r + (b.r - a.r) * u,
        a.g + (b.g - a.g) * u,
        a.b + (b.b - a.b) * u,
        a.a + (b.a - a.a) * u)
end

terra shade(a: compile.Color, k: float) : compile.Color
    return color(a.r * k, a.g * k, a.b * k, a.a)
end

terra draw_image(app: &DemoApp, cmd: compile.ImageCmd)
    if cmd.image_id == nil then return end

    if C.strcmp(cmd.image_id, "terrain") == 0 then
        sdl.draw_textured_quad(app.terrain_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    elseif C.strcmp(cmd.image_id, "water") == 0 then
        sdl.draw_textured_quad(app.water_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    elseif C.strcmp(cmd.image_id, "roads") == 0 then
        sdl.draw_textured_quad(app.roads_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    elseif C.strcmp(cmd.image_id, "blueprint") == 0 then
        sdl.draw_textured_quad(app.blueprint_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    elseif C.strcmp(cmd.image_id, "heatmap") == 0 then
        sdl.draw_textured_quad(app.heatmap_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    else
        sdl.draw_textured_quad(app.checker_tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.tint)
    end
end

terra draw_custom(app: &DemoApp, cmd: compile.CustomCmd)
    if cmd.kind == nil then return end

    if C.strcmp(cmd.kind, "preview_guides") == 0 then
        var accent = app.accent
        var pulse = 0.45f + 0.25f * C.sinf([float](app.tick) * 0.09f)
        var inner = 18.0f + 4.0f * pulse

        C.glColor4f(0.02, 0.03, 0.04, 0.14)
        sdl.gl_quad(cmd.x, cmd.y, cmd.w, 16)
        sdl.gl_quad(cmd.x, cmd.y + cmd.h - 16, cmd.w, 16)
        sdl.gl_quad(cmd.x, cmd.y, 16, cmd.h)
        sdl.gl_quad(cmd.x + cmd.w - 16, cmd.y, 16, cmd.h)

        C.glColor4f(1.0, 1.0, 1.0, 0.10)
        var step: float = 32
        var x = cmd.x + step
        while x < cmd.x + cmd.w do
            C.glBegin(C.GL_LINES)
            C.glVertex2f(x, cmd.y)
            C.glVertex2f(x, cmd.y + cmd.h)
            C.glEnd()
            x = x + step
        end
        var y = cmd.y + step
        while y < cmd.y + cmd.h do
            C.glBegin(C.GL_LINES)
            C.glVertex2f(cmd.x, y)
            C.glVertex2f(cmd.x + cmd.w, y)
            C.glEnd()
            y = y + step
        end

        sdl.gl_color(lerp_color(accent, color(1.0f, 1.0f, 1.0f, 1.0f), 0.35f), 0.60f + pulse * 0.25f)
        C.glBegin(C.GL_LINES)
        C.glVertex2f(cmd.x + cmd.w * 0.5, cmd.y)
        C.glVertex2f(cmd.x + cmd.w * 0.5, cmd.y + cmd.h)
        C.glVertex2f(cmd.x, cmd.y + cmd.h * 0.5)
        C.glVertex2f(cmd.x + cmd.w, cmd.y + cmd.h * 0.5)
        C.glEnd()

        C.glColor4f(accent.r, accent.g, accent.b, 0.35f + pulse * 0.20f)
        sdl.gl_line_rect(cmd.x + inner, cmd.y + inner, cmd.w - inner * 2.0f, cmd.h - inner * 2.0f)

        if C.strcmp(app.selected_tool, "Paint") == 0 then
            C.glColor4f(accent.r, accent.g, accent.b, 0.45f)
            sdl.gl_line_rect(cmd.x + cmd.w * 0.5f - 34, cmd.y + cmd.h * 0.5f - 34, 68, 68)
        elseif C.strcmp(app.selected_tool, "Lighting") == 0 then
            C.glColor4f(1.0f, 0.92f, 0.54f, 0.32f)
            C.glBegin(C.GL_LINES)
            C.glVertex2f(cmd.x + 30, cmd.y + 24)
            C.glVertex2f(cmd.x + cmd.w - 30, cmd.y + cmd.h - 24)
            C.glVertex2f(cmd.x + 30, cmd.y + cmd.h - 24)
            C.glVertex2f(cmd.x + cmd.w - 30, cmd.y + 24)
            C.glEnd()
        elseif C.strcmp(app.selected_tool, "Export") == 0 then
            C.glColor4f(0.90f, 0.96f, 1.0f, 0.30f)
            sdl.gl_line_rect(cmd.x + 10, cmd.y + 10, cmd.w - 20, cmd.h - 20)
        end
    elseif C.strcmp(cmd.kind, "inspector_chart") == 0 then
        var accent = app.accent
        C.glColor4f(0.14, 0.16, 0.20, 1.0)
        sdl.gl_quad(cmd.x, cmd.y, cmd.w, cmd.h)
        C.glColor4f(0.22, 0.24, 0.28, 1.0)
        sdl.gl_line_rect(cmd.x, cmd.y, cmd.w, cmd.h)
        var bars = 12
        var bar_w = (cmd.w - 26) / [float](bars)
        for i = 0, bars - 1 do
            var wave = 0.5f + 0.5f * C.sinf([float](app.tick + i * 7) * 0.13f)
            var h = 16.0f + wave * (cmd.h - 30.0f)
            var bx = cmd.x + 10 + [float](i) * bar_w
            var by = cmd.y + cmd.h - 8 - h
            var c = lerp_color(shade(accent, 0.65f), color(0.82f, 0.88f, 1.0f, 1.0f), [float](i) / [float](bars))
            C.glColor4f(c.r, c.g, c.b, 0.96)
            sdl.gl_quad(bx, by, bar_w - 4, h)
        end
    elseif C.strcmp(cmd.kind, "accent_swatches") == 0 then
        var accent = app.accent
        var palette0 = shade(accent, 0.45f)
        var palette1 = shade(accent, 0.72f)
        var palette2 = accent
        var palette3 = lerp_color(accent, color(1.0f, 1.0f, 1.0f, 1.0f), 0.28f)
        var palette4 = lerp_color(accent, color(1.0f, 0.86f, 0.36f, 1.0f), 0.36f)
        var sw = (cmd.w - 28.0f) / 5.0f
        var y0 = cmd.y + 8.0f
        var h = cmd.h - 16.0f
        var cols : compile.Color[5]
        cols[0] = palette0; cols[1] = palette1; cols[2] = palette2; cols[3] = palette3; cols[4] = palette4
        for i = 0, 4 do
            var c = cols[i]
            var x0 = cmd.x + 8.0f + [float](i) * sw
            C.glColor4f(c.r, c.g, c.b, 1.0f)
            sdl.gl_quad(x0, y0, sw - 4.0f, h)
            C.glColor4f(1.0f, 1.0f, 1.0f, 0.18f)
            sdl.gl_line_rect(x0, y0, sw - 4.0f, h)
        end
    elseif C.strcmp(cmd.kind, "timeline_wave") == 0 then
        var accent = app.accent
        C.glColor4f(0.12, 0.14, 0.18, 1.0)
        sdl.gl_quad(cmd.x, cmd.y, cmd.w, cmd.h)
        C.glColor4f(0.22, 0.24, 0.28, 1.0)
        sdl.gl_line_rect(cmd.x, cmd.y, cmd.w, cmd.h)
        C.glColor4f(accent.r, accent.g, accent.b, 0.35f)
        sdl.gl_quad(cmd.x + 12, cmd.y + cmd.h - 22, cmd.w - 24, 6)
        C.glLineWidth(2.0f)
        C.glColor4f(accent.r, accent.g, accent.b, 0.95f)
        C.glBegin(C.GL_LINE_STRIP)
        for i = 0, 48 do
            var t = [float](i) / 48.0f
            var phase = [float](app.tick) * 0.07f
            var y = cmd.y + cmd.h * 0.55f + C.sinf(t * 8.5f + phase) * 11.0f + C.sinf(t * 21.0f + phase * 1.8f) * 4.5f
            C.glVertex2f(cmd.x + 10.0f + t * (cmd.w - 20.0f), y)
        end
        C.glEnd()
        C.glLineWidth(1.0f)
    else
        C.glColor4f(1.0, 0.4, 0.1, 1.0)
        sdl.gl_line_rect(cmd.x, cmd.y, cmd.w, cmd.h)
    end
end

terra init_texture_pattern(tex_out: &uint32, pattern: int32)
    var pixels: uint8[128 * 128 * 4]
    for y = 0, 128 do
        for x = 0, 128 do
            var idx = (y * 128 + x) * 4
            if pattern == 0 then
                var dark = ((x / 16) + (y / 16)) % 2 == 0
                if dark then
                    pixels[idx + 0] = 72; pixels[idx + 1] = 78; pixels[idx + 2] = 90; pixels[idx + 3] = 255
                else
                    pixels[idx + 0] = 160; pixels[idx + 1] = 168; pixels[idx + 2] = 182; pixels[idx + 3] = 255
                end
            elseif pattern == 1 then
                pixels[idx + 0] = 60 + [uint8]((x * 35) / 128)
                pixels[idx + 1] = 96 + [uint8]((y * 90) / 128)
                pixels[idx + 2] = 48 + [uint8](((x + y) * 20) / 128)
                pixels[idx + 3] = 255
                if ((x / 12) + (y / 10)) % 5 == 0 then
                    pixels[idx + 0] = 126; pixels[idx + 1] = 182; pixels[idx + 2] = 86
                end
            elseif pattern == 2 then
                pixels[idx + 0] = 34
                pixels[idx + 1] = 84 + [uint8]((x * 44) / 128)
                pixels[idx + 2] = 156 + [uint8]((y * 68) / 128)
                pixels[idx + 3] = 255
                if (y / 10) % 3 == 0 then
                    pixels[idx + 0] = 72; pixels[idx + 1] = 170; pixels[idx + 2] = 220
                end
            elseif pattern == 3 then
                pixels[idx + 0] = 76
                pixels[idx + 1] = 78
                pixels[idx + 2] = 84
                pixels[idx + 3] = 255
                if x % 24 < 6 or y % 24 < 6 then
                    pixels[idx + 0] = 120; pixels[idx + 1] = 124; pixels[idx + 2] = 132
                end
                if x % 32 >= 14 and x % 32 <= 18 then
                    pixels[idx + 0] = 220; pixels[idx + 1] = 190; pixels[idx + 2] = 68
                end
            elseif pattern == 4 then
                pixels[idx + 0] = 24 + [uint8]((x * 40) / 128)
                pixels[idx + 1] = 34 + [uint8]((y * 24) / 128)
                pixels[idx + 2] = 76 + [uint8]((x * 86) / 128)
                pixels[idx + 3] = 255
                if x % 16 == 0 or y % 16 == 0 then
                    pixels[idx + 0] = 94; pixels[idx + 1] = 168; pixels[idx + 2] = 255
                end
            else
                pixels[idx + 0] = [uint8]((x * 255) / 128)
                pixels[idx + 1] = [uint8]((y * 255) / 128)
                pixels[idx + 2] = [uint8](255 - ((x * 255) / 128))
                pixels[idx + 3] = 255
            end
        end
    end
    @tex_out = sdl.upload_texture_rgba(128, 128, [&opaque](&pixels[0]), false)
end

terra init_textures(app: &DemoApp)
    init_texture_pattern(&app.checker_tex, 0)
    init_texture_pattern(&app.terrain_tex, 1)
    init_texture_pattern(&app.water_tex, 2)
    init_texture_pattern(&app.roads_tex, 3)
    init_texture_pattern(&app.blueprint_tex, 4)
    init_texture_pattern(&app.heatmap_tex, 5)
end

terra set_events(app: &DemoApp, e1: rawstring, e2: rawstring, e3: rawstring)
    app.event_1 = e1
    app.event_2 = e2
    app.event_3 = e3
end

terra apply_tool_profile(app: &DemoApp, tool_name: rawstring)
    app.selected_tool = tool_name

    if C.strcmp(tool_name, "Inspect") == 0 then
        app.status_secondary = "Reviewing bounds, clips, and layout metadata"
        app.mode_summary = "Inspect mode: hover authored nodes and inspect kernel output"
        app.mode_line_1 = "• highlight bounds and clipping regions"
        app.mode_line_2 = "• surface command order from merged streams"
        app.mode_line_3 = "• keep pointer capture transparent over overlays"
    elseif C.strcmp(tool_name, "Paint") == 0 then
        app.status_secondary = "Brush preview locked to current selection"
        app.mode_summary = "Paint mode: stamp and adjust accent-weighted coverage"
        app.mode_line_1 = "• use overlay reticle as brush aperture"
        app.mode_line_2 = "• animate fill progress against the preview target"
        app.mode_line_3 = "• verify clipped content and hit routing while painting"
    elseif C.strcmp(tool_name, "Lighting") == 0 then
        app.status_secondary = "Evaluating highlights, fog, and exposure"
        app.mode_summary = "Lighting mode: compare tonal balance and spatial emphasis"
        app.mode_line_1 = "• inspect focal center and horizon-safe framing"
        app.mode_line_2 = "• evaluate guide overlays against emissive regions"
        app.mode_line_3 = "• monitor chart response while exposure changes"
    else
        app.status_secondary = "Preparing artifact bundle from compiled UI state"
        app.mode_summary = "Export mode: validate packaging, replay order, and status reporting"
        app.mode_line_1 = "• keep diagnostics stable under repeated replay"
        app.mode_line_2 = "• verify text cache reuse before snapshotting"
        app.mode_line_3 = "• surface final preview metadata in the inspector"
    end
end

terra apply_asset_profile(app: &DemoApp, asset_name: rawstring)
    app.selected_asset = asset_name

    if C.strcmp(asset_name, "Terrain") == 0 then
        app.preview_image = "terrain"
        app.preview_title = "Terrain composite"
        app.detail_a = "Asset type: tile set"
        app.detail_b = "Build channel: sculpt preview"
        app.hint_text = "Terrain preview: contour guides + focal center"
        app.asset_meta_1 = "Resolution: 2048 x 2048"
        app.asset_meta_2 = "Channels: albedo, height, roughness"
        app.asset_meta_3 = "Last bake: 00:01.4 ago"
        app.accent = color(0.42, 0.70, 0.32, 1.0)
        app.progress_a = 174
        app.progress_b = 126
    elseif C.strcmp(asset_name, "Water") == 0 then
        app.preview_image = "water"
        app.preview_title = "Water simulation"
        app.detail_a = "Asset type: fluid layer"
        app.detail_b = "Build channel: ripple solve"
        app.hint_text = "Water preview: horizon-safe crop and wave field"
        app.asset_meta_1 = "Resolution: 1536 x 1536"
        app.asset_meta_2 = "Channels: flow, foam, depth"
        app.asset_meta_3 = "Last bake: 00:00.9 ago"
        app.accent = color(0.26, 0.64, 0.92, 1.0)
        app.progress_a = 142
        app.progress_b = 188
    elseif C.strcmp(asset_name, "Roads") == 0 then
        app.preview_image = "roads"
        app.preview_title = "Road network"
        app.detail_a = "Asset type: lane graph"
        app.detail_b = "Build channel: signage bake"
        app.hint_text = "Road preview: guide grid aligned to lane stitching"
        app.asset_meta_1 = "Resolution: 1024 x 2048"
        app.asset_meta_2 = "Channels: asphalt, decals, traffic density"
        app.asset_meta_3 = "Last bake: 00:02.1 ago"
        app.accent = color(0.90, 0.74, 0.22, 1.0)
        app.progress_a = 196
        app.progress_b = 104
    elseif C.strcmp(asset_name, "Blueprint") == 0 then
        app.preview_image = "blueprint"
        app.preview_title = "Blueprint overlay"
        app.detail_a = "Asset type: design layer"
        app.detail_b = "Build channel: markup review"
        app.hint_text = "Blueprint preview: read margins, overlays, and label fit"
        app.asset_meta_1 = "Resolution: 4096 x 2160"
        app.asset_meta_2 = "Channels: notes, zones, anchors"
        app.asset_meta_3 = "Last bake: 00:00.6 ago"
        app.accent = color(0.36, 0.62, 1.0, 1.0)
        app.progress_a = 118
        app.progress_b = 152
    else
        app.preview_image = "heatmap"
        app.preview_title = "Heatmap diagnostics"
        app.detail_a = "Asset type: analysis pass"
        app.detail_b = "Build channel: hotspot review"
        app.hint_text = "Heatmap preview: compare hot zones against focal frame"
        app.asset_meta_1 = "Resolution: 1920 x 1080"
        app.asset_meta_2 = "Channels: occupancy, intensity, confidence"
        app.asset_meta_3 = "Last bake: 00:01.1 ago"
        app.accent = color(0.98, 0.42, 0.28, 1.0)
        app.progress_a = 156
        app.progress_b = 86
    end
end

terra app_init(app: &DemoApp, hidden: bool) : int
    var rc = sdl.init(&app.backend, "TerraUI SDL+OpenGL Demo", 1380, 860, hidden)
    if rc ~= 0 then return rc end

    init_textures(app)

    app.status_primary = "Ready"
    app.footer_text = "Cursor idle"
    app.tick = 0
    apply_tool_profile(app, "Inspect")
    apply_asset_profile(app, "Terrain")
    set_events(app,
        "Event: compiled kernel reused from memoized artifact",
        "Event: preview overlay attached through floating target",
        "Event: text now cached into reusable GL textures")
    return 0
end

terra app_shutdown(app: &DemoApp)
    if app.checker_tex ~= 0 then C.glDeleteTextures(1, &app.checker_tex) end
    if app.terrain_tex ~= 0 then C.glDeleteTextures(1, &app.terrain_tex) end
    if app.water_tex ~= 0 then C.glDeleteTextures(1, &app.water_tex) end
    if app.roads_tex ~= 0 then C.glDeleteTextures(1, &app.roads_tex) end
    if app.blueprint_tex ~= 0 then C.glDeleteTextures(1, &app.blueprint_tex) end
    if app.heatmap_tex ~= 0 then C.glDeleteTextures(1, &app.heatmap_tex) end
    sdl.shutdown(&app.backend)
end

terra pump_input(app: &DemoApp, frame: &Frame, quit: &bool)
    frame.input.mouse_pressed = false
    frame.input.mouse_released = false
    frame.input.wheel_dx = 0.0f
    frame.input.wheel_dy = 0.0f

    var have_mouse_pos = false
    var event_mouse_x: float = frame.input.mouse_x
    var event_mouse_y: float = frame.input.mouse_y

    var ev: C.SDL_Event
    while C.SDL_PollEvent(&ev) do
        if ev.type == C.SDL_EVENT_QUIT or ev.type == C.SDL_EVENT_WINDOW_CLOSE_REQUESTED then
            @quit = true
        elseif ev.type == C.SDL_EVENT_KEY_DOWN then
            if ev.key.key == C.SDLK_D then
                app.debug_mode = (app.debug_mode + 1) % 4
            elseif ev.key.key == C.SDLK_ESCAPE then
                @quit = true
            end
        elseif ev.type == C.SDL_EVENT_MOUSE_MOTION then
            event_mouse_x = ev.motion.x
            event_mouse_y = ev.motion.y
            have_mouse_pos = true
        elseif ev.type == C.SDL_EVENT_MOUSE_BUTTON_DOWN and ev.button.button == 1 then
            frame.input.mouse_down = true
            frame.input.mouse_pressed = true
            event_mouse_x = ev.button.x
            event_mouse_y = ev.button.y
            have_mouse_pos = true
        elseif ev.type == C.SDL_EVENT_MOUSE_BUTTON_UP and ev.button.button == 1 then
            frame.input.mouse_down = false
            frame.input.mouse_released = true
            event_mouse_x = ev.button.x
            event_mouse_y = ev.button.y
            have_mouse_pos = true
        elseif ev.type == C.SDL_EVENT_MOUSE_WHEEL then
            var wx = ev.wheel.x
            var wy = ev.wheel.y
            if ev.wheel.integer_x ~= 0 then wx = [float](ev.wheel.integer_x) end
            if ev.wheel.integer_y ~= 0 then wy = [float](ev.wheel.integer_y) end
            if ev.wheel.direction == C.SDL_MOUSEWHEEL_FLIPPED then
                wx = -wx
                wy = -wy
            end
            frame.input.wheel_dx = frame.input.wheel_dx + wx
            frame.input.wheel_dy = frame.input.wheel_dy + wy
            event_mouse_x = ev.wheel.mouse_x
            event_mouse_y = ev.wheel.mouse_y
            have_mouse_pos = true
        end
    end

    if have_mouse_pos then
        frame.input.mouse_x = event_mouse_x
        frame.input.mouse_y = event_mouse_y
    else
        var mx: float, my: float
        C.SDL_GetMouseState(&mx, &my)
        frame.input.mouse_x = mx
        frame.input.mouse_y = my
    end

    var vw: int, vh: int
    C.SDL_GetWindowSizeInPixels(app.backend.window, &vw, &vh)
    frame.viewport_w = [float](vw)
    frame.viewport_h = [float](vh)
end

terra sync_params(frame: &Frame, app: &DemoApp)
    frame.text_backend_state = [&opaque](&app.backend.text)
    -- param order matches `params` declaration above.
    frame.params.p0 = app.selected_tool
    frame.params.p1 = app.selected_asset
    frame.params.p2 = app.status_primary
    frame.params.p3 = app.status_secondary
    frame.params.p4 = app.hint_text
    frame.params.p5 = app.preview_image
    frame.params.p6 = app.preview_title
    frame.params.p7 = app.detail_a
    frame.params.p8 = app.detail_b
    frame.params.p9 = app.footer_text
    frame.params.p10 = app.progress_a
    frame.params.p11 = app.progress_b
    frame.params.p12 = app.accent
    frame.params.p13 = app.mode_summary
    frame.params.p14 = app.mode_line_1
    frame.params.p15 = app.mode_line_2
    frame.params.p16 = app.mode_line_3
    frame.params.p17 = app.asset_meta_1
    frame.params.p18 = app.asset_meta_2
    frame.params.p19 = app.asset_meta_3
    frame.params.p20 = app.event_1
    frame.params.p21 = app.event_2
    frame.params.p22 = app.event_3
end

local replay = sdl.make_replay(Frame, max_packets, max_scissors, DemoApp, draw_image, draw_custom)

---------------------------------------------------------------------------
-- Debug overlay  (toggled by D key, cycles: off → bounds → +padding → +info)
---------------------------------------------------------------------------

-- Compile-time metadata per node
local DebugNodeMeta = struct {
    label: rawstring        -- short human-readable name
    axis: int32             -- 0=row, 1=column
    has_clip: bool
    has_scroll: bool
    has_float: bool
    has_text: bool
    depth: int32            -- nesting depth for color cycling
}

-- Build the metadata table at compile time
local debug_meta_values = {}
do
    -- Compute depth for each node
    local depth_map = {}
    for i, node in ipairs(planned.nodes) do
        if node.parent == nil then
            depth_map[node.index] = 0
        else
            depth_map[node.index] = (depth_map[node.parent] or 0) + 1
        end
    end

    local labels = planned._stable_id_labels or {}
    for i, node in ipairs(planned.nodes) do
        local idx = node.index
        local lbl = labels[idx] or ("#" .. idx)
        local axis_val = 0
        if node.axis and node.axis.kind == "Column" then axis_val = 1 end
        table.insert(debug_meta_values, {
            label = lbl,
            axis = axis_val,
            has_clip = node.clip_slot ~= nil,
            has_scroll = node.scroll_slot ~= nil,
            has_float = node.float_slot ~= nil,
            has_text = node.text_slot ~= nil,
            depth = depth_map[idx] or 0,
        })
    end
end

-- HSL-to-RGB for depth-based color cycling
terra hsl_to_rgb(h: float, s: float, l: float, out_r: &float, out_g: &float, out_b: &float)
    var c = (1.0f - C.fabsf(2.0f * l - 1.0f)) * s
    var hp = h / 60.0f
    var x = c * (1.0f - C.fabsf(C.fmodf(hp, 2.0f) - 1.0f))
    var r1: float, g1: float, b1: float = 0.0f, 0.0f, 0.0f
    if hp < 1.0f then      r1 = c; g1 = x; b1 = 0
    elseif hp < 2.0f then  r1 = x; g1 = c; b1 = 0
    elseif hp < 3.0f then  r1 = 0; g1 = c; b1 = x
    elseif hp < 4.0f then  r1 = 0; g1 = x; b1 = c
    elseif hp < 5.0f then  r1 = x; g1 = 0; b1 = c
    else                   r1 = c; g1 = 0; b1 = x
    end
    var m = l - c * 0.5f
    @out_r = r1 + m
    @out_g = g1 + m
    @out_b = b1 + m
end

-- Global metadata array — initialized via codegen since rawstring can't go
-- through terralib.new.  Each label is a terralib.constant string.
local debug_meta_arr = global(DebugNodeMeta[node_count])
local debug_meta_init_stmts = terralib.newlist()
for i, m in ipairs(debug_meta_values) do
    local lbl = terralib.constant(rawstring, m.label)
    local idx = i - 1
    debug_meta_init_stmts:insert(quote
        debug_meta_arr[idx].label = lbl
        debug_meta_arr[idx].axis = [m.axis]
        debug_meta_arr[idx].has_clip = [m.has_clip]
        debug_meta_arr[idx].has_scroll = [m.has_scroll]
        debug_meta_arr[idx].has_float = [m.has_float]
        debug_meta_arr[idx].has_text = [m.has_text]
        debug_meta_arr[idx].depth = [m.depth]
    end)
end
terra init_debug_meta()
    [debug_meta_init_stmts]
end

terra draw_debug_overlay(session: &sdl.Session, app: &DemoApp, frame: &Frame)
    if app.debug_mode == 0 then return end

    -- Disable any lingering scissor
    C.glDisable(C.GL_SCISSOR_TEST)

    var mx = frame.input.mouse_x
    var my = frame.input.mouse_y
    var hover_node: int32 = -1
    var hover_area: float = 1e18f

    C.glEnable(C.GL_BLEND)
    C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)

    -- Pass 1: draw node bounds
    for i = 0, [node_count - 1] do
        var n = frame.nodes[i]
        if n.visible and n.w >= 1 and n.h >= 1 then
            var meta = debug_meta_arr[i]

            -- Depth-based hue cycling (golden angle ~137.5°)
            var hue = C.fmodf([float](meta.depth) * 137.5f, 360.0f)
            var r: float, g: float, b: float
            hsl_to_rgb(hue, 0.75f, 0.55f, &r, &g, &b)

            -- Brighten scroll/clip/float nodes
            if meta.has_scroll then
                r = 0.2f; g = 0.85f; b = 0.95f   -- cyan
            elseif meta.has_clip then
                r = 0.95f; g = 0.6f; b = 0.2f     -- orange
            elseif meta.has_float then
                r = 0.9f; g = 0.3f; b = 0.9f      -- magenta
            end

            -- Mode >= 2: draw padding fill
            if app.debug_mode >= 2 then
                -- Padding region = outer box minus content box, semi-transparent
                C.glColor4f(r, g, b, 0.06f)
                -- Top padding strip
                sdl.gl_quad(n.x, n.y, n.w, n.content_y - n.y)
                -- Bottom padding strip
                sdl.gl_quad(n.x, n.content_y + n.content_h, n.w, (n.y + n.h) - (n.content_y + n.content_h))
                -- Left padding strip
                sdl.gl_quad(n.x, n.content_y, n.content_x - n.x, n.content_h)
                -- Right padding strip
                sdl.gl_quad(n.content_x + n.content_w, n.content_y, (n.x + n.w) - (n.content_x + n.content_w), n.content_h)
            end

            -- Outer bound wireframe
            C.glColor4f(r, g, b, 0.45f)
            sdl.gl_line_rect(n.x + 0.5f, n.y + 0.5f, n.w - 1.0f, n.h - 1.0f)

            -- Content box wireframe (dashed effect: just dimmer)
            if app.debug_mode >= 2 and (n.content_x ~= n.x or n.content_y ~= n.y or n.content_w ~= n.w or n.content_h ~= n.h) then
                C.glColor4f(r, g, b, 0.22f)
                sdl.gl_line_rect(n.content_x + 0.5f, n.content_y + 0.5f, n.content_w - 1.0f, n.content_h - 1.0f)
            end

            -- Hit test for hover tooltip
            if mx >= n.x and mx < n.x + n.w and my >= n.y and my < n.y + n.h then
                var area = n.w * n.h
                if area < hover_area then
                    hover_area = area
                    hover_node = i
                end
            end
        end
    end

    -- Pass 2: clip region indicators (red dashed)
    if app.debug_mode >= 2 then
        for i = 0, [node_count - 1] do
            var n = frame.nodes[i]
            if n.visible then
                var meta = debug_meta_arr[i]
                if meta.has_clip then
                    C.glColor4f(1.0f, 0.25f, 0.15f, 0.55f)
                    C.glLineWidth(2.0f)
                    sdl.gl_line_rect(n.clip_x0 + 0.5f, n.clip_y0 + 0.5f,
                        n.clip_x1 - n.clip_x0 - 1.0f, n.clip_y1 - n.clip_y0 - 1.0f)
                    C.glLineWidth(1.0f)
                end
            end
        end
    end

    -- Pass 3: highlight hovered node
    if hover_node >= 0 then
        var n = frame.nodes[hover_node]
        C.glColor4f(1.0f, 1.0f, 1.0f, 0.15f)
        sdl.gl_quad(n.x, n.y, n.w, n.h)
        C.glColor4f(1.0f, 1.0f, 1.0f, 0.8f)
        C.glLineWidth(2.0f)
        sdl.gl_line_rect(n.x + 0.5f, n.y + 0.5f, n.w - 1.0f, n.h - 1.0f)
        C.glLineWidth(1.0f)
    end

    -- Pass 4: mode >= 3 — draw node index labels at top-left of each node
    if app.debug_mode >= 3 then
        for i = 0, [node_count - 1] do
            var n = frame.nodes[i]
            if n.visible and n.w >= 16 and n.h >= 10 then
                -- Small index badge
                var label: int8[8]
                C.snprintf(&label[0], 8, "%d", i)

                var meta = debug_meta_arr[i]
                var hue = C.fmodf([float](meta.depth) * 137.5f, 360.0f)
                var r: float, g: float, b: float
                hsl_to_rgb(hue, 0.75f, 0.55f, &r, &g, &b)
                if meta.has_scroll then r = 0.2f; g = 0.85f; b = 0.95f
                elseif meta.has_clip then r = 0.95f; g = 0.6f; b = 0.2f
                elseif meta.has_float then r = 0.9f; g = 0.3f; b = 0.9f
                end

                -- Badge background
                var tw: float = 7.0f * C.strlen(&label[0]) + 8.0f
                C.glColor4f(0.0f, 0.0f, 0.0f, 0.72f)
                sdl.gl_quad(n.x, n.y, tw, 14.0f)
                -- Badge outline
                C.glColor4f(r, g, b, 0.6f)
                sdl.gl_line_rect(n.x + 0.5f, n.y + 0.5f, tw - 1.0f, 13.0f)

                -- Render label text via TextCmd
                var cmd: compile.TextCmd
                C.memset(&cmd, 0, [terralib.sizeof(compile.TextCmd)])
                cmd.x = n.x + 3.0f
                cmd.y = n.y + 1.0f
                cmd.w = tw - 6.0f
                cmd.h = 12.0f
                cmd.text = &label[0]
                cmd.font_size = 10.0f
                cmd.color = compile.Color { r, g, b, 1.0f }
                cmd.wrap = [compile.TEXT_WRAP_NONE]
                cmd.align = [compile.TEXT_ALIGN_LEFT]
                sdl.draw_text(session, cmd)
            end
        end
    end

    -- Pass 5: tooltip for hovered node (mode >= 1)
    if hover_node >= 0 then
        var n = frame.nodes[hover_node]
        var meta = debug_meta_arr[hover_node]

        -- Build tooltip lines
        var buf: int8[1024]
        var pos = 0
        pos = pos + C.snprintf(&buf[pos], 1024 - pos, "node %d  %s\n", hover_node, meta.label)
        pos = pos + C.snprintf(&buf[pos], 1024 - pos, "axis: %s\n",
            terralib.select(meta.axis == 0, "Row", "Column"))
        pos = pos + C.snprintf(&buf[pos], 1024 - pos, "pos: (%.0f, %.0f)  size: %.0f x %.0f\n",
            n.x, n.y, n.w, n.h)
        pos = pos + C.snprintf(&buf[pos], 1024 - pos, "content: (%.0f, %.0f)  %.0f x %.0f\n",
            n.content_x, n.content_y, n.content_w, n.content_h)
        if meta.has_clip then
            pos = pos + C.snprintf(&buf[pos], 1024 - pos, "clip: (%.0f, %.0f) -> (%.0f, %.0f)\n",
                n.clip_x0, n.clip_y0, n.clip_x1, n.clip_y1)
        end
        if meta.has_scroll then
            pos = pos + C.snprintf(&buf[pos], 1024 - pos, "scroll: (%.1f, %.1f)  need: %s%s\n",
                n.scroll_x, n.scroll_y,
                terralib.select(n.scroll_need_x, "x", ""),
                terralib.select(n.scroll_need_y, "y", ""))
            pos = pos + C.snprintf(&buf[pos], 1024 - pos, "extent: %.0f x %.0f\n",
                n.content_extent_w, n.content_extent_h)
        end
        if meta.has_text then
            pos = pos + C.snprintf(&buf[pos], 1024 - pos, "text node")
        end
        if meta.has_float then
            pos = pos + C.snprintf(&buf[pos], 1024 - pos, "float")
        end

        -- Count lines and estimate width from the longest line so the
        -- inspector tooltip is compact but never vertically cramped.
        var lines = 1
        var cur_chars = 0
        var max_chars = 0
        for k = 0, pos - 1 do
            if buf[k] == ("\n")[0] then
                if cur_chars > max_chars then max_chars = cur_chars end
                cur_chars = 0
                lines = lines + 1
            else
                cur_chars = cur_chars + 1
            end
        end
        if cur_chars > max_chars then max_chars = cur_chars end
        if pos > 0 and buf[pos - 1] == ("\n")[0] then lines = lines - 1 end

        var pad_x: float = 12.0f
        var pad_y: float = 12.0f
        var font_size: float = 12.0f
        var line_h: float = 18.0f
        var est_char_w: float = 7.6f
        var tw = [float](max_chars) * est_char_w + pad_x * 2.0f
        if tw < 260.0f then tw = 260.0f end
        if tw > 420.0f then tw = 420.0f end
        var th: float = [float](lines) * line_h + pad_y * 2.0f + 4.0f

        -- Position tooltip near mouse, keep on screen with a small margin.
        var tx = mx + 18.0f
        var ty = my + 18.0f
        if tx + tw > frame.viewport_w - 8.0f then tx = mx - tw - 10.0f end
        if ty + th > frame.viewport_h - 8.0f then ty = my - th - 10.0f end
        if tx < 8.0f then tx = 8.0f end
        if ty < 8.0f then ty = 8.0f end

        -- Background
        C.glColor4f(0.06f, 0.07f, 0.09f, 0.94f)
        sdl.gl_quad(tx, ty, tw, th)
        -- Border
        C.glColor4f(0.5f, 0.6f, 0.7f, 0.7f)
        sdl.gl_line_rect(tx + 0.5f, ty + 0.5f, tw - 1.0f, th - 1.0f)

        -- Render tooltip text line by line
        var line_start = 0
        var line_idx = 0
        for k = 0, pos do
            if k == pos or buf[k] == ("\n")[0] then
                if k > line_start then
                    var saved = buf[k]
                    buf[k] = 0
                    var cmd: compile.TextCmd
                    C.memset(&cmd, 0, [terralib.sizeof(compile.TextCmd)])
                    cmd.x = tx + pad_x
                    cmd.y = ty + pad_y + 1.0f + [float](line_idx) * line_h
                    cmd.w = tw - pad_x * 2.0f
                    cmd.h = line_h
                    cmd.text = &buf[line_start]
                    cmd.font_size = font_size
                    cmd.wrap = [compile.TEXT_WRAP_NONE]
                    cmd.align = [compile.TEXT_ALIGN_LEFT]
                    if line_idx == 0 then
                        cmd.color = compile.Color { 1.0f, 1.0f, 1.0f, 1.0f }
                    else
                        cmd.color = compile.Color { 0.75f, 0.80f, 0.88f, 1.0f }
                    end
                    sdl.draw_text(session, cmd)
                    buf[k] = saved
                end
                line_start = k + 1
                line_idx = line_idx + 1
            end
        end
    end

    -- Mode indicator in top-right corner
    var mode_labels: rawstring[4]
    mode_labels[0] = ""
    mode_labels[1] = "DEBUG: bounds"
    mode_labels[2] = "DEBUG: bounds + padding"
    mode_labels[3] = "DEBUG: full"
    if app.debug_mode > 0 then
        var lbl = mode_labels[app.debug_mode]
        var lw: float = 8.0f * C.strlen(lbl) + 16.0f
        var lx = frame.viewport_w - lw - 10.0f
        var ly: float = 10.0f
        C.glColor4f(0.05f, 0.06f, 0.08f, 0.90f)
        sdl.gl_quad(lx, ly, lw, 24.0f)
        C.glColor4f(0.4f, 0.8f, 1.0f, 0.7f)
        sdl.gl_line_rect(lx + 0.5f, ly + 0.5f, lw - 1.0f, 23.0f)
        var cmd: compile.TextCmd
        C.memset(&cmd, 0, [terralib.sizeof(compile.TextCmd)])
        cmd.x = lx + 8.0f
        cmd.y = ly + 5.0f
        cmd.w = lw - 16.0f
        cmd.h = 14.0f
        cmd.text = lbl
        cmd.font_size = 12.0f
        cmd.color = compile.Color { 0.4f, 0.85f, 1.0f, 1.0f }
        cmd.wrap = [compile.TEXT_WRAP_NONE]
        cmd.align = [compile.TEXT_ALIGN_LEFT]
        sdl.draw_text(session, cmd)
    end
end

---------------------------------------------------------------------------

terra maybe_handle_action(app: &DemoApp, frame: &Frame)
    if frame.action_name == nil then return end

    if C.strcmp(frame.action_name, "tool:inspect") == 0 then
        apply_tool_profile(app, "Inspect")
        app.status_primary = "Inspect tool armed"
        set_events(app,
            "Event: bound tree and kernel nodes are under inspection",
            "Event: overlay remains passthrough while hit-testing preview content",
            "Event: inspector chart tracks live runtime coverage")
    elseif C.strcmp(frame.action_name, "tool:paint") == 0 then
        apply_tool_profile(app, "Paint")
        app.status_primary = "Paint tool armed"
        set_events(app,
            "Event: brush aperture synced with preview overlay",
            "Event: fill meters now emphasize coverage over bake latency",
            "Event: cached text keeps tool switching responsive")
    elseif C.strcmp(frame.action_name, "tool:lighting") == 0 then
        apply_tool_profile(app, "Lighting")
        app.status_primary = "Lighting tool armed"
        set_events(app,
            "Event: tonal diagnostics enabled for the active preview",
            "Event: waveform panel now tracks exposure-style motion",
            "Event: inspector palette pivots toward the active accent")
    elseif C.strcmp(frame.action_name, "tool:export") == 0 then
        apply_tool_profile(app, "Export")
        app.status_primary = "Export requested"
        set_events(app,
            "Event: artifact package staged from compiled UI state",
            "Event: renderer details frozen for a reproducible snapshot",
            "Event: memoized compile artifact remains hot for the next run")
    elseif C.strcmp(frame.action_name, "asset:terrain") == 0 then
        app.status_primary = "Selection changed"
        apply_asset_profile(app, "Terrain")
        set_events(app,
            "Event: terrain tile set promoted to the preview target",
            "Event: guide grid tuned for contour-centric composition",
            "Event: inspector metadata refreshed from the terrain profile")
    elseif C.strcmp(frame.action_name, "asset:water") == 0 then
        app.status_primary = "Selection changed"
        apply_asset_profile(app, "Water")
        set_events(app,
            "Event: water simulation promoted to the preview target",
            "Event: overlay hints adjusted for ripple-safe framing",
            "Event: chart cadence updated to fluid-layer diagnostics")
    elseif C.strcmp(frame.action_name, "asset:roads") == 0 then
        app.status_primary = "Selection changed"
        apply_asset_profile(app, "Roads")
        set_events(app,
            "Event: road network promoted to the preview target",
            "Event: grid overlay aligned with lane stitching and signage",
            "Event: inspector metadata refreshed from the traffic profile")
    elseif C.strcmp(frame.action_name, "asset:blueprint") == 0 then
        app.status_primary = "Selection changed"
        apply_asset_profile(app, "Blueprint")
        set_events(app,
            "Event: blueprint layer promoted to the preview target",
            "Event: export-friendly margins surfaced in the overlay",
            "Event: chart cadence updated to markup-review diagnostics")
    elseif C.strcmp(frame.action_name, "asset:heatmap") == 0 then
        app.status_primary = "Selection changed"
        apply_asset_profile(app, "Heatmap")
        set_events(app,
            "Event: heatmap pass promoted to the preview target",
            "Event: overlay tuned to focal hotspots and confidence zones",
            "Event: inspector metadata refreshed from the analysis profile")
    end

    C.SDL_SetWindowTitle(app.backend.window, app.preview_title)
end

terra update_live_state(app: &DemoApp, frame: &Frame)
    app.tick = app.tick + 1

    var wave = [float](app.tick % 64)
    app.progress_a = 110 + (wave * 1.4f)
    app.progress_b = 72 + ([float]((app.tick * 3) % 92) * 1.2f)

    if frame.cursor_name ~= nil then
        app.footer_text = "Cursor: pointer over interactive control"
    elseif frame.hit.hot >= 0 then
        app.footer_text = "Cursor: hovering layout node"
    else
        app.footer_text = "Cursor idle"
    end

    if frame.action_name ~= nil then
        app.footer_text = "Action emitted from compiled kernel"
    end

    if C.strcmp(app.selected_asset, "Terrain") == 0 then
        app.progress_a = 150 + wave * 0.8f
        app.progress_b = 92 + [float]((app.tick * 5) % 60)
    elseif C.strcmp(app.selected_asset, "Water") == 0 then
        app.progress_a = 118 + [float]((app.tick * 3) % 80)
        app.progress_b = 142 + [float]((app.tick * 2) % 50)
    elseif C.strcmp(app.selected_asset, "Roads") == 0 then
        app.progress_a = 176 + [float]((app.tick * 2) % 30)
        app.progress_b = 84 + [float]((app.tick * 4) % 76)
    elseif C.strcmp(app.selected_asset, "Blueprint") == 0 then
        app.progress_a = 96 + [float]((app.tick * 2) % 66)
        app.progress_b = 132 + [float]((app.tick * 3) % 48)
    else
        app.progress_a = 142 + [float]((app.tick * 6) % 70)
        app.progress_b = 70 + [float]((app.tick * 5) % 88)
    end

    if C.strcmp(app.selected_tool, "Paint") == 0 then
        app.progress_a = app.progress_a + 14.0f
    elseif C.strcmp(app.selected_tool, "Lighting") == 0 then
        app.progress_b = app.progress_b + 10.0f
    elseif C.strcmp(app.selected_tool, "Export") == 0 then
        app.progress_a = 208.0f - [float]((app.tick * 3) % 44)
        app.progress_b = 168.0f + [float]((app.tick * 2) % 34)
    end
end

terra main(argc: int, argv: &rawstring)
    var max_frames: int = -1
    var hidden = false
    var debug_scroll = false
    var debug_geom = false
    if argc > 1 and C.strcmp(argv[1], "hidden") ~= 0 and C.strcmp(argv[1], "debug-scroll") ~= 0 and C.strcmp(argv[1], "debug-geom") ~= 0 then
        max_frames = C.atoi(argv[1])
    end
    for i = 1, argc - 1 do
        if C.strcmp(argv[i], "hidden") == 0 then
            hidden = true
        elseif C.strcmp(argv[i], "debug-scroll") == 0 then
            debug_scroll = true
        elseif C.strcmp(argv[i], "debug-geom") == 0 then
            debug_geom = true
        end
    end

    var app: DemoApp
    C.memset(&app, 0, [terralib.sizeof(DemoApp)])

    if debug_scroll then
        var f = C.fopen([debug_scroll_log_path], "w")
        if f ~= nil then
            C.fprintf(f, "[scroll-debug] enabled\n")
            C.fflush(f)
            C.fclose(f)
        end
    end
    if debug_geom then
        var f = C.fopen([debug_geom_log_path], "w")
        if f ~= nil then
            C.fprintf(f, "[geom-debug] enabled\n")
            C.fflush(f)
            C.fclose(f)
        end
    end

    var rc = app_init(&app, hidden)
    if rc ~= 0 then return rc end
    init_debug_meta()

    var frame: Frame
    [init_q](&frame)

    var quit = false
    var frames = 0
    while not quit and (max_frames < 0 or frames < max_frames) do
        pump_input(&app, &frame, &quit)
        var had_wheel = frame.input.wheel_dx ~= 0.0f or frame.input.wheel_dy ~= 0.0f
        if debug_scroll and had_wheel then
            debug_scroll_input(&frame)
            debug_scroll_state(&frame, "before run")
        end
        sync_params(&frame, &app)
        if debug_scroll and had_wheel then
            [layout_q](&frame)
            [hit_test_q](&frame)
            debug_scroll_state(&frame, "after pre-layout+hit")
            [input_q](&frame)
            debug_scroll_state(&frame, "after input")
            frame.input.mouse_pressed = false
            frame.input.mouse_released = false
            frame.input.wheel_dx = 0.0f
            frame.input.wheel_dy = 0.0f
            [run_q](&frame)
            debug_scroll_state(&frame, "after run")
        else
            [run_q](&frame)
        end
        maybe_handle_action(&app, &frame)
        update_live_state(&app, &frame)
        sync_params(&frame, &app)
        if (debug_geom or debug_scroll) and frames < 4 then
            debug_geom_state(&frame, "before replay")
        end
        replay(&app.backend, &app, &frame)
        draw_debug_overlay(&app.backend, &app, &frame)
        sdl.swap_window(&app.backend)
        frames = frames + 1
    end

    app_shutdown(&app)
    return 0
end

terralib.saveobj(out_path, "executable", { main = main }, link_flags)
print("built demo:", out_path)
print("font:", font_path)
