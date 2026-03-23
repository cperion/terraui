-- tests/dsl_test.t
-- Tests: declarative DSL and public entrypoint.

local terraui = require("lib/terraui")
local Decl = terraui.types.Decl

local ui = terraui.dsl()
assert(ui.scroll_container == nil)

---------------------------------------------------------------------------
-- Test 1: basic DSL lowers to Decl.Component
---------------------------------------------------------------------------

do
    local decl = ui.component("demo") {
        params = {
            ui.param("title") { type = ui.types.string, default = "Hello" },
        },
        state = {
            ui.state("hovered") { type = ui.types.bool, initial = false },
        },
        root = ui.column {
            key = ui.stable("root"),
            gap = 8,
        } {
            ui.label { key = ui.stable("lbl"), text = ui.param_ref("title") },
            ui.button { key = ui.stable("btn"), text = "Click", action = "go" },
        },
    }

    assert(Decl.Component:isclassof(decl))
    assert(decl.name == "demo")
    assert(#decl.params == 1)
    assert(#decl.state == 1)
    assert(decl.root.layout.axis == Decl.Column)
    assert(#decl.root.children == 2)
    assert(decl.root.children[1].kind == "NodeChild")
    assert(decl.root.children[1].value.leaf.kind == "Text")
    assert(decl.root.children[2].value.input.press == true)

    print("  test 1 (basic DSL lowering): ok")
end

---------------------------------------------------------------------------
-- Test 2: child helpers flatten deterministically
---------------------------------------------------------------------------

do
    local decl = ui.component("helpers") {
        root = ui.row { key = ui.stable("root") } {
            ui.fragment {
                ui.label { text = "A" },
                ui.label { text = "B" },
            },
            ui.when(true, ui.label { text = "C" }),
            ui.maybe(nil),
            ui.each({1,2}, function(x)
                return ui.label { key = ui.indexed("n", x), text = tostring(x) }
            end),
        },
    }

    assert(#decl.root.children == 5)
    assert(decl.root.children[1].value.leaf.kind == "Text")
    assert(decl.root.children[5].value.id.kind == "Indexed")

    print("  test 2 (child helpers): ok")
end

---------------------------------------------------------------------------
-- Test 3: scroll region and tooltip lower to scroll/floating
---------------------------------------------------------------------------

do
    local decl = ui.component("specials") {
        root = ui.column { key = ui.stable("root") } {
            ui.scroll_region {
                key = ui.stable("scroll"),
                vertical = true,
            } {
                ui.label { text = "Inside" },
            },
            ui.tooltip {
                key = ui.stable("tip"),
                target = ui.float.parent,
                parent_point = ui.attach.right_bottom,
                element_point = ui.attach.left_top,
                offset_x = 4,
                offset_y = 5,
            } {
                ui.label { text = "Tip" },
            },
        },
    }

    assert(decl.root.children[1].value.scroll ~= nil)
    assert(decl.root.children[1].value.scroll.vertical == true)
    assert(decl.root.children[1].value.clip == nil)
    assert(decl.root.children[2].value.floating ~= nil)
    assert(decl.root.children[2].value.floating.target == Decl.FloatParent)

    local ok, err = pcall(function()
        ui.scroll_region { vertical = true, scroll_y = 12 } {}
    end)
    assert(not ok)
    assert(err:match("scroll_x/scroll_y"))

    print("  test 3 (scroll/floating lowering): ok")
end

---------------------------------------------------------------------------
-- Test 4: widget DSL lowers to WidgetDef / WidgetCall / SlotRef
---------------------------------------------------------------------------

do
    local card = ui.widget("Card") {
        props = {
            ui.widget_prop("title") { type = ui.types.string },
        },
        slots = {
            ui.widget_slot("children"),
        },
        root = ui.column { key = ui.stable("root") } {
            ui.label { key = ui.stable("title"), text = ui.prop_ref("title") },
            ui.slot("children"),
        },
    }

    local decl = ui.component("widget_dsl") {
        widgets = { card },
        root = ui.column { key = ui.stable("root") } {
            ui.use("Card") { key = ui.stable("card1"), title = "Inspector" } {
                ui.label { text = "Body" },
            },
        },
    }

    assert(#decl.widgets == 1)
    assert(decl.widgets[1].name == "Card")
    assert(#decl.root.children == 1)
    assert(decl.root.children[1].kind == "WidgetChild")
    assert(decl.root.children[1].value.name == "Card")
    assert(decl.root.children[1].value.id.kind == "Stable")

    print("  test 4 (widget DSL lowering): ok")
end

---------------------------------------------------------------------------
-- Test 5: widget DSL supports local state and named slot sugar
---------------------------------------------------------------------------

do
    local split = ui.widget("Split") {
        state = {
            ui.state("gap") { type = ui.types.number, initial = 4 },
        },
        slots = {
            ui.widget_slot("left"),
            ui.widget_slot("right"),
        },
        root = ui.row { key = ui.stable("root"), gap = ui.state_ref("gap") } {
            ui.slot("left"),
            ui.slot("right"),
        },
    }

    local decl = ui.component("named_slots") {
        widgets = { split },
        root = ui.column { key = ui.stable("root") } {
            ui.use("Split") { key = ui.stable("split1") } {
                left = {
                    ui.label { text = "L" },
                },
                right = {
                    ui.label { text = "R" },
                },
            },
        },
    }

    assert(#decl.widgets[1].state == 1)
    assert(decl.widgets[1].state[1].name == "gap")
    assert(#decl.root.children == 1)
    assert(decl.root.children[1].kind == "WidgetChild")
    assert(#decl.root.children[1].value.slots == 2)
    assert(decl.root.children[1].value.slots[1].name == "left")
    assert(decl.root.children[1].value.slots[2].name == "right")

    local k = terraui.compile(decl)
    local Frame = k:frame_type()
    local run_q = k.kernels.run_fn
    local test = terra()
        var f : Frame
        f.viewport_w = 200; f.viewport_h = 120
        [run_q](&f)
        if f.text_count ~= 2 then return 1 end
        return 0
    end
    assert(test() == 0)

    print("  test 5 (widget state + named slot sugar): ok")
end

---------------------------------------------------------------------------
-- Test 6: widget DSL validates props/slots early and exposes scope helpers
---------------------------------------------------------------------------

do
    local card = ui.widget("StrictCard") {
        props = {
            ui.widget_prop("title") { type = ui.types.string },
        },
        slots = {
            ui.widget_slot("children"),
        },
        root = ui.column { key = ui.stable("root") } {
            ui.label { text = ui.prop_ref("title") },
            ui.slot("children"),
        },
    }

    local ok1, err1 = pcall(function()
        ui.use(card) { key = ui.stable("c1"), title = nil } {}
    end)
    assert(not ok1)
    assert(err1:match("missing required widget prop"))

    local ok2, err2 = pcall(function()
        ui.use(card) { key = ui.stable("c2"), title = "Hi", bogus = true } {}
    end)
    assert(not ok2)
    assert(err2:match("unknown widget prop"))

    local ok_type, err_type = pcall(function()
        ui.use(card) { key = ui.stable("c2b"), title = 42 } {}
    end)
    assert(not ok_type)
    assert(err_type:match("widget prop type mismatch"))

    local ok3, err3 = pcall(function()
        ui.use(card) { key = ui.stable("c3"), title = "Hi" } {
            side = { ui.label { text = "X" } },
        }
    end)
    assert(not ok3)
    assert(err3:match("unknown widget slot"))

    local card_scope = ui.scope("card1")
    local preview = card_scope:child("preview")
    assert(preview:key().kind == "Stable")
    assert(preview:key().name == "card1/preview")

    local item_scope = ui.scope(ui.indexed("card", 3))
    local item_preview = item_scope:child("preview")
    assert(item_preview:key().kind == "Indexed")
    assert(item_preview:key().name == "card/preview")

    local nested = card_scope:child("preview", "header")
    assert(nested:key().kind == "Stable")
    assert(nested:key().name == "card1/preview/header")

    local ft = card_scope:ref("preview")
    assert(ft.kind == "FloatById")
    assert(ft.id.kind == "Stable")
    assert(ft.id.name == "card1/preview")

    local decl = ui.component("scope_ids") {
        root = ui.column { key = card_scope } {
            ui.label { ref = "preview", text = "Preview" },
        },
    }
    local bound = terraui.bind(decl)
    assert(bound.root.stable_id.base == "card1")
    assert(bound.root.children[1].stable_id.base == "card1/preview")

    print("  test 6 (widget DSL validation + scope helpers): ok")
end

---------------------------------------------------------------------------
-- Test 7: scroll_area composes a viewport and live scrollbar thumb
---------------------------------------------------------------------------

do
    local decl = ui.component("scroll_area_demo") {
        root = ui.scroll_area {
            key = ui.scope("scrollbox"),
            width = ui.fixed(100),
            height = ui.fixed(60),
            vertical = true,
            bar_size = 10,
            viewport_padding = 10,
        } {
            ui.spacer {
                key = ui.stable("content"),
                width = ui.fixed(60),
                height = ui.fixed(200),
                background = ui.rgba(0.4, 0.4, 0.6, 1),
            },
        },
    }

    local k = terraui.compile(decl)
    local Frame = k:frame_type()
    local init_q = k.kernels.init_fn
    local run_q = k.kernels.run_fn
    local test = terra()
        var f : Frame
        [init_q](&f)
        f.viewport_w = 200; f.viewport_h = 200
        f.input.mouse_x = 15; f.input.mouse_y = 15
        f.input.wheel_dy = 1
        [run_q](&f)
        if f.scissor_count ~= 2 then return 1 end
        -- node 2 = viewport (scroll region)
        if f.nodes[2].scroll_y ~= 32 then return 2 end
        f.nodes[2].scroll_y = 160
        f.input.wheel_dy = 0
        [run_q](&f)
        -- node 6 = thumb, node 4 = vbar (overlay float)
        var thumb_bottom = f.nodes[6].y + f.nodes[6].h
        var track_bottom = f.nodes[4].content_y + f.nodes[4].content_h
        if thumb_bottom < track_bottom - 0.1f or thumb_bottom > track_bottom + 0.1f then return 3 end
        return 0
    end
    assert(test() == 0)

    print("  test 7 (scroll_area widget helper): ok")
end

---------------------------------------------------------------------------
-- Test 8: scroll_area track paging updates scroll offsets
---------------------------------------------------------------------------

do
    local decl = ui.component("scroll_area_track_paging") {
        root = ui.scroll_area {
            key = ui.scope("scrollbox"),
            width = ui.fixed(100),
            height = ui.fixed(60),
            vertical = true,
            bar_size = 10,
            viewport_padding = 10,
        } {
            ui.spacer {
                key = ui.stable("content"),
                width = ui.fixed(60),
                height = ui.fixed(200),
                background = ui.rgba(0.4, 0.4, 0.6, 1),
            },
        },
    }

    local k = terraui.compile(decl)
    local Frame = k:frame_type()
    local init_q = k.kernels.init_fn
    local run_q = k.kernels.run_fn
    local test = terra()
        var f : Frame
        [init_q](&f)
        f.viewport_w = 200; f.viewport_h = 200
        [run_q](&f)
        -- vbar is overlay float at right edge of body (inside outer padding)
        f.input.mouse_x = 95; f.input.mouse_y = 45
        f.input.mouse_pressed = true
        [run_q](&f)
        if f.nodes[2].scroll_y ~= 40 then return 1 end
        f.input.mouse_pressed = false
        f.input.mouse_released = true
        [run_q](&f)
        f.input.mouse_released = false
        f.input.mouse_pressed = true
        f.input.mouse_x = 95; f.input.mouse_y = 12
        [run_q](&f)
        if f.nodes[2].scroll_y ~= 0 then return 2 end
        return 0
    end
    assert(test() == 0)

    print("  test 8 (scroll_area track paging): ok")
end

---------------------------------------------------------------------------
-- Test 9: scroll_area hides scrollbar when content fits
---------------------------------------------------------------------------

do
    local decl = ui.component("scroll_area_hidden_bar") {
        root = ui.scroll_area {
            key = ui.scope("scrollbox"),
            width = ui.fixed(100),
            height = ui.fixed(60),
            vertical = true,
            bar_size = 10,
        } {
            ui.spacer {
                key = ui.stable("content"),
                width = ui.fixed(60),
                height = ui.fixed(20),
                background = ui.rgba(0.4, 0.4, 0.6, 1),
            },
        },
    }

    local k = terraui.compile(decl)
    local Frame = k:frame_type()
    local init_q = k.kernels.init_fn
    local run_q = k.kernels.run_fn
    local test = terra()
        var f : Frame
        [init_q](&f)
        f.viewport_w = 200; f.viewport_h = 200
        [run_q](&f)
        -- node 2 = viewport (scroll region), node 4 = vbar overlay float
        if f.nodes[2].scroll_need_y then return 1 end
        if f.nodes[4].visible then return 2 end
        var x0 = f.nodes[2].x
        [run_q](&f)
        if f.nodes[2].x ~= x0 then return 3 end
        return 0
    end
    assert(test() == 0)

    print("  test 9 (scroll_area hides unused scrollbar): ok")
end

---------------------------------------------------------------------------
-- Test 10: scroll_area solves cross-axis scrollbar dependence
---------------------------------------------------------------------------

do
    local decl = ui.component("scroll_area_cross_axis") {
        root = ui.scroll_area {
            key = ui.scope("scrollbox"),
            width = ui.fixed(100),
            height = ui.fixed(60),
            horizontal = true,
            vertical = true,
            bar_size = 10,
        } {
            ui.spacer {
                key = ui.stable("content"),
                width = ui.fixed(150),
                height = ui.fixed(120),
                background = ui.rgba(0.4, 0.4, 0.6, 1),
            },
        },
    }

    local k = terraui.compile(decl)
    local Frame = k:frame_type()
    local init_q = k.kernels.init_fn
    local run_q = k.kernels.run_fn
    local test = terra()
        var f : Frame
        [init_q](&f)
        f.viewport_w = 200; f.viewport_h = 200
        [run_q](&f)
        -- node 2 = viewport, node 4 = vbar float, node 8 = hbar float
        if not f.nodes[4].visible then return 1 end
        if not f.nodes[8].visible then return 2 end
        if not f.nodes[2].scroll_need_y then return 3 end
        if not f.nodes[2].scroll_need_x then return 4 end
        return 0
    end
    assert(test() == 0)

    print("  test 10 (scroll_area cross-axis solve): ok")
end

---------------------------------------------------------------------------
-- Test 11: public compile entry works and memoizes
---------------------------------------------------------------------------

do
    local decl = ui.component("compile_demo") {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.fixed(100),
            height = ui.fixed(50),
            background = ui.rgba(0.2, 0.3, 0.4, 1),
        } {
            ui.label { text = "Hello" },
        },
    }

    local custom_text_backend = { key = "dsl-test-backend" }
    function custom_text_backend:measure_width(ctx, spec)
        return `42.0f
    end
    function custom_text_backend:measure_height_for_width(ctx, spec, max_width)
        return `17.0f
    end

    local k1 = terraui.compile(decl)
    local k2 = terraui.compile(decl)
    local k3 = terraui.compile(decl, { text_backend = custom_text_backend })
    local k4 = terraui.compile(decl, { text_backend = custom_text_backend })

    assert(k1 == k2)
    assert(k3 == k4)
    assert(k1 ~= k3)
    assert(terralib.types.istype(k1:frame_type()))

    local Frame = k1:frame_type()
    local run_q = k1.kernels.run_fn
    local test = terra()
        var f : Frame
        f.viewport_w = 200; f.viewport_h = 200
        [run_q](&f)
        if f.rect_count ~= 1 then return 1 end
        if f.text_count ~= 1 then return 2 end
        return 0
    end
    assert(test() == 0)

    print("  test 11 (public compile entry): ok")
end

---------------------------------------------------------------------------
print("dsl test passed")
