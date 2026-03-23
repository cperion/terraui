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
        id = ui.stable("root"),
        width = ui.grow(),
        height = ui.fit(),
        gap = ui.state_ref("gap"),
        padding = 10,
        background = rgba(0.11, 0.12, 0.14, 1),
        border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.24, 0.26, 0.30, 1) },
    } {
        ui.row { id = ui.stable("header"), width = ui.grow(), height = ui.fit(), gap = 8 } {
            ui.label { id = ui.stable("title"), text = ui.prop_ref("title"), font_size = 18 },
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
        id = ui.stable("root"),
        width = ui.grow(),
        height = ui.grow(),
        gap = ui.state_ref("gap"),
    } {
        ui.column { id = ui.stable("left_col"), width = ui.grow(), height = ui.grow(), gap = 8 } {
            ui.slot("left"),
        },
        ui.column { id = ui.stable("right_col"), width = ui.grow(), height = ui.grow(), gap = 8 } {
            ui.slot("right"),
        },
    },
}

local decl = ui.component("widget_composition_example") {
    widgets = { Section, Split },
    root = ui.column {
        id = ui.stable("root"),
        width = ui.fixed(640),
        height = ui.fixed(360),
        padding = 12,
        gap = 12,
        background = rgba(0.07, 0.08, 0.10, 1),
    } {
        ui.use(Split) { id = ui.stable("workspace") } {
            left = {
                ui.use(Section) { id = ui.stable("assets"), title = "Assets" } {
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
                ui.use(Section) { id = ui.stable("preview"), title = "Preview" } {
                    toolbar = {
                        ui.button { text = "Refresh", action = "refresh" },
                    },
                    children = {
                        ui.image_view {
                            id = ui.stable("image"),
                            image = "checker",
                            width = ui.fixed(280),
                            height = ui.fixed(180),
                        },
                        ui.tooltip {
                            id = ui.stable("tip"),
                            target = ui.float.path("preview", "image"),
                            parent_point = ui.attach.right_top,
                            element_point = ui.attach.left_bottom,
                            offset_x = 8,
                            offset_y = -6,
                            background = rgba(0.95, 0.86, 0.36, 0.98),
                            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.55, 0.43, 0.12, 1) },
                            padding = 8,
                        } {
                            ui.label { text = "Tooltip target resolved through ui.float.path", text_color = rgba(0.16, 0.13, 0.08, 1) },
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
assert(names["assets/gap"])
assert(names["preview/gap"])

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
