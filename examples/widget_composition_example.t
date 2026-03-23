local terraui = require("lib/terraui")

local ui = terraui.dsl()

local function rgba(r, g, b, a)
    return ui.rgba(r, g, b, a)
end

local Section = ui.widget("Section") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 8 },
    },
    props = {
        ui.widget_prop("title") { type = ui.types.string },
    },
    slots = {
        ui.widget_slot("toolbar"),
        ui.widget_slot("children"),
    },
    root = ui.column {
        key = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
        padding = 10,
        background = rgba(0.11, 0.12, 0.14, 1),
        border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.24, 0.26, 0.30, 1) },
    } {
        ui.row { ref = "header", width = ui.grow(), height = ui.fit(), gap = 8 } {
            ui.label { text = ui.prop_ref("title"), font_size = 18 },
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            ui.slot("toolbar"),
        },
        ui.slot("children"),
    },
}

local Split = ui.widget("Split") {
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
        height = ui.grow(),
        gap = ui.state_ref("gap"),
    } {
        ui.column { key = ui.stable("left_col"), width = ui.grow(), height = ui.grow(), gap = 8 } {
            ui.slot("left"),
        },
        ui.column { key = ui.stable("right_col"), width = ui.grow(), height = ui.grow(), gap = 8 } {
            ui.slot("right"),
        },
    },
}

local workspace = ui.scope("workspace")
local assets = workspace:child("assets")
local preview = workspace:child("preview")

local decl = ui.component("widget_composition_example") {
    widgets = { Section, Split },
    root = ui.column {
        width = ui.fixed(640),
        height = ui.fixed(360),
        padding = 12,
        gap = 12,
        background = rgba(0.07, 0.08, 0.10, 1),
    } {
        ui.use(Split) { key = workspace } {
            left = {
                ui.use(Section) { key = assets, title = "Assets" } {
                    toolbar = {
                        ui.button { text = "Import", action = "import" },
                    },
                    children = {
                        ui.label { text = "Terrain" },
                        ui.label { text = "Roads" },
                        ui.label { text = "Water" },
                    },
                },
            },
            right = {
                ui.use(Section) { key = preview, title = "Preview" } {
                    toolbar = {
                        ui.button { text = "Refresh", action = "refresh" },
                    },
                    children = {
                        ui.image_view {
                            ref = "image",
                            image = "checker",
                            width = ui.fixed(280),
                            height = ui.fixed(180),
                        },
                        ui.tooltip {
                            key = ui.stable("tip"),
                            target = preview:target("image"),
                            parent_point = ui.attach.right_top,
                            element_point = ui.attach.left_bottom,
                            offset_x = 8,
                            offset_y = -6,
                            background = rgba(0.95, 0.86, 0.36, 0.98),
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.55, 0.43, 0.12, 1) },
                            padding = 8,
                        } {
                            ui.label { text = "Tooltip target resolved through preview:target(\"image\")", text_color = rgba(0.16, 0.13, 0.08, 1) },
                        },
                        ui.tooltip {
                            key = ui.stable("header_tip"),
                            target = preview:target("header"),
                            parent_point = ui.attach.right_bottom,
                            element_point = ui.attach.left_top,
                            offset_x = 8,
                            offset_y = 6,
                            background = rgba(0.76, 0.88, 0.98, 0.98),
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.28, 0.44, 0.60, 1) },
                            padding = 8,
                        } {
                            ui.label { text = "Section header targeted through preview:target(\"header\")", text_color = rgba(0.10, 0.18, 0.26, 1) },
                        },
                    },
                },
            },
        },
    },
}

local bound = terraui.bind(decl)
assert(#bound.state == 3)
local names = {}
for _, s in ipairs(bound.state) do names[s.name] = true end
assert(names["workspace/gap"])
assert(names["workspace/assets/gap"])
assert(names["workspace/preview/gap"])

local kernel = terraui.compile(decl)
local Frame = kernel:frame_type()
local run_q = kernel.kernels.run_fn
local test = terra()
    var f : Frame
    f.viewport_w = 640
    f.viewport_h = 360
    [run_q](&f)
    if f.text_count < 5 then return 1 end
    if f.image_count ~= 1 then return 2 end
    if f.scissor_count < 0 then return 3 end
    return 0
end
assert(test() == 0)

print("widget composition example passed")
