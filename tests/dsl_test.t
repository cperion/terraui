-- tests/dsl_test.t
-- Tests: declarative DSL and public entrypoint.

local terraui = require("lib/terraui")
local Decl = terraui.types.Decl

local ui = terraui.dsl()

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
            id = ui.stable("root"),
            gap = 8,
        } {
            ui.label { id = ui.stable("lbl"), text = ui.param_ref("title") },
            ui.button { id = ui.stable("btn"), text = "Click", action = "go" },
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
        root = ui.row { id = ui.stable("root") } {
            ui.fragment {
                ui.label { text = "A" },
                ui.label { text = "B" },
            },
            ui.when(true, ui.label { text = "C" }),
            ui.maybe(nil),
            ui.each({1,2}, function(x)
                return ui.label { id = ui.indexed("n", x), text = tostring(x) }
            end),
        },
    }

    assert(#decl.root.children == 5)
    assert(decl.root.children[1].value.leaf.kind == "Text")
    assert(decl.root.children[5].value.id.kind == "Indexed")

    print("  test 2 (child helpers): ok")
end

---------------------------------------------------------------------------
-- Test 3: scroll region and tooltip lower to clip/floating
---------------------------------------------------------------------------

do
    local decl = ui.component("specials") {
        root = ui.column { id = ui.stable("root") } {
            ui.scroll_region {
                id = ui.stable("scroll"),
                vertical = true,
                scroll_y = 12,
            } {
                ui.label { text = "Inside" },
            },
            ui.tooltip {
                id = ui.stable("tip"),
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

    assert(decl.root.children[1].value.clip ~= nil)
    assert(decl.root.children[1].value.clip.vertical == true)
    assert(decl.root.children[2].value.floating ~= nil)
    assert(decl.root.children[2].value.floating.target == Decl.FloatParent)

    print("  test 3 (clip/floating lowering): ok")
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
        root = ui.column { id = ui.stable("root") } {
            ui.label { id = ui.stable("title"), text = ui.prop_ref("title") },
            ui.slot("children"),
        },
    }

    local decl = ui.component("widget_dsl") {
        widgets = { card },
        root = ui.column { id = ui.stable("root") } {
            ui.use("Card") { id = ui.stable("card1"), title = "Inspector" } {
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
        root = ui.row { id = ui.stable("root"), gap = ui.state_ref("gap") } {
            ui.slot("left"),
            ui.slot("right"),
        },
    }

    local decl = ui.component("named_slots") {
        widgets = { split },
        root = ui.column { id = ui.stable("root") } {
            ui.use("Split") { id = ui.stable("split1") } {
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
        root = ui.column { id = ui.stable("root") } {
            ui.label { text = ui.prop_ref("title") },
            ui.slot("children"),
        },
    }

    local ok1, err1 = pcall(function()
        ui.use(card) { id = ui.stable("c1") } {}
    end)
    assert(not ok1)
    assert(err1:match("missing required widget prop"))

    local ok2, err2 = pcall(function()
        ui.use(card) { id = ui.stable("c2"), title = "Hi", bogus = true } {}
    end)
    assert(not ok2)
    assert(err2:match("unknown widget prop"))

    local ok_type, err_type = pcall(function()
        ui.use(card) { id = ui.stable("c2b"), title = 42 } {}
    end)
    assert(not ok_type)
    assert(err_type:match("widget prop type mismatch"))

    local ok3, err3 = pcall(function()
        ui.use(card) { id = ui.stable("c3"), title = "Hi" } {
            side = { ui.label { text = "X" } },
        }
    end)
    assert(not ok3)
    assert(err3:match("unknown widget slot"))

    local card_scope = ui.scope("card1")
    local preview = card_scope:child("preview")
    assert(preview:id().kind == "Stable")
    assert(preview:id().name == "card1/preview")

    local item_scope = ui.scope(ui.indexed("card", 3))
    local item_preview = item_scope:child("preview")
    assert(item_preview:id().kind == "Indexed")
    assert(item_preview:id().name == "card/preview")

    local nested = card_scope:child("preview", "header")
    assert(nested:id().kind == "Stable")
    assert(nested:id().name == "card1/preview/header")

    local ft = card_scope:float("preview")
    assert(ft.kind == "FloatById")
    assert(ft.id.kind == "Stable")
    assert(ft.id.name == "card1/preview")

    local decl = ui.component("scope_ids") {
        root = ui.column { id = card_scope } {
            ui.label { id = preview, text = "Preview" },
        },
    }
    assert(decl.root.id.kind == "Stable")
    assert(decl.root.id.name == "card1")
    assert(decl.root.children[1].value.id.kind == "Stable")
    assert(decl.root.children[1].value.id.name == "card1/preview")

    print("  test 6 (widget DSL validation + scope helpers): ok")
end

---------------------------------------------------------------------------
-- Test 7: public compile entry works and memoizes
---------------------------------------------------------------------------

do
    local decl = ui.component("compile_demo") {
        root = ui.column {
            id = ui.stable("root"),
            width = ui.fixed(100),
            height = ui.fixed(50),
            background = ui.rgba(0.2, 0.3, 0.4, 1),
        } {
            ui.label { text = "Hello" },
        },
    }

    local k1 = terraui.compile(decl)
    local k2 = terraui.compile(decl)

    assert(k1 == k2)
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

    print("  test 7 (public compile entry): ok")
end

---------------------------------------------------------------------------
print("dsl test passed")
