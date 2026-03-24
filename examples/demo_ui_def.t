-- examples/demo_ui_def.t
-- Shared UI definition for the TerraUI demo.
-- Used by both the SDL+OpenGL AOT build and the Love2D FFI build.
--
-- Returns a Decl.Component.

local terraui = require("lib/terraui")
local ui = terraui.dsl()

local function rgba(r,g,b,a) return ui.rgba(r,g,b,a) end
local function tok(name) return ui.token(name) end
local function tok_color(name) return ui.token.color(name) end
local function tok_number(name) return ui.token.number(name) end

local function inset(x, y)
    y = y or x
    return { left = x, top = y, right = x, bottom = y }
end

local function panel(props)
    props = props or {}
    props.background = props.background or tok_color("color.surface.panel")
    props.border = props.border or ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.border.panel") }
    props.padding = props.padding or inset(tok_number("space.panel.padding_x"), tok_number("space.panel.padding_y"))
    props.gap = props.gap or tok_number("space.panel.gap")
    return props
end

local function button(text, action, props)
    props = props or {}
    props.text = text
    props.action = action
    props.padding = props.padding or { left = 12, top = 8, right = 12, bottom = 8 }
    props.background = props.background or tok_color("color.button.bg")
    props.border = props.border or ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.button.border") }
    props.radius = props.radius or ui.radius(tok_number("radius.button"))
    props.text_color = props.text_color or tok_color("color.button.fg")
    props.font_size = props.font_size or tok_number("font.button.size")
    return ui.button(props)
end

local function label(text, props)
    props = props or {}
    props.text = text
    props.text_color = props.text_color or tok_color("color.text.primary")
    props.font_size = props.font_size or tok_number("font.body.size")
    if props.wrap ~= nil and props.width == nil then
        props.width = ui.grow()
    end
    return ui.label(props)
end

local function themed_button(text, action, overrides)
    return ui.with_theme("demo_dark", overrides or {}) {
        button(text, action)
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

local themes = {
    ui.theme_def("demo_dark") {
        tokens = {
            ui.theme_token("color.app.bg", ui.types.color, rgba(0.07, 0.08, 0.10, 1)),
            ui.theme_token("color.surface.panel", ui.types.color, rgba(0.12, 0.13, 0.15, 1.0)),
            ui.theme_token("color.surface.toolbar", ui.types.color, rgba(0.10, 0.11, 0.14, 1)),
            ui.theme_token("color.surface.footer", ui.types.color, rgba(0.09, 0.10, 0.12, 1)),
            ui.theme_token("color.border.panel", ui.types.color, rgba(0.22, 0.24, 0.28, 1.0)),
            ui.theme_token("color.border.toolbar", ui.types.color, rgba(0.22, 0.24, 0.28, 1.0)),
            ui.theme_token("color.border.footer", ui.types.color, rgba(0.20, 0.22, 0.26, 1.0)),
            ui.theme_token("color.text.primary", ui.types.color, rgba(0.92, 0.93, 0.95, 1)),
            ui.theme_token("color.text.muted", ui.types.color, rgba(0.68, 0.72, 0.78, 1)),
            ui.theme_token("color.text.subtle", ui.types.color, rgba(0.72, 0.76, 0.82, 1)),
            ui.theme_token("color.button.bg", ui.types.color, rgba(0.22, 0.37, 0.66, 1)),
            ui.theme_token("color.button.border", ui.types.color, rgba(0.42, 0.58, 0.86, 1)),
            ui.theme_token("color.button.fg", ui.types.color, rgba(1, 1, 1, 1)),
            ui.theme_token("color.surface.track", ui.types.color, rgba(0.14, 0.16, 0.20, 1)),
            ui.theme_token("color.border.track", ui.types.color, rgba(0.26, 0.28, 0.33, 1)),
            ui.theme_token("color.border.preview", ui.types.color, rgba(0.30, 0.32, 0.38, 1)),
            ui.theme_token("color.surface.badge", ui.types.color, rgba(0.13, 0.14, 0.17, 1.0)),
            ui.theme_token("color.border.badge", ui.types.color, rgba(0.29, 0.31, 0.37, 1)),
            ui.theme_token("color.surface.scrollbar", ui.types.color, rgba(0.10, 0.11, 0.13, 0.0)),
            ui.theme_token("color.scrollbar.thumb", ui.types.color, rgba(0.36, 0.41, 0.49, 1.0)),
            ui.theme_token("color.surface.tooltip", ui.types.color, rgba(0.96, 0.84, 0.34, 0.97)),
            ui.theme_token("color.border.tooltip", ui.types.color, rgba(0.56, 0.42, 0.10, 1)),
            ui.theme_token("color.text.tooltip", ui.types.color, rgba(0.18, 0.14, 0.08, 1)),
            ui.theme_token("color.text.disabled", ui.types.color, rgba(0.52, 0.56, 0.62, 1)),
            ui.theme_token("space.panel.padding_x", ui.types.number, 14),
            ui.theme_token("space.panel.padding_y", ui.types.number, 14),
            ui.theme_token("space.panel.gap", ui.types.number, 10),
            ui.theme_token("space.badge.padding_x", ui.types.number, 16),
            ui.theme_token("space.badge.padding_y", ui.types.number, 13),
            ui.theme_token("space.shell.padding", ui.types.number, 14),
            ui.theme_token("space.shell.gap", ui.types.number, 14),
            ui.theme_token("space.bar.padding_x", ui.types.number, 14),
            ui.theme_token("space.bar.padding_y", ui.types.number, 8),
            ui.theme_token("font.body.size", ui.types.number, 15),
            ui.theme_token("font.button.size", ui.types.number, 15),
            ui.theme_token("radius.button", ui.types.number, 5),
        },
    },
}

local HeaderBadge = ui.widget("HeaderBadge") {
    props = {
        ui.widget_prop("title") { type = ui.types.string },
        ui.widget_prop("subtitle") { type = ui.types.string },
        ui.widget_prop("accent") { type = ui.types.color },
    },
    parts = {
        ui.widget_part("root"),
        ui.widget_part("title"),
        ui.widget_part("subtitle"),
    },
    root = ui.part("root", ui.row {
        key = ui.stable("root"),
        width = ui.fixed(520),
        height = ui.fit(),
        padding = inset(tok_number("space.badge.padding_x"), tok_number("space.badge.padding_y")),
        gap = 10,
        align_y = ui.align_y.center,
    } {
        ui.column { key = ui.stable("text"), width = ui.fit(), height = ui.fit(), gap = 4 } {
            ui.part("title", label(ui.prop_ref("title"), { font_size = 21 })),
            ui.part("subtitle", label(ui.prop_ref("subtitle"), { font_size = 12, text_color = ui.prop_ref("accent") })),
        },
        ui.spacer { key = ui.stable("spacer"), width = ui.grow(), height = ui.fixed(0) },
        ui.column {
            key = ui.stable("swatch"),
            width = ui.fixed(14),
            height = ui.fixed(14),
            background = ui.prop_ref("accent"),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.95, 0.95, 0.98, 0.35) },
        } {},
    }),
}

local InfoRowWidget = ui.widget("InfoRow") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 8 },
    },
    props = {
        ui.widget_prop("lhs") { type = ui.types.string },
        ui.widget_prop("rhs") { type = ui.types.string },
    },
    parts = {
        ui.widget_part("root"),
        ui.widget_part("lhs"),
        ui.widget_part("rhs"),
    },
    root = ui.part("root", ui.row {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.top,
    } {
        ui.part("lhs", label(ui.prop_ref("lhs"), {
            width = ui.fixed(80),
            font_size = 14,
            text_color = tok_color("color.text.muted"),
        })),
        ui.part("rhs", label(ui.prop_ref("rhs"), {
            width = ui.grow(),
            font_size = 14,
            text_color = tok_color("color.text.primary"),
            wrap = ui.wrap.words,
        })),
    }),
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
        label(ui.prop_ref("title"), { font_size = 13, text_color = tok_color("color.text.muted") }),
        ui.column {
            key = ui.stable("track"),
            width = ui.fixed(220),
            height = ui.fixed(14),
            background = tok_color("color.surface.track"),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.border.track") },
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
        padding = inset(tok_number("space.bar.padding_x"), tok_number("space.bar.padding_y")),
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.center,
        background = tok_color("color.surface.toolbar"),
        border = ui.border { bottom = 1, color = tok_color("color.border.toolbar") },
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
        ui.row { key = ui.stable("bottom"), width = ui.fixed(520), height = ui.fit(), gap = 16, align_y = ui.align_y.top } {
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
        padding = inset(tok_number("space.bar.padding_x"), tok_number("space.bar.padding_y")),
        gap = ui.state_ref("gap"),
        align_y = ui.align_y.center,
        background = tok_color("color.surface.footer"),
        border = ui.border { top = 1, color = tok_color("color.border.footer") },
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
        background = tok_color("color.app.bg"),
    } {
        ui.slot("toolbar"),
        ui.row {
            key = ui.stable("main"),
            width = ui.grow(),
            height = ui.grow(),
            gap = tok_number("space.shell.gap"),
            padding = tok_number("space.shell.padding"),
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
    themes = themes,
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
        ui.with_theme("demo_dark") {
        ui.use(Shell) { key = app } {
        toolbar = {
            ui.use(ToolbarBar) { key = ui.stable("toolbar") } {
                primary = {
                    button("Inspect", "tool:inspect"),
                    themed_button("Paint", "tool:paint", {
                        ["color.button.bg"] = rgba(0.54, 0.28, 0.18, 1),
                        ["color.button.border"] = rgba(0.78, 0.48, 0.32, 1),
                    }),
                    themed_button("Lighting", "tool:lighting", {
                        ["color.button.bg"] = rgba(0.35, 0.28, 0.12, 1),
                        ["color.button.border"] = rgba(0.68, 0.55, 0.24, 1),
                    }),
                    themed_button("Export", "tool:export", {
                        ["color.button.bg"] = rgba(0.22, 0.44, 0.26, 1),
                        ["color.button.border"] = rgba(0.42, 0.70, 0.46, 1),
                    }),
                },
                trailing = {
                    ui.column { gap = 2, width = ui.fit(), height = ui.fit() } {
                        label("TerraUI SDL + OpenGL demo", { font_size = 18 }),
                        label(ui.param_ref("status_secondary"), { font_size = 13, text_color = tok_color("color.text.muted"), width = ui.fixed(320), wrap = ui.wrap.words }),
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
                scrollbar_background = tok_color("color.surface.scrollbar"),
                thumb_background = tok_color("color.scrollbar.thumb"),
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
                    styles = {
                        root = ui.style {
                            background = tok_color("color.surface.badge"),
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.border.badge") },
                            radius = ui.radius(6),
                        },
                    },
                } {},

                ui.use(PreviewCard) { key = preview_card } {
                    media = {
                        ui.image_view {
                            ref = "preview",
                            image = ui.param_ref("preview_image"),
                            width = ui.fixed(520),
                            height = ui.fixed(300),
                            aspect_ratio = 1.73,
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.border.preview") },
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
                        label(ui.param_ref("event_1"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle"), wrap = ui.wrap.words }),
                        label(ui.param_ref("event_2"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle"), wrap = ui.wrap.words }),
                        label(ui.param_ref("event_3"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle"), wrap = ui.wrap.words }),
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
                    label("Kernel: compiled layout + hit + emit", { width = ui.grow(), text_color = tok_color("color.text.muted"), wrap = ui.wrap.words }),
                    label("Backend: SDL_ttf + OpenGL replay with text texture cache", { width = ui.grow(), text_color = tok_color("color.text.muted"), wrap = ui.wrap.words }),
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
                    background = tok_color("color.surface.tooltip"),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = tok_color("color.border.tooltip") },
                } {
                    label(ui.param_ref("hint_text"), {
                        width = ui.fixed(260),
                        text_color = tok_color("color.text.tooltip"),
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
                    label("Selection", { font_size = 14, text_color = tok_color("color.text.muted") }),
                    ui.use(InfoRowWidget) { key = ui.stable("asset_info"), lhs = "Asset", rhs = ui.param_ref("selected_asset") } {},
                    ui.use(InfoRowWidget) { key = ui.stable("tool_info"), lhs = "Tool", rhs = ui.param_ref("selected_tool") } {},
                    ui.use(InfoRowWidget) {
                        key = ui.stable("target_info"),
                        lhs = "Target",
                        rhs = ui.param_ref("preview_title"),
                        styles = {
                            rhs = ui.style { text_color = ui.param_ref("accent") },
                        },
                    } {},
                    ui.custom {
                        key = ui.stable("accent_swatches"),
                        kind = "accent_swatches",
                        width = ui.fixed(280),
                        height = ui.fixed(44),
                    },
                },
                context = {
                    label("Tool context", { font_size = 14, text_color = tok_color("color.text.muted") }),
                    label(ui.param_ref("mode_summary"), { width = ui.grow(), font_size = 14, wrap = ui.wrap.words }),
                    label(ui.param_ref("mode_line_1"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle") , wrap = ui.wrap.words }),
                    label(ui.param_ref("mode_line_2"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle") , wrap = ui.wrap.words }),
                    label(ui.param_ref("mode_line_3"), { width = ui.grow(), font_size = 13, text_color = tok_color("color.text.subtle") , wrap = ui.wrap.words }),
                },
                metadata = {
                    label("Asset metadata", { font_size = 14, text_color = tok_color("color.text.muted") }),
                    label(ui.param_ref("asset_meta_1"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label(ui.param_ref("asset_meta_2"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                    label(ui.param_ref("asset_meta_3"), { width = ui.grow(), font_size = 13, wrap = ui.wrap.words }),
                },
                renderer = {
                    label("Renderer", { font_size = 14, text_color = tok_color("color.text.muted") }),
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
                    label(ui.param_ref("footer_text"), { font_size = 13, text_color = tok_color("color.text.subtle") }),
                },
                right = {
                    label("Terra AOT executable", { font_size = 13, text_color = tok_color("color.text.disabled") }),
                },
            },
        },
        },
        },
    },
}

return decl
