-- tests/plan_test.t
-- Tests: Bound -> Plan phase transition via lib/plan.t

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local bind = require("lib/bind")
local plan = require("lib/plan")

local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound
local Plan = TerraUI.types.Plan

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local zero = Decl.NumLit(0)

local function no_vis()
    return Decl.Visibility(nil, nil)
end

local function no_decor()
    return Decl.Decor(nil, nil, nil, nil)
end

local function no_input()
    return Decl.Input(false, false, false, false, nil, nil)
end

local function zero_padding()
    return Decl.Padding(zero, zero, zero, zero)
end

local function fit_layout()
    return Decl.Layout(
        Decl.Row, Decl.Fit(nil, nil), Decl.Fit(nil, nil),
        zero_padding(), zero, Decl.AlignLeft, Decl.AlignTop)
end

local function text_style()
    return Decl.TextStyle(
        Decl.ColorLit(1, 1, 1, 1), Decl.StringLit("default"),
        Decl.NumLit(14), Decl.NumLit(0), Decl.NumLit(1.2),
        Decl.WrapNone, Decl.TextAlignLeft)
end

local function child_list(xs)
    local out = List()
    for _, x in ipairs(xs or {}) do
        if Decl.Node:isclassof(x) then
            out:insert(Decl.NodeChild(x))
        else
            out:insert(x)
        end
    end
    return out
end

local function component(name, params, state, root, widgets)
    return Decl.Component(name, params or List(), state or List(), widgets or List(), root)
end

local function node(id, visibility, layout, decor, clip, floating, input, aspect_ratio, leaf, children)
    return Decl.Node(id, visibility, layout, decor, clip, nil, nil, floating, input, aspect_ratio, leaf, child_list(children))
end

local function make_label(name, text)
    return node(
        Decl.Stable(name), no_vis(), fit_layout(), no_decor(),
        nil, nil, no_input(), nil,
        Decl.Text(Decl.TextLeaf(Decl.StringLit(text), text_style())),
        child_list())
end

local function make_box(name, children)
    return node(
        Decl.Stable(name), no_vis(),
        Decl.Layout(Decl.Column, Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            zero_padding(), Decl.NumLit(8), Decl.AlignLeft, Decl.AlignTop),
        no_decor(), nil, nil, no_input(), nil, nil, children)
end

local function bind_and_plan(decl_comp)
    local bound = bind.bind_component(decl_comp)
    return plan.plan_component(bound), bound
end

---------------------------------------------------------------------------
-- Test 1: simple tree flattening
---------------------------------------------------------------------------

do
    local comp = component(
        "simple", List(), List(),
        make_box("root", List{
            make_label("a", "A"),
            make_label("b", "B"),
        }))

    local p = bind_and_plan(comp)

    -- 3 nodes total
    assert(#p.nodes == 3)

    -- Root = index 0
    local root = p.nodes[1]
    assert(root.index == 0)
    assert(root.parent == nil)      -- root has no parent
    assert(root.first_child == 1)
    assert(root.child_count == 2)
    assert(root.subtree_end == 3)

    -- Child a = index 1
    local a = p.nodes[2]
    assert(a.index == 1)
    assert(a.parent == 0)
    assert(a.child_count == 0)
    assert(a.subtree_end == 2)
    assert(a.first_child == nil)

    -- Child b = index 2
    local b = p.nodes[3]
    assert(b.index == 2)
    assert(b.parent == 0)
    assert(b.child_count == 0)
    assert(b.subtree_end == 3)

    -- Root index
    assert(p.root_index == 0)

    print("  test 1 (tree flattening): ok")
end

---------------------------------------------------------------------------
-- Test 2: side tables populated
---------------------------------------------------------------------------

do
    local comp = component(
        "sides", List(), List(),
        make_box("root", List{
            make_label("a", "A"),
        }))

    local p = bind_and_plan(comp)

    -- 2 nodes -> 2 guards, 2 paints, 2 inputs
    assert(#p.guards == 2)
    assert(#p.paints == 2)
    assert(#p.inputs == 2)

    -- 1 text leaf
    assert(#p.texts == 1)
    assert(p.texts[1].node_index == 1)

    -- No clips, images, customs, floats
    assert(#p.clips == 0)
    assert(#p.images == 0)
    assert(#p.customs == 0)
    assert(#p.floats == 0)

    -- Slot references on nodes
    local root = p.nodes[1]
    assert(root.guard_slot == 0)
    assert(root.paint_slot == 0)
    assert(root.input_slot == 0)
    assert(root.text_slot == nil)

    local a = p.nodes[2]
    assert(a.guard_slot == 1)
    assert(a.paint_slot == 1)
    assert(a.input_slot == 1)
    assert(a.text_slot == 0)

    print("  test 2 (side tables): ok")
end

---------------------------------------------------------------------------
-- Test 3: binding lowering (Value -> Binding)
---------------------------------------------------------------------------

do
    local comp = component(
        "bindings",
        List{ Decl.Param("x", Decl.TNumber, nil) },
        List{ Decl.StateSlot("y", Decl.TNumber, nil) },
        node(
            Decl.Stable("root"), no_vis(),
            Decl.Layout(
                Decl.Column,
                Decl.Fixed(Decl.ParamRef("x")),
                Decl.Fixed(Decl.StateRef("y")),
                zero_padding(),
                Decl.Binary("+", Decl.NumLit(4), Decl.ParamRef("x")),
                Decl.AlignLeft, Decl.AlignTop),
            no_decor(), nil, nil, no_input(), nil, nil, List()))

    local p = bind_and_plan(comp)
    local root = p.nodes[1]

    -- Width = Fixed(Param(0))
    assert(root.width.kind == "Fixed")
    assert(root.width.value.kind == "Param")
    assert(root.width.value.slot == 0)

    -- Height = Fixed(State(0))
    assert(root.height.kind == "Fixed")
    assert(root.height.value.kind == "State")
    assert(root.height.value.slot == 0)

    -- Gap = Expr("+", [ConstNumber(4), Param(0)])
    assert(root.gap.kind == "Expr")
    assert(root.gap.op == "+")
    assert(#root.gap.args == 2)
    assert(root.gap.args[1].kind == "ConstNumber")
    assert(root.gap.args[1].v == 4)
    assert(root.gap.args[2].kind == "Param")
    assert(root.gap.args[2].slot == 0)

    print("  test 3 (binding lowering): ok")
end

---------------------------------------------------------------------------
-- Test 4: text spec bindings
---------------------------------------------------------------------------

do
    local comp = component(
        "textspec", List(), List(),
        make_label("lbl", "Hello"))

    local p = bind_and_plan(comp)

    assert(#p.texts == 1)
    local ts = p.texts[1]
    assert(ts.node_index == 0)
    assert(ts.content.kind == "ConstString")
    assert(ts.content.v == "Hello")
    assert(ts.font_size.kind == "ConstNumber")
    assert(ts.font_size.v == 14)
    assert(ts.wrap == Decl.WrapNone)
    assert(ts.align == Decl.TextAlignLeft)

    print("  test 4 (text spec): ok")
end

---------------------------------------------------------------------------
-- Test 5: clip + scroll side tables
---------------------------------------------------------------------------

do
    local comp = component(
        "cliptest", List(), List(),
        Decl.Node(
            Decl.Stable("root"), no_vis(), fit_layout(), no_decor(),
            Decl.Clip(true, false),
            Decl.Scroll(false, true),
            nil,
            nil, no_input(), nil, nil, List()))

    local p = bind_and_plan(comp)

    assert(#p.clips == 1)
    assert(#p.scrolls == 1)

    local cs = p.clips[1]
    assert(cs.node_index == 0)
    assert(cs.horizontal == true)
    assert(cs.vertical == true)

    local ss = p.scrolls[1]
    assert(ss.node_index == 0)
    assert(ss.horizontal == false)
    assert(ss.vertical == true)

    assert(p.nodes[1].clip_slot == 0)
    assert(p.nodes[1].scroll_slot == 0)

    print("  test 5 (clip + scroll side tables): ok")
end

---------------------------------------------------------------------------
-- Test 6: decor with border and radius
---------------------------------------------------------------------------

do
    local one = Decl.NumLit(1)
    local four = Decl.NumLit(4)
    local comp = component(
        "decortest", List(), List(),
        node(
            Decl.Stable("root"), no_vis(), fit_layout(),
            Decl.Decor(
                Decl.ColorLit(0.1, 0.1, 0.1, 1),
                Decl.Border(one, one, one, one, zero, Decl.ColorLit(0,0,0,1)),
                Decl.CornerRadius(four, four, four, four),
                Decl.NumLit(0.9)),
            nil, nil, no_input(), nil, nil, List()))

    local p = bind_and_plan(comp)

    local paint = p.paints[1]
    assert(paint.background.kind == "ConstColor")
    assert(paint.border ~= nil)
    assert(paint.border.left.kind == "ConstNumber")
    assert(paint.border.left.v == 1)
    assert(paint.radius ~= nil)
    assert(paint.radius.top_left.kind == "ConstNumber")
    assert(paint.radius.top_left.v == 4)
    assert(paint.opacity.kind == "ConstNumber")
    assert(paint.opacity.v == 0.9)

    print("  test 6 (decor): ok")
end

---------------------------------------------------------------------------
-- Test 7: floating (FloatParent)
---------------------------------------------------------------------------

do
    local comp = component(
        "floattest", List(), List(),
        make_box("root", List{
            node(
                Decl.Stable("tooltip"), no_vis(), fit_layout(), no_decor(),
                nil,
                Decl.Floating(
                    Decl.FloatParent,
                    Decl.AttachCenter,
                    Decl.AttachBottomCenter,
                    zero, zero, zero, zero,
                    Decl.NumLit(10),
                    Decl.Capture),
                no_input(), nil, nil, List()),
        }))

    local p = bind_and_plan(comp)

    assert(#p.floats == 1)
    local fs = p.floats[1]
    assert(fs.node_index == 1)
    assert(fs.attach_parent_slot == 0)  -- parent is root at index 0
    assert(fs.z_index.kind == "ConstNumber")
    assert(fs.z_index.v == 10)
    assert(fs.pointer_capture == Decl.Capture)
    assert(p.nodes[2].float_slot == 0)

    print("  test 7 (floating): ok")
end

---------------------------------------------------------------------------
-- Test 8: deep tree subtree_end
---------------------------------------------------------------------------

do
    -- root(0)
    --   a(1)
    --     a1(2)
    --     a2(3)
    --   b(4)
    local comp = component(
        "deep", List(), List(),
        make_box("root", List{
            make_box("a", List{
                make_label("a1", "A1"),
                make_label("a2", "A2"),
            }),
            make_label("b", "B"),
        }))

    local p = bind_and_plan(comp)
    assert(#p.nodes == 5)

    assert(p.nodes[1].index == 0)
    assert(p.nodes[1].subtree_end == 5)

    assert(p.nodes[2].index == 1)
    assert(p.nodes[2].subtree_end == 4)
    assert(p.nodes[2].first_child == 2)
    assert(p.nodes[2].child_count == 2)

    assert(p.nodes[3].index == 2)
    assert(p.nodes[3].subtree_end == 3)

    assert(p.nodes[4].index == 3)
    assert(p.nodes[4].subtree_end == 4)

    assert(p.nodes[5].index == 4)
    assert(p.nodes[5].subtree_end == 5)

    print("  test 8 (deep subtree_end): ok")
end

---------------------------------------------------------------------------
-- Test 9: image leaf
---------------------------------------------------------------------------

do
    local comp = component(
        "imgtest", List(), List(),
        node(
            Decl.Stable("img"), no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil,
            Decl.Image(Decl.ImageLeaf(
                Decl.StringLit("tex"),
                Decl.ColorLit(1, 1, 1, 1),
                Decl.ImageContain)),
            List()))

    local p = bind_and_plan(comp)

    assert(#p.images == 1)
    assert(p.images[1].image_id.kind == "ConstString")
    assert(p.images[1].image_id.v == "tex")
    assert(p.images[1].fit == Decl.ImageContain)
    assert(p.nodes[1].image_slot == 0)
    assert(p.nodes[1].text_slot == nil)

    print("  test 9 (image leaf): ok")
end

---------------------------------------------------------------------------
-- Test 10: aspect ratio
---------------------------------------------------------------------------

do
    local comp = component(
        "artest", List(), List(),
        node(
            Decl.Stable("root"), no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(),
            Decl.NumLit(1.777),
            nil, List()))

    local p = bind_and_plan(comp)
    assert(p.nodes[1].aspect_ratio ~= nil)
    assert(p.nodes[1].aspect_ratio.kind == "ConstNumber")
    assert(math.abs(p.nodes[1].aspect_ratio.v - 1.777) < 0.001)

    print("  test 10 (aspect ratio): ok")
end

---------------------------------------------------------------------------
-- Test 11: visibility guard bindings
---------------------------------------------------------------------------

do
    local comp = component(
        "guardstest",
        List{ Decl.Param("show", Decl.TBool, nil) },
        List(),
        node(
            Decl.Stable("root"),
            Decl.Visibility(Decl.ParamRef("show"), nil),
            fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil, List()))

    local p = bind_and_plan(comp)

    local g = p.guards[1]
    assert(g.visible_when ~= nil)
    assert(g.visible_when.kind == "Param")
    assert(g.visible_when.slot == 0)
    assert(g.enabled_when == nil)

    print("  test 11 (visibility guard): ok")
end

---------------------------------------------------------------------------
-- Test 12: select / intrinsic bindings survive planning
---------------------------------------------------------------------------

do
    local comp = component(
        "exprtest",
        List{ Decl.Param("x", Decl.TNumber, nil) },
        List(),
        node(
            Decl.Stable("root"), no_vis(),
            Decl.Layout(
                Decl.Row,
                Decl.Fixed(
                    Decl.Select(
                        Decl.BoolLit(true),
                        Decl.NumLit(100),
                        Decl.ParamRef("x"))),
                Decl.Fit(nil, nil),
                zero_padding(), zero,
                Decl.AlignLeft, Decl.AlignTop),
            no_decor(), nil, nil, no_input(), nil, nil, List()))

    local p = bind_and_plan(comp)
    local w = p.nodes[1].width
    assert(w.kind == "Fixed")
    assert(w.value.kind == "Expr")
    assert(w.value.op == "select")
    assert(#w.value.args == 3)
    assert(w.value.args[1].kind == "ConstBool")
    assert(w.value.args[2].kind == "ConstNumber")
    assert(w.value.args[3].kind == "Param")

    print("  test 12 (select binding): ok")
end

---------------------------------------------------------------------------
print("plan test passed")
