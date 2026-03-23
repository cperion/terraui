-- examples/love2d/main.lua
-- TerraUI + Love2D demo
--
-- Same UI as the SDL+OpenGL AOT demo, rendered through Love2D.
--
-- Build:  make love2d-build
-- Run:    make love2d-run
-- Both:   make love2d

local ffi = require("ffi")
local ui = require("demo_ui_ffi")

local frame
local mouse_was_down = false
local tick = 0

---------------------------------------------------------------------------
-- Procedural textures  (matches SDL demo's init_texture_pattern)
---------------------------------------------------------------------------

local textures = {}

local function gen_texture(pattern)
    local sz = 128
    local data = love.image.newImageData(sz, sz)
    for y = 0, sz - 1 do
        for x = 0, sz - 1 do
            local r, g, b = 0, 0, 0
            if pattern == 0 then  -- checker
                local dark = (math.floor(x / 16) + math.floor(y / 16)) % 2 == 0
                if dark then r, g, b = 72, 78, 90 else r, g, b = 160, 168, 182 end
            elseif pattern == 1 then  -- terrain
                r = 60 + math.floor(x * 35 / sz)
                g = 96 + math.floor(y * 90 / sz)
                b = 48 + math.floor((x + y) * 20 / sz)
                if (math.floor(x / 12) + math.floor(y / 10)) % 5 == 0 then
                    r, g, b = 126, 182, 86
                end
            elseif pattern == 2 then  -- water
                r = 34
                g = 84 + math.floor(x * 44 / sz)
                b = 156 + math.floor(y * 68 / sz)
                if math.floor(y / 10) % 3 == 0 then r, g, b = 72, 170, 220 end
            elseif pattern == 3 then  -- roads
                r, g, b = 76, 78, 84
                if x % 24 < 6 or y % 24 < 6 then r, g, b = 120, 124, 132 end
                if x % 32 >= 14 and x % 32 <= 18 then r, g, b = 220, 190, 68 end
            elseif pattern == 4 then  -- blueprint
                r = 24 + math.floor(x * 40 / sz)
                g = 34 + math.floor(y * 24 / sz)
                b = 76 + math.floor(x * 86 / sz)
                if x % 16 == 0 or y % 16 == 0 then r, g, b = 94, 168, 255 end
            else  -- heatmap
                r = math.floor(x * 255 / sz)
                g = math.floor(y * 255 / sz)
                b = 255 - math.floor(x * 255 / sz)
            end
            data:setPixel(x, y, r / 255, g / 255, b / 255, 1)
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

local function init_textures()
    textures.checker   = gen_texture(0)
    textures.terrain   = gen_texture(1)
    textures.water     = gen_texture(2)
    textures.roads     = gen_texture(3)
    textures.blueprint = gen_texture(4)
    textures.heatmap   = gen_texture(5)
end

---------------------------------------------------------------------------
-- Color helpers
---------------------------------------------------------------------------

local accent = { r = 0.42, g = 0.70, b = 0.32, a = 1 }

local function lerp(a, b, t)
    t = math.max(0, math.min(1, t))
    return a + (b - a) * t
end

local function shade(c, k) return { r = c.r * k, g = c.g * k, b = c.b * k, a = c.a } end

local function lerp_color(a, b, t)
    return { r = lerp(a.r, b.r, t), g = lerp(a.g, b.g, t), b = lerp(a.b, b.b, t), a = lerp(a.a, b.a, t) }
end

---------------------------------------------------------------------------
-- Custom command renderers  (match SDL demo's draw_custom)
---------------------------------------------------------------------------

local custom_renderers = {}

function custom_renderers.preview_guides(c)
    local lg = love.graphics
    local pulse = 0.45 + 0.25 * math.sin(tick * 0.09)
    local inner = 18 + 4 * pulse

    -- Safe-area bars
    lg.setColor(0.02, 0.03, 0.04, 0.14)
    lg.rectangle("fill", c.x, c.y, c.w, 16)
    lg.rectangle("fill", c.x, c.y + c.h - 16, c.w, 16)
    lg.rectangle("fill", c.x, c.y, 16, c.h)
    lg.rectangle("fill", c.x + c.w - 16, c.y, 16, c.h)

    -- Grid
    lg.setColor(1, 1, 1, 0.10)
    local step = 32
    for gx = c.x + step, c.x + c.w - 1, step do
        lg.line(gx, c.y, gx, c.y + c.h)
    end
    for gy = c.y + step, c.y + c.h - 1, step do
        lg.line(c.x, gy, c.x + c.w, gy)
    end

    -- Crosshairs
    local ac = lerp_color(accent, { r = 1, g = 1, b = 1, a = 1 }, 0.35)
    lg.setColor(ac.r, ac.g, ac.b, 0.60 + pulse * 0.25)
    lg.line(c.x + c.w * 0.5, c.y, c.x + c.w * 0.5, c.y + c.h)
    lg.line(c.x, c.y + c.h * 0.5, c.x + c.w, c.y + c.h * 0.5)

    -- Focal rectangle
    lg.setColor(accent.r, accent.g, accent.b, 0.35 + pulse * 0.20)
    lg.rectangle("line", c.x + inner, c.y + inner, c.w - inner * 2, c.h - inner * 2)

    -- Tool-specific overlays
    if app.selected_tool == "Paint" then
        lg.setColor(accent.r, accent.g, accent.b, 0.45)
        lg.rectangle("line", c.x + c.w / 2 - 34, c.y + c.h / 2 - 34, 68, 68)
    elseif app.selected_tool == "Lighting" then
        lg.setColor(1, 0.92, 0.54, 0.32)
        lg.line(c.x + 30, c.y + 24, c.x + c.w - 30, c.y + c.h - 24)
        lg.line(c.x + 30, c.y + c.h - 24, c.x + c.w - 30, c.y + 24)
    elseif app.selected_tool == "Export" then
        lg.setColor(0.90, 0.96, 1.0, 0.30)
        lg.rectangle("line", c.x + 10, c.y + 10, c.w - 20, c.h - 20)
    end
end

function custom_renderers.inspector_chart(c)
    local lg = love.graphics
    -- Background
    lg.setColor(0.14, 0.16, 0.20, 1)
    lg.rectangle("fill", c.x, c.y, c.w, c.h)
    lg.setColor(0.22, 0.24, 0.28, 1)
    lg.rectangle("line", c.x, c.y, c.w, c.h)
    -- Bars
    local bars = 12
    local bar_w = (c.w - 26) / bars
    for i = 0, bars - 1 do
        local wave = 0.5 + 0.5 * math.sin((tick + i * 7) * 0.13)
        local h = 16 + wave * (c.h - 30)
        local bx = c.x + 10 + i * bar_w
        local by = c.y + c.h - 8 - h
        local col = lerp_color(shade(accent, 0.65), { r = 0.82, g = 0.88, b = 1.0, a = 1 }, i / bars)
        lg.setColor(col.r, col.g, col.b, 0.96)
        lg.rectangle("fill", bx, by, bar_w - 4, h)
    end
end

function custom_renderers.accent_swatches(c)
    local lg = love.graphics
    local palette = {
        shade(accent, 0.45),
        shade(accent, 0.72),
        accent,
        lerp_color(accent, { r = 1, g = 1, b = 1, a = 1 }, 0.28),
        lerp_color(accent, { r = 1, g = 0.86, b = 0.36, a = 1 }, 0.36),
    }
    local sw = (c.w - 28) / 5
    local y0 = c.y + 8
    local h = c.h - 16
    for i, col in ipairs(palette) do
        local x0 = c.x + 8 + (i - 1) * sw
        lg.setColor(col.r, col.g, col.b, 1)
        lg.rectangle("fill", x0, y0, sw - 4, h)
        lg.setColor(1, 1, 1, 0.18)
        lg.rectangle("line", x0, y0, sw - 4, h)
    end
end

function custom_renderers.timeline_wave(c)
    local lg = love.graphics
    -- Background
    lg.setColor(0.12, 0.14, 0.18, 1)
    lg.rectangle("fill", c.x, c.y, c.w, c.h)
    lg.setColor(0.22, 0.24, 0.28, 1)
    lg.rectangle("line", c.x, c.y, c.w, c.h)
    -- Base bar
    lg.setColor(accent.r, accent.g, accent.b, 0.35)
    lg.rectangle("fill", c.x + 12, c.y + c.h - 22, c.w - 24, 6)
    -- Wave
    lg.setLineWidth(2)
    lg.setColor(accent.r, accent.g, accent.b, 0.95)
    local pts = {}
    for i = 0, 48 do
        local t = i / 48
        local phase = tick * 0.07
        local y = c.y + c.h * 0.55 + math.sin(t * 8.5 + phase) * 11 + math.sin(t * 21 + phase * 1.8) * 4.5
        pts[#pts + 1] = c.x + 10 + t * (c.w - 20)
        pts[#pts + 1] = y
    end
    if #pts >= 4 then lg.line(pts) end
    lg.setLineWidth(1)
end

---------------------------------------------------------------------------
-- App state  (mirrors SDL demo)
---------------------------------------------------------------------------

app = {
    selected_tool    = "Inspect",
    selected_asset   = "Terrain",
    status_primary   = "Ready",
    status_secondary = "Static-tree kernel online",
    hint_text        = "Preview overlay: safe area + focal guides",
    preview_image    = "terrain",
    preview_title    = "Terrain composite",
    detail_a         = "Asset type: Tile set",
    detail_b         = "Build channel: Preview",
    footer_text      = "Cursor idle",
    progress_a       = 140,
    progress_b       = 96,
    mode_summary     = "Inspect mode: hover authored nodes and inspect kernel output",
    mode_line_1      = "• highlight bounds and clipping regions",
    mode_line_2      = "• surface command order from merged streams",
    mode_line_3      = "• keep pointer capture transparent over overlays",
    asset_meta_1     = "Resolution: 2048 × 2048",
    asset_meta_2     = "Channels: albedo, height, roughness",
    asset_meta_3     = "Last bake: 00:01.4 ago",
    event_1          = "Event: compiled kernel reused from memoized artifact",
    event_2          = "Event: preview overlay attached through floating target",
    event_3          = "Event: text now cached into reusable GL textures",
}

local tool_profiles = {
    Inspect  = { sec = "Reviewing bounds, clips, and layout metadata",
                 sum = "Inspect mode: hover authored nodes and inspect kernel output",
                 l1 = "• highlight bounds and clipping regions",
                 l2 = "• surface command order from merged streams",
                 l3 = "• keep pointer capture transparent over overlays" },
    Paint    = { sec = "Brush preview locked to current selection",
                 sum = "Paint mode: stamp and adjust accent-weighted coverage",
                 l1 = "• use overlay reticle as brush aperture",
                 l2 = "• animate fill progress against the preview target",
                 l3 = "• verify clipped content and hit routing while painting" },
    Lighting = { sec = "Evaluating highlights, fog, and exposure",
                 sum = "Lighting mode: compare tonal balance and spatial emphasis",
                 l1 = "• inspect focal center and horizon-safe framing",
                 l2 = "• evaluate guide overlays against emissive regions",
                 l3 = "• monitor chart response while exposure changes" },
    Export   = { sec = "Preparing artifact bundle from compiled UI state",
                 sum = "Export mode: validate packaging, replay order, and status reporting",
                 l1 = "• keep diagnostics stable under repeated replay",
                 l2 = "• verify text cache reuse before snapshotting",
                 l3 = "• surface final preview metadata in the inspector" },
}

local asset_profiles = {
    Terrain   = { image = "terrain",   title = "Terrain composite",    a = "Asset type: tile set",      b = "Build channel: sculpt preview",
                  hint = "Terrain preview: contour guides + focal center",    ac = { r = 0.42, g = 0.70, b = 0.32, a = 1 },
                  m1 = "Resolution: 2048 × 2048", m2 = "Channels: albedo, height, roughness", m3 = "Last bake: 00:01.4 ago" },
    Water     = { image = "water",     title = "Water simulation",     a = "Asset type: fluid layer",   b = "Build channel: ripple solve",
                  hint = "Water preview: horizon-safe crop and wave field",   ac = { r = 0.26, g = 0.64, b = 0.92, a = 1 },
                  m1 = "Resolution: 1536 × 1536", m2 = "Channels: flow, foam, depth",          m3 = "Last bake: 00:00.9 ago" },
    Roads     = { image = "roads",     title = "Road network",         a = "Asset type: lane graph",    b = "Build channel: signage bake",
                  hint = "Road preview: guide grid aligned to lane stitching",ac = { r = 0.90, g = 0.74, b = 0.22, a = 1 },
                  m1 = "Resolution: 1024 × 2048", m2 = "Channels: asphalt, decals, traffic",   m3 = "Last bake: 00:02.1 ago" },
    Blueprint = { image = "blueprint", title = "Blueprint overlay",    a = "Asset type: design layer",  b = "Build channel: markup review",
                  hint = "Blueprint preview: read margins, overlays, and label fit", ac = { r = 0.36, g = 0.62, b = 1.0, a = 1 },
                  m1 = "Resolution: 4096 × 2160", m2 = "Channels: notes, zones, anchors",      m3 = "Last bake: 00:00.6 ago" },
    Heatmap   = { image = "heatmap",   title = "Heatmap diagnostics",  a = "Asset type: analysis pass", b = "Build channel: hotspot review",
                  hint = "Heatmap preview: compare hot zones against focal frame", ac = { r = 0.98, g = 0.42, b = 0.28, a = 1 },
                  m1 = "Resolution: 1920 × 1080", m2 = "Channels: occupancy, intensity, confidence", m3 = "Last bake: 00:01.1 ago" },
}

local function apply_tool(name)
    local p = tool_profiles[name]; if not p then return end
    app.selected_tool    = name
    app.status_secondary = p.sec
    app.mode_summary     = p.sum
    app.mode_line_1      = p.l1
    app.mode_line_2      = p.l2
    app.mode_line_3      = p.l3
end

local function apply_asset(name)
    local p = asset_profiles[name]; if not p then return end
    app.selected_asset = name
    app.preview_image  = p.image
    app.preview_title  = p.title
    app.detail_a       = p.a
    app.detail_b       = p.b
    app.hint_text      = p.hint
    app.asset_meta_1   = p.m1
    app.asset_meta_2   = p.m2
    app.asset_meta_3   = p.m3
    accent = p.ac
end

local function sync_params()
    for k, v in pairs(app) do
        if ui.params[k] then ui.set_param(frame, k, v) end
    end
    -- accent is a color param — set fields directly
    frame.params.p12 = ffi.new("TerraUI_Color", accent.r, accent.g, accent.b, accent.a)
end

local function handle_action(action)
    if not action then return end
    local tool = action:match("^tool:(.+)$")
    if tool then
        local name = tool:sub(1, 1):upper() .. tool:sub(2)
        apply_tool(name)
        app.status_primary = name .. " tool armed"
        return
    end
    local asset = action:match("^asset:(.+)$")
    if asset then
        local name = asset:sub(1, 1):upper() .. asset:sub(2)
        apply_asset(name)
        app.status_primary = "Selection changed"
        return
    end
end

---------------------------------------------------------------------------
-- Love2D callbacks
---------------------------------------------------------------------------

function love.load()
    love.window.setTitle("TerraUI + Love2D")
    love.graphics.setBackgroundColor(0.07, 0.08, 0.10)
    init_textures()
    frame = ui.new_frame()
    ui.init(frame)
end

function love.update(dt)
    local w, h = love.graphics.getDimensions()
    frame.viewport_w = w
    frame.viewport_h = h

    local mx, my = love.mouse.getPosition()
    local down = love.mouse.isDown(1)
    frame.input.mouse_x = mx
    frame.input.mouse_y = my
    frame.input.mouse_pressed  = down and not mouse_was_down
    frame.input.mouse_released = not down and mouse_was_down
    frame.input.mouse_down     = down
    mouse_was_down = down

    tick = tick + 1
    local wave = tick % 64
    app.progress_a = 110 + wave * 1.4
    app.progress_b = 72 + ((tick * 3) % 92) * 1.2
    app.footer_text = frame.cursor_name ~= nil and "Cursor: pointer over interactive control"
                   or (frame.hit.hot >= 0 and "Cursor: hovering layout node" or "Cursor idle")

    sync_params()
    ui.run(frame)

    if frame.action_name ~= nil then
        handle_action(ffi.string(frame.action_name))
    end

    love.mouse.setCursor(frame.cursor_name ~= nil
        and love.mouse.getSystemCursor("hand") or nil)

    frame.input.wheel_dx = 0
    frame.input.wheel_dy = 0
end

function love.wheelmoved(x, y)
    frame.input.wheel_dx = frame.input.wheel_dx + x
    frame.input.wheel_dy = frame.input.wheel_dy + y
end

---------------------------------------------------------------------------
-- Renderer
---------------------------------------------------------------------------

local font_cache = {}
local function get_font(size)
    local s = math.max(6, math.floor(size + 0.5))
    if not font_cache[s] then font_cache[s] = love.graphics.newFont(s) end
    return font_cache[s]
end

local function build_draw_list()
    local cmds = {}
    local n = 0
    for i = 0, frame.rect_count - 1 do
        local r = frame.rects[i]
        n = n + 1; cmds[n] = { t = 1, z = r.z, seq = r.seq,
            x = r.x, y = r.y, w = r.w, h = r.h,
            cr = r.color.r, cg = r.color.g, cb = r.color.b, ca = r.color.a * r.opacity }
    end
    for i = 0, frame.border_count - 1 do
        local b = frame.borders[i]
        n = n + 1; cmds[n] = { t = 2, z = b.z, seq = b.seq,
            x = b.x, y = b.y, w = b.w, h = b.h,
            bl = b.left, bt = b.top, br = b.right, bb = b.bottom,
            cr = b.color.r, cg = b.color.g, cb = b.color.b, ca = b.color.a * b.opacity }
    end
    for i = 0, frame.text_count - 1 do
        local t = frame.texts[i]
        n = n + 1; cmds[n] = { t = 3, z = t.z, seq = t.seq,
            x = t.x, y = t.y, w = t.w, h = t.h,
            str = ffi.string(t.text), fs = t.font_size,
            cr = t.color.r, cg = t.color.g, cb = t.color.b, ca = t.color.a }
    end
    for i = 0, frame.image_count - 1 do
        local im = frame.images[i]
        n = n + 1; cmds[n] = { t = 6, z = im.z, seq = im.seq,
            x = im.x, y = im.y, w = im.w, h = im.h,
            cr = im.tint.r, cg = im.tint.g, cb = im.tint.b, ca = im.tint.a,
            image_id = im.image_id ~= nil and ffi.string(im.image_id) or nil }
    end
    for i = 0, frame.custom_count - 1 do
        local cu = frame.customs[i]
        n = n + 1; cmds[n] = { t = 7, z = cu.z, seq = cu.seq,
            x = cu.x, y = cu.y, w = cu.w, h = cu.h,
            kind = cu.kind ~= nil and ffi.string(cu.kind) or nil }
    end
    for i = 0, frame.scissor_count - 1 do
        local s = frame.scissors[i]
        n = n + 1; cmds[n] = { t = s.is_begin and 4 or 5, z = s.z, seq = s.seq,
            x0 = s.x0, y0 = s.y0, x1 = s.x1, y1 = s.y1 }
    end
    table.sort(cmds, function(a, b)
        if a.z ~= b.z then return a.z < b.z end
        return a.seq < b.seq
    end)
    return cmds
end

function love.draw()
    local cmds = build_draw_list()
    local lg = love.graphics

    for i = 1, #cmds do
        local c = cmds[i]
        if c.t == 1 then
            lg.setColor(c.cr, c.cg, c.cb, c.ca)
            lg.rectangle("fill", c.x, c.y, c.w, c.h)
        elseif c.t == 2 then
            lg.setColor(c.cr, c.cg, c.cb, c.ca)
            if c.bt > 0 then lg.rectangle("fill", c.x, c.y, c.w, c.bt) end
            if c.bb > 0 then lg.rectangle("fill", c.x, c.y + c.h - c.bb, c.w, c.bb) end
            if c.bl > 0 then lg.rectangle("fill", c.x, c.y, c.bl, c.h) end
            if c.br > 0 then lg.rectangle("fill", c.x + c.w - c.br, c.y, c.br, c.h) end
        elseif c.t == 3 then
            lg.setColor(c.cr, c.cg, c.cb, c.ca)
            lg.setFont(get_font(c.fs))
            lg.setScissor(c.x, c.y, c.w, c.h)
            lg.printf(c.str, c.x, c.y, c.w, "left")
            lg.setScissor()
        elseif c.t == 4 then
            local sw, sh = c.x1 - c.x0, c.y1 - c.y0
            if sw > 0 and sh > 0 then lg.setScissor(c.x0, c.y0, sw, sh) end
        elseif c.t == 5 then
            lg.setScissor()
        elseif c.t == 6 then
            -- Image: draw the procedural texture stretched to fit
            local tex = textures[c.image_id] or textures.checker
            lg.setColor(c.cr, c.cg, c.cb, c.ca)
            lg.draw(tex, c.x, c.y, 0, c.w / tex:getWidth(), c.h / tex:getHeight())
        elseif c.t == 7 then
            -- Custom: dispatch to registered renderer
            local renderer = custom_renderers[c.kind]
            if renderer then
                renderer(c)
            else
                lg.setColor(1, 0.4, 0.1, 1)
                lg.rectangle("line", c.x, c.y, c.w, c.h)
            end
        end
    end

    lg.setColor(1, 1, 1, 1)
    lg.setScissor()

    -- Debug overlay
    lg.setFont(get_font(11))
    lg.setColor(0.4, 0.4, 0.4, 0.6)
    lg.print(string.format(
        "%d rects  %d borders  %d texts  %d images  %d customs  %d scissors   hot:%d   %.0f fps",
        frame.rect_count, frame.border_count, frame.text_count,
        frame.image_count, frame.custom_count, frame.scissor_count,
        frame.hit.hot, love.timer.getFPS()
    ), 4, frame.viewport_h - 16)
end
