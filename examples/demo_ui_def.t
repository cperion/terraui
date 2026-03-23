-- examples/demo_ui_def.t
-- Shared UI definition for the TerraUI demo.
-- Used by both the SDL+OpenGL AOT build and the Love2D FFI build.
--
-- Returns a Decl.Component.

local terraui = require("lib/terraui")
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
        width = ui.fit(),
        height = ui.fit(),
        gap = 10,
        align_y = ui.align_y.center,
    } {
        ui.column { key = ui.stable("text"), width = ui.fit(), height = ui.fit(), gap = 2 } {
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
        align_y = ui.align_y.top,
    } {
        label(ui.prop_ref("lhs"), {
            width = ui.fixed(80),
            font_size = 14,
            text_color = rgba(0.70, 0.74, 0.80, 1),
        }),
        label(ui.prop_ref("rhs"), {
            width = ui.grow(),
            font_size = 14,
            text_color = rgba(0.94, 0.95, 0.97, 1),
            wrap = ui.wrap.words,
        }),
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
        height = ui.fit(),
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
        ui.row { key = ui.stable("bottom"), width = ui.grow(), height = ui.fit(), gap = 16, align_y = ui.align_y.top } {
            ui.column { key = ui.stable("meta_col"), width = ui.grow(), height = ui.fit(), gap = 6 } {
                ui.slot("meta"),
            },
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
    label("Choose a surface to drive the preview + inspector.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    button("Terrain",   "asset:terrain"),
    button("Water",     "asset:water"),
    button("Roads",     "asset:roads"),
    button("Blueprint", "asset:blueprint"),
    button("Heatmap",   "asset:heatmap"),
    ui.spacer { height = ui.fixed(12), width = ui.fixed(0) },
    label("The list is clipped in the kernel and kept inside its panel.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Use the center rail and inspector widgets to compare mode-specific metadata.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Recent notes: terrain bake validated, water foam map re-tuned, road masks queued for export.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Pending review: blueprint anchor cleanup, decal atlas repack, and heatmap confidence normalization.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Render notes: terrain uses triplanar blend masks; roads keep an extra traffic-density channel for debug overlays.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Bake queue: shoreline foam retime, lane stitching guide refresh, export thumbnails pending async packaging.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Inspector hint: select an asset, switch tools, then compare the generated metadata and preview overlays side by side.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
    label("Scroll the panel to inspect the rest of the authored asset summary.", { width = ui.grow(), font_size = 13, text_color = rgba(0.68, 0.72, 0.78, 1), wrap = ui.wrap.words }),
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
            ui.scroll_area(panel {
                key = ui.stable("assets"),
                width = ui.fixed(250),
                height = ui.grow(),
                vertical = true,
                bar_size = 6,
                scrollbar_background = rgba(0.10, 0.11, 0.13, 0.0),
                thumb_background = rgba(0.36, 0.41, 0.49, 1.0),
                thumb_radius = ui.radius(3),
                viewport_gap = 8,
                viewport_padding = { right = 8 },
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
                        label(ui.param_ref("status_primary"), { width = ui.grow(), font_size = 16, wrap = ui.wrap.words }),
                        label(ui.param_ref("event_1"), { width = ui.grow(), font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1), wrap = ui.wrap.words }),
                        label(ui.param_ref("event_2"), { width = ui.grow(), font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1), wrap = ui.wrap.words }),
                        label(ui.param_ref("event_3"), { width = ui.grow(), font_size = 13, text_color = rgba(0.72, 0.76, 0.82, 1), wrap = ui.wrap.words }),
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
                    label(ui.param_ref("mode_summary"), { width = ui.grow(), font_size = 14, wrap = ui.wrap.words }),
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
                    label("• split streams merged by (z, seq)", { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label("• CPU-side scissor stack replay", { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label("• text measured in kernel, rasterized once per cache key", { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
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

return decl
