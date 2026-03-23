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

local function button(text, action, props)
    props = props or {}
    props.text = text
    props.action = action
    props.padding = props.padding or { left = 12, top = 8, right = 12, bottom = 8 }
    props.background = props.background or rgba(0.22, 0.37, 0.66, 1)
    props.border = props.border or ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.42, 0.58, 0.86, 1) }
    props.radius = props.radius or ui.radius(5)
    props.text_color = props.text_color or rgba(1, 1, 1, 1)
    props.font_size = props.font_size or 15
    return ui.button(props)
end

local function label(text, props)
    props = props or {}
    props.text = text
    props.text_color = props.text_color or rgba(0.92, 0.93, 0.95, 1)
    props.font_size = props.font_size or 15
    if props.wrap ~= nil and props.width == nil then
        props.width = ui.grow()
    end
    return ui.label(props)
end

local function info_row(lhs, rhs)
    return ui.row {
        width = ui.grow(),
        height = ui.fit(),
        gap = 8,
    } {
        label(lhs, { font_size = 14, text_color = rgba(0.70, 0.74, 0.80, 1) }),
        ui.spacer { width = ui.grow(), height = ui.fixed(0) },
        label(rhs, { font_size = 14, text_color = rgba(0.94, 0.95, 0.97, 1) }),
    }
end

local function progress_meter(title, width_param)
    return ui.column {
        width = ui.fit(),
        height = ui.fit(),
        gap = 4,
    } {
        label(title, { font_size = 13, text_color = rgba(0.70, 0.74, 0.80, 1) }),
        ui.column {
            width = ui.fixed(220),
            height = ui.fixed(14),
            background = rgba(0.14, 0.16, 0.20, 1),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.26, 0.28, 0.33, 1) },
        } {
            ui.spacer {
                width = ui.fixed(ui.param_ref(width_param)),
                height = ui.fixed(14),
                background = ui.param_ref("accent"),
            },
        },
    }
end

local params = {
    ui.param("selected_tool")    { type = ui.types.string, default = "Inspect" },
    ui.param("selected_asset")   { type = ui.types.string, default = "Terrain" },
    ui.param("status_primary")   { type = ui.types.string, default = "Ready" },
    ui.param("status_secondary") { type = ui.types.string, default = "Static-tree kernel online" },
    ui.param("hint_text")        { type = ui.types.string, default = "Preview overlay: safe area + focal guides" },
    ui.param("preview_image")    { type = ui.types.image,  default = "terrain" },
    ui.param("preview_title")    { type = ui.types.string, default = "Terrain composite" },
    ui.param("detail_a")         { type = ui.types.string, default = "Asset type: Tile set" },
    ui.param("detail_b")         { type = ui.types.string, default = "Build channel: Preview" },
    ui.param("footer_text")      { type = ui.types.string, default = "Cursor idle" },
    ui.param("progress_a")       { type = ui.types.number, default = 140 },
    ui.param("progress_b")       { type = ui.types.number, default = 96 },
    ui.param("accent")           { type = ui.types.color,  default = rgba(0.42, 0.70, 0.32, 1) },
    ui.param("mode_summary")     { type = ui.types.string, default = "Inspect mode: hover authored nodes and inspect kernel output" },
    ui.param("mode_line_1")      { type = ui.types.string, default = "• highlight bounds and clipping regions" },
    ui.param("mode_line_2")      { type = ui.types.string, default = "• surface command order from merged streams" },
    ui.param("mode_line_3")      { type = ui.types.string, default = "• keep pointer capture transparent over overlays" },
    ui.param("asset_meta_1")     { type = ui.types.string, default = "Resolution: 2048 x 2048" },
    ui.param("asset_meta_2")     { type = ui.types.string, default = "Channels: albedo, height, roughness" },
    ui.param("asset_meta_3")     { type = ui.types.string, default = "Last bake: 00:01.4 ago" },
    ui.param("event_1")          { type = ui.types.string, default = "Event: compiled kernel reused from memoized artifact" },
    ui.param("event_2")          { type = ui.types.string, default = "Event: preview overlay attached through floating target" },
    ui.param("event_3")          { type = ui.types.string, default = "Event: text now cached into reusable GL textures" },
}

local HeaderBadge = ui.widget("HeaderBadge") {
    props = {
        ui.widget_prop("title") { type = ui.types.string },
        ui.widget_prop("subtitle") { type = ui.types.string },
        ui.widget_prop("accent") { type = ui.types.color },
    },
    root = ui.row {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = 10,
        align_y = ui.align_y.center,
    } {
        ui.column { key = ui.stable("text"), width = ui.grow(), height = ui.fit(), gap = 2 } {
            label(ui.prop_ref("title"), { font_size = 24 }),
            label(ui.prop_ref("subtitle"), { font_size = 14, text_color = ui.prop_ref("accent") }),
        },
        ui.column {
            key = ui.stable("swatch"),
            width = ui.fixed(18),
            height = ui.fixed(18),
            background = ui.prop_ref("accent"),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.95, 0.95, 0.98, 0.35) },
        } {},
    },
}

local InfoRowWidget = ui.widget("InfoRow") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 8 },
    },
    props = {
        ui.widget_prop("lhs") { type = ui.types.string },
        ui.widget_prop("rhs") { type = ui.types.string },
    },
    root = ui.row {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
    } {
        label(ui.prop_ref("lhs"), { font_size = 14, text_color = rgba(0.70, 0.74, 0.80, 1) }),
        ui.spacer { width = ui.grow(), height = ui.fixed(0) },
        label(ui.prop_ref("rhs"), { font_size = 14, text_color = rgba(0.94, 0.95, 0.97, 1) }),
    },
}

local ProgressMeterWidget = ui.widget("ProgressMeter") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 4 },
    },
    props = {
        ui.widget_prop("title") { type = ui.types.string },
        ui.widget_prop("bar_width") { type = ui.types.number },
        ui.widget_prop("fill") { type = ui.types.color },
    },
    root = ui.column {
        key = ui.stable("root"),
        width = ui.fit(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
    } {
        label(ui.prop_ref("title"), { font_size = 13, text_color = rgba(0.70, 0.74, 0.80, 1) }),
        ui.column {
            key = ui.stable("track"),
            width = ui.fixed(220),
            height = ui.fixed(14),
            background = rgba(0.14, 0.16, 0.20, 1),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.26, 0.28, 0.33, 1) },
        } {
            ui.spacer {
                key = ui.stable("fill"),
                width = ui.fixed(ui.prop_ref("bar_width")),
                height = ui.fixed(14),
                background = ui.prop_ref("fill"),
            },
        },
    },
}

local ToolbarBar = ui.widget("ToolbarBar") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 8 },
    },
    slots = {
        ui.widget_slot("primary"),
        ui.widget_slot("trailing"),
    },
    root = ui.row {
        key = ui.stable("root"),
        height = ui.fixed(52),
        padding = { left = 14, top = 8, right = 14, bottom = 8 },
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.center,
        background = rgba(0.10, 0.11, 0.14, 1),
        border = ui.border { bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
    } {
        ui.slot("primary"),
        ui.spacer { width = ui.grow(), height = ui.fixed(0) },
        ui.slot("trailing"),
    },
}

local PreviewCard = ui.widget("PreviewCard") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 10 },
    },
    slots = {
        ui.widget_slot("media"),
        ui.widget_slot("meta"),
        ui.widget_slot("meters"),
    },
    root = ui.column(panel {
        key = ui.stable("root"),
        width = ui.fit(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
    }) {
        ui.slot("media"),
        ui.row { key = ui.stable("bottom"), width = ui.grow(), height = ui.fit(), gap = 16 } {
            ui.column { key = ui.stable("meta_col"), width = ui.fit(), height = ui.fit(), gap = 6 } {
                ui.slot("meta"),
            },
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            ui.column { key = ui.stable("meter_col"), width = ui.fit(), height = ui.fit(), gap = 8 } {
                ui.slot("meters"),
            },
        },
    },
}

local ActivityStrip = ui.widget("ActivityStrip") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 14 },
    },
    slots = {
        ui.widget_slot("log"),
        ui.widget_slot("chart"),
    },
    root = ui.row(panel {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.center,
    }) {
        ui.column { key = ui.stable("log_col"), width = ui.grow(), height = ui.fit(), gap = 4 } {
            ui.slot("log"),
        },
        ui.slot("chart"),
    },
}

local InspectorPanel = ui.widget("InspectorPanel") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 10 },
    },
    slots = {
        ui.widget_slot("summary"),
        ui.widget_slot("context"),
        ui.widget_slot("metadata"),
        ui.widget_slot("renderer"),
        ui.widget_slot("chart"),
    },
    root = ui.column(panel {
        key = ui.stable("root"),
        width = ui.fixed(320),
        height = ui.grow(),
        gap = ui.state_ref("gap"),
    }) {
        ui.slot("summary"),
        ui.slot("context"),
        ui.slot("metadata"),
        ui.slot("renderer"),
        ui.slot("chart"),
    },
}

local FooterBar = ui.widget("FooterBar") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 12 },
    },
    slots = {
        ui.widget_slot("left"),
        ui.widget_slot("right"),
    },
    root = ui.row {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fixed(34),
        padding = { left = 14, top = 8, right = 14, bottom = 8 },
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.center,
        background = rgba(0.09, 0.10, 0.12, 1),
        border = ui.border { top = 1, color = rgba(0.20, 0.22, 0.26, 1) },
    } {
        ui.slot("left"),
        ui.spacer { width = ui.grow(), height = ui.fixed(0) },
        ui.slot("right"),
    },
}

local Shell = ui.widget("Shell") {
    slots = {
        ui.widget_slot("toolbar"),
        ui.widget_slot("assets"),
        ui.widget_slot("center"),
        ui.widget_slot("inspector"),
        ui.widget_slot("footer"),
    },
    root = ui.column {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.grow(),
        background = rgba(0.07, 0.08, 0.10, 1),
    } {
        ui.slot("toolbar"),
        ui.row {
            key = ui.stable("main"),
            width = ui.grow(),
            height = ui.grow(),
            gap = 12,
            padding = 12,
        } {
            ui.slot("assets"),
            ui.slot("center"),
            ui.slot("inspector"),
        },
        ui.slot("footer"),
    },
}

local assets_children = {
    label("Assets", { font_size = 21 }),
    label("Choose a surface to drive the preview + inspector.", { font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    button("Terrain",   "asset:terrain"),
    button("Water",     "asset:water"),
    button("Roads",     "asset:roads"),
    button("Blueprint", "asset:blueprint"),
    button("Heatmap",   "asset:heatmap"),
    ui.spacer { height = ui.fixed(12), width = ui.fixed(0) },
    label("The list is clipped and scroll-offset in the kernel.", { font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Use the center rail and inspector widgets to compare mode-specific metadata.", { font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
}

local app = ui.scope("app")
local preview_card = app:child("preview_card")

local decl = ui.component("sdl_gl_demo") {
    params = params,
    widgets = {
        HeaderBadge,
        InfoRowWidget,
        ProgressMeterWidget,
        ToolbarBar,
        PreviewCard,
        ActivityStrip,
        InspectorPanel,
        FooterBar,
        Shell,
    },
    root = ui.column {
        key = ui.stable("root_mount"),
        width = ui.grow(),
        height = ui.grow(),
    } {
        ui.use(Shell) { key = app } {
        toolbar = {
            ui.use(ToolbarBar) { key = ui.stable("toolbar") } {
                primary = {
                    button("Inspect", "tool:inspect"),
                    button("Paint",   "tool:paint",   { background = rgba(0.54, 0.28, 0.18, 1), border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.78, 0.48, 0.32, 1) } }),
                    button("Lighting", "tool:lighting", { background = rgba(0.35, 0.28, 0.12, 1), border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.68, 0.55, 0.24, 1) } }),
                    button("Export",  "tool:export",  { background = rgba(0.22, 0.44, 0.26, 1), border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.42, 0.70, 0.46, 1) } }),
                },
                trailing = {
                    ui.column { gap = 2, width = ui.fit(), height = ui.fit() } {
                        label("TerraUI SDL + OpenGL demo", { font_size = 18 }),
                        label(ui.param_ref("status_secondary"), { font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), width = ui.fixed(320), wrap = ui.wrap.words }),
                    },
                },
            },
        },
        assets = {
            ui.scroll_region(panel {
                key = ui.stable("assets"),
                width = ui.fixed(250),
                height = ui.grow(),
                vertical = true,
                scroll_y = 20,
            }) (assets_children),
        },
        center = {
            ui.column {
                key = ui.stable("center"),
                width = ui.grow(),
                height = ui.grow(),
                gap = 12,
            } {
                ui.use(HeaderBadge) {
                    key = ui.stable("preview_header"),
                    title = ui.param_ref("preview_title"),
                    subtitle = ui.param_ref("selected_asset"),
                    accent = ui.param_ref("accent"),
                } {},

                ui.use(PreviewCard) { key = preview_card } {
                    media = {
                        ui.image_view {
                            ref = "preview",
                            image = ui.param_ref("preview_image"),
                            width = ui.fixed(520),
                            height = ui.fixed(300),
                            aspect_ratio = 1.73,
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.30, 0.32, 0.38, 1) },
                            tint = rgba(1,1,1,1),
                        },
                        ui.custom {
                            key = ui.stable("preview_overlay"),
                            kind = "preview_guides",
                            target = preview_card:ref("preview"),
                            element_point = ui.attach.left_top,
                            parent_point = ui.attach.left_top,
                            width = ui.fixed(520),
                            height = ui.fixed(300),
                            z_index = 12,
                            pointer_capture = ui.pointer_capture.passthrough,
                        },
                    },
                    meta = {
                        ui.use(InfoRowWidget) { key = ui.stable("tool_row"), lhs = "Tool", rhs = ui.param_ref("selected_tool") } {},
                        ui.use(InfoRowWidget) { key = ui.stable("selection_row"), lhs = "Selection", rhs = ui.param_ref("selected_asset") } {},
                        ui.use(InfoRowWidget) { key = ui.stable("mode_row"), lhs = "Mode", rhs = ui.param_ref("mode_summary") } {},
                        ui.use(InfoRowWidget) { key = ui.stable("state_row"), lhs = "State", rhs = ui.param_ref("detail_b") } {},
                    },
                    meters = {
                        ui.use(ProgressMeterWidget) { key = ui.stable("coverage_meter"), title = "Coverage", bar_width = ui.param_ref("progress_a"), fill = ui.param_ref("accent") } {},
                        ui.use(ProgressMeterWidget) { key = ui.stable("bake_meter"), title = "Bake completion", bar_width = ui.param_ref("progress_b"), fill = ui.param_ref("accent") } {},
                    },
                },

                ui.use(ActivityStrip) { key = ui.stable("activity") } {
                    log = {
                        label(ui.param_ref("status_primary"), { font_size = 16 }),
                        label(ui.param_ref("event_1"), { font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1) }),
                        label(ui.param_ref("event_2"), { font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1) }),
                        label(ui.param_ref("event_3"), { font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1) }),
                    },
                    chart = {
                        ui.custom {
                            key = ui.stable("timeline_wave"),
                            kind = "timeline_wave",
                            width = ui.fixed(240),
                            height = ui.fixed(88),
                        },
                    },
                },

                ui.row(panel {
                    key = ui.stable("status_strip"),
                    width = ui.grow(),
                    height = ui.fit(),
                    gap = 18,
                }) {
                    label("Kernel: compiled layout + hit + emit", { width = ui.grow(), text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
                    label("Backend: SDL_ttf + OpenGL replay with text texture cache", { width = ui.grow(), text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
                    label(ui.param_ref("detail_a"), { width = ui.grow(), text_color = ui.param_ref("accent"), wrap = ui.wrap.words }),
                },

                ui.tooltip {
                    key = ui.stable("tooltip"),
                    target = preview_card:ref("preview"),
                    element_point = ui.attach.left_bottom,
                    parent_point = ui.attach.right_top,
                    offset_x = 12,
                    offset_y = -10,
                    z_index = 20,
                    padding = { left = 12, top = 9, right = 12, bottom = 9 },
                    background = rgba(0.96, 0.84, 0.34, 0.97),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.56, 0.42, 0.10, 1) },
                } {
                    label(ui.param_ref("hint_text"), {
                        width = ui.fixed(260),
                        text_color = rgba(0.18, 0.14, 0.08, 1),
                        font_size = 14,
                        wrap = ui.wrap.words,
                    }),
                },
            },
        },
        inspector = {
            ui.use(InspectorPanel) { key = ui.stable("inspector") } {
                summary = {
                    label("Inspector", { font_size = 21 }),
                    label("Selection", { font_size = 14, text_color = rgba(0.68, 0.72, 0.78, 1) }),
                    ui.use(InfoRowWidget) { key = ui.stable("asset_info"), lhs = "Asset", rhs = ui.param_ref("selected_asset") } {},
                    ui.use(InfoRowWidget) { key = ui.stable("tool_info"), lhs = "Tool", rhs = ui.param_ref("selected_tool") } {},
                    ui.use(InfoRowWidget) { key = ui.stable("target_info"), lhs = "Target", rhs = ui.param_ref("preview_title") } {},
                    ui.custom {
                        key = ui.stable("accent_swatches"),
                        kind = "accent_swatches",
                        width = ui.fixed(280),
                        height = ui.fixed(44),
                    },
                },
                context = {
                    label("Tool context", { font_size = 14, text_color = rgba(0.68, 0.72, 0.78, 1) }),
                    label(ui.param_ref("mode_summary"), { font_size = 14 }),
                    label(ui.param_ref("mode_line_1"), { width = ui.grow(), font_size = 13, text_color = rgba(0.74, 0.78, 0.84, 1), wrap = ui.wrap.words }),
                    label(ui.param_ref("mode_line_2"), { width = ui.grow(), font_size = 13, text_color = rgba(0.74, 0.78, 0.84, 1), wrap = ui.wrap.words }),
                    label(ui.param_ref("mode_line_3"), { width = ui.grow(), font_size = 13, text_color = rgba(0.74, 0.78, 0.84, 1), wrap = ui.wrap.words }),
                },
                metadata = {
                    label("Asset metadata", { font_size = 14, text_color = rgba(0.68, 0.72, 0.78, 1) }),
                    label(ui.param_ref("asset_meta_1"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label(ui.param_ref("asset_meta_2"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label(ui.param_ref("asset_meta_3"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                },
                renderer = {
                    label("Renderer", { font_size = 14, text_color = rgba(0.68, 0.72, 0.78, 1) }),
                    label("• split streams merged by (z, seq)", { font_size = 13 }),
                    label("• CPU-side scissor stack replay", { font_size = 13 }),
                    label("• text measured in kernel, rasterized once per cache key", { font_size = 13 }),
                },
                chart = {
                    ui.custom {
                        key = ui.stable("inspector_chart"),
                        kind = "inspector_chart",
                        width = ui.fixed(280),
                        height = ui.fixed(96),
                    },
                },
            },
        },
        footer = {
            ui.use(FooterBar) { key = ui.stable("footer") } {
                left = {
                    label(ui.param_ref("footer_text"), { font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1) }),
                },
                right = {
                    label("Terra AOT executable", { font_size = 13, text_color = rgba(0.52, 0.56, 0.62, 1) }),
                },
            },
        },
        },
    },
}

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
}

local bound = bind.bind_component(decl, { text_backend = sdl.text_backend })
local planned = plan.plan_component(bound)
local kernel = compile.compile_component(planned, { text_backend = sdl.text_backend })
local Frame = kernel:frame_type()
local init_q = kernel.kernels.init_fn
local run_q = kernel.kernels.run_fn

local max_packets = #planned.paints + #planned.texts + #planned.images + (#planned.clips * 2) + #planned.customs
if max_packets < 1 then max_packets = 1 end
local max_scissors = #planned.clips
if max_scissors < 1 then max_scissors = 1 end

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
    sdl.pump_input(&app.backend, &frame.input, &frame.viewport_w, &frame.viewport_h, quit)
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
    if argc > 1 then
        max_frames = C.atoi(argv[1])
    end
    if argc > 2 and C.strcmp(argv[2], "hidden") == 0 then
        hidden = true
    end

    var app: DemoApp
    C.memset(&app, 0, [terralib.sizeof(DemoApp)])

    var rc = app_init(&app, hidden)
    if rc ~= 0 then return rc end

    var frame: Frame
    [init_q](&frame)

    var quit = false
    var frames = 0
    while not quit and (max_frames < 0 or frames < max_frames) do
        pump_input(&app, &frame, &quit)
        sync_params(&frame, &app)
        [run_q](&frame)
        maybe_handle_action(&app, &frame)
        update_live_state(&app, &frame)
        sync_params(&frame, &app)
        replay(&app.backend, &app, &frame)
        frames = frames + 1
    end

    app_shutdown(&app)
    return 0
end

terralib.saveobj(out_path, "executable", { main = main }, link_flags)
print("built demo:", out_path)
print("font:", font_path)
