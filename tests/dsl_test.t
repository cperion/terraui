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
    assert(decl.root.children[1].leaf.kind == "Text")
    assert(decl.root.children[2].input.press == true)

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
    assert(decl.root.children[1].leaf.kind == "Text")
    assert(decl.root.children[5].id.kind == "Indexed")

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

    assert(decl.root.children[1].clip ~= nil)
    assert(decl.root.children[1].clip.vertical == true)
    assert(decl.root.children[2].floating ~= nil)
    assert(decl.root.children[2].floating.target == Decl.FloatParent)

    print("  test 3 (clip/floating lowering): ok")
end

---------------------------------------------------------------------------
-- Test 4: public compile entry works and memoizes
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

    print("  test 4 (public compile entry): ok")
end

---------------------------------------------------------------------------
print("dsl test passed")
