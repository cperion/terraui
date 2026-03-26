-- tests/bind_test.t
-- Tests: Decl -> Bound phase transition via lib/bind.t

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local bind = require("lib/bind")

local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound

---------------------------------------------------------------------------
-- Helpers for building Decl trees by hand
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
        Decl.Row,
        Decl.Fit(nil, nil),
        Decl.Fit(nil, nil),
        zero_padding(),
        zero,
        Decl.AlignLeft,
        Decl.AlignTop)
end

local function text_style()
    return Decl.TextStyle(
        Decl.ColorLit(1, 1, 1, 1),
        Decl.StringLit("default"),
        Decl.NumLit(14),
        Decl.NumLit(0),
        Decl.NumLit(1.2),
        Decl.WrapNone,
        Decl.TextAlignLeft)
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

local function component(name, params, state, root, widgets, themes)
    return Decl.Component(name, params or List(), state or List(), themes or List(), widgets or List(), root)
end

local function node(id, visibility, layout, decor, clip, floating, input, aspect_ratio, leaf, children)
    return Decl.Node(id, nil, nil, visibility, layout, decor, clip, nil, nil, floating, input, aspect_ratio, leaf, child_list(children))
end

local function make_label(name, text)
    return node(
        Decl.Stable(name),
        no_vis(), fit_layout(), no_decor(),
        nil, nil, no_input(), nil,
        Decl.Text(Decl.TextLeaf(Decl.StringLit(text), text_style())),
        child_list())
end

---------------------------------------------------------------------------
-- Test 1: minimal component bind
---------------------------------------------------------------------------

do
    local comp = component(
        "test_comp",
        List{ Decl.Param("title", Decl.TString, Decl.StringLit("hello")) },
        List{ Decl.StateSlot("count", Decl.TNumber, Decl.NumLit(0)) },
        node(
            Decl.Stable("root"),
            no_vis(),
            Decl.Layout(
                Decl.Column,
                Decl.Grow(nil, nil),
                Decl.Grow(nil, nil),
                zero_padding(),
                Decl.NumLit(8),
                Decl.AlignLeft,
                Decl.AlignTop),
            no_decor(),
            nil, nil, no_input(), nil, nil,
            List{ make_label("label1", "Hello"),
                  make_label("label2", "World") }))

    local bound = bind.bind_component(comp)

    assert(bound.name == "test_comp")

    -- Params
    assert(#bound.params == 1)
    assert(bound.params[1].name == "title")
    assert(bound.params[1].slot == 0)

    -- State
    assert(#bound.state == 1)
    assert(bound.state[1].name == "count")
    assert(bound.state[1].slot == 0)
    assert(bound.state[1].initial ~= nil)
    assert(bound.state[1].initial.kind == "ConstNumber")
    assert(bound.state[1].initial.v == 0)

    -- Root
    assert(bound.root.stable_id.base == "root")
    assert(bound.root.local_id == 0)
    assert(#bound.root.children == 2)

    -- Children
    assert(bound.root.children[1].stable_id.base == "label1")
    assert(bound.root.children[1].local_id == 1)
    assert(bound.root.children[2].stable_id.base == "label2")
    assert(bound.root.children[2].local_id == 2)

    -- Layout axis pass-through
    assert(bound.root.layout.axis == Decl.Column)

    -- Gap binding
    assert(bound.root.layout.gap.kind == "ConstNumber")
    assert(bound.root.layout.gap.v == 8)

    -- Size binding
    assert(bound.root.layout.width.kind == "Grow")
    assert(bound.root.layout.height.kind == "Grow")

    -- Leaf
    local leaf = bound.root.children[1].leaf
    assert(leaf ~= nil)
    assert(leaf.kind == "Text")
    assert(leaf.value.content.kind == "ConstString")
    assert(leaf.value.content.v == "Hello")
    assert(leaf.value.style.font_size.kind == "ConstNumber")
    assert(leaf.value.style.font_size.v == 14)
    assert(leaf.value.style.wrap == Decl.WrapNone)

    -- Key
    assert(bound.key ~= nil)
    assert(bound.key.renderer == "default")

    print("  test 1 (component bind): ok")
end

---------------------------------------------------------------------------
-- Test 2: Expr variants
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()
    ctx:register_param("x")
    ctx:register_state("y")

    -- Literals
    assert(Decl.BoolLit(true):bind(ctx).kind == "ConstBool")
    assert(Decl.BoolLit(true):bind(ctx).v == true)
    assert(Decl.NumLit(42):bind(ctx).kind == "ConstNumber")
    assert(Decl.NumLit(42):bind(ctx).v == 42)
    assert(Decl.StringLit("hi"):bind(ctx).kind == "ConstString")
    assert(Decl.StringLit("hi"):bind(ctx).v == "hi")

    local c = Decl.ColorLit(0.1, 0.2, 0.3, 1):bind(ctx)
    assert(c.kind == "ConstColor")
    assert(c.r == 0.1 and c.g == 0.2 and c.b == 0.3 and c.a == 1)

    local v = Decl.Vec2Lit(10, 20):bind(ctx)
    assert(v.kind == "ConstVec2")
    assert(v.x == 10 and v.y == 20)

    -- Param/state refs
    local p = Decl.ParamRef("x"):bind(ctx)
    assert(p.kind == "ParamSlot" and p.slot == 0)

    local s = Decl.StateRef("y"):bind(ctx)
    assert(s.kind == "StateSlotRef" and s.slot == 0)

    -- Env/theme
    local e = Decl.EnvRef("viewport_w"):bind(ctx)
    assert(e.kind == "EnvSlot" and e.name == "viewport_w")

    local t = Decl.TokenRef("bg_color"):bind(ctx)
    assert(t.kind == "EnvSlot" and t.name == "token:bg_color")

    -- Unary
    local u = Decl.Unary("-", Decl.NumLit(5)):bind(ctx)
    assert(u.kind == "Unary" and u.op == "-")
    assert(u.rhs.kind == "ConstNumber" and u.rhs.v == 5)

    -- Binary
    local b = Decl.Binary("+",
        Decl.ParamRef("x"), Decl.NumLit(1)):bind(ctx)
    assert(b.kind == "Binary" and b.op == "+")
    assert(b.lhs.kind == "ParamSlot" and b.lhs.slot == 0)
    assert(b.rhs.kind == "ConstNumber" and b.rhs.v == 1)

    -- Select
    local sel = Decl.Select(
        Decl.BoolLit(true),
        Decl.NumLit(1),
        Decl.NumLit(2)):bind(ctx)
    assert(sel.kind == "Select")
    assert(sel.cond.kind == "ConstBool")
    assert(sel.yes.kind == "ConstNumber" and sel.yes.v == 1)
    assert(sel.no.kind == "ConstNumber" and sel.no.v == 2)

    -- Call -> Intrinsic
    local call = Decl.Call("abs", List{ Decl.NumLit(-5) }):bind(ctx)
    assert(call.kind == "Intrinsic")
    assert(call.fn == "abs")
    assert(#call.args == 1)
    assert(call.args[1].kind == "ConstNumber" and call.args[1].v == -5)

    print("  test 2 (expr variants): ok")
end

---------------------------------------------------------------------------
-- Test 3: Size variants
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()

    local fit = Decl.Fit(Decl.NumLit(10), Decl.NumLit(100)):bind(ctx)
    assert(fit.kind == "Fit")
    assert(fit.min.v == 10 and fit.max.v == 100)

    local grow = Decl.Grow(nil, nil):bind(ctx)
    assert(grow.kind == "Grow")
    assert(grow.min == nil and grow.max == nil)

    local fixed = Decl.Fixed(Decl.NumLit(48)):bind(ctx)
    assert(fixed.kind == "Fixed" and fixed.value.v == 48)

    local pct = Decl.Percent(Decl.NumLit(0.5)):bind(ctx)
    assert(pct.kind == "Percent" and pct.value.v == 0.5)

    print("  test 3 (size variants): ok")
end

---------------------------------------------------------------------------
-- Test 4: Decor with border and radius
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()
    local one = Decl.NumLit(1)

    local border = Decl.Border(one, one, one, one, zero, Decl.ColorLit(0,0,0,1))
    local radius = Decl.CornerRadius(
        Decl.NumLit(4), Decl.NumLit(4), Decl.NumLit(4), Decl.NumLit(4))
    local decor = Decl.Decor(
        Decl.ColorLit(0.1, 0.1, 0.1, 1),
        border, radius,
        Decl.NumLit(0.9))

    local bd = decor:bind(ctx)
    assert(bd.background.kind == "ConstColor")
    assert(bd.border ~= nil)
    assert(bd.border.left.v == 1)
    assert(bd.border.color.kind == "ConstColor")
    assert(bd.radius ~= nil)
    assert(bd.radius.top_left.v == 4)
    assert(bd.opacity.v == 0.9)

    print("  test 4 (decor bind): ok")
end

---------------------------------------------------------------------------
-- Test 5: Clip and scroll bind
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()

    local clip = Decl.Clip(true, false)
    local bc = clip:bind(ctx)
    assert(bc.horizontal == true)
    assert(bc.vertical == false)

    local scroll = Decl.Scroll(false, true)
    local bs = scroll:bind(ctx)
    assert(bs.horizontal == false)
    assert(bs.vertical == true)

    print("  test 5 (clip and scroll bind): ok")
end

---------------------------------------------------------------------------
-- Test 6: Floating bind
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()

    local floating = Decl.Floating(
        Decl.FloatParent,
        Decl.AttachCenter,
        Decl.AttachBottomCenter,
        zero, zero, zero, zero,
        Decl.NumLit(10),
        Decl.Capture)

    local bf = floating:bind(ctx)
    assert(bf.target == Bound.FloatParent)
    assert(bf.element_point == Decl.AttachCenter)
    assert(bf.parent_point == Decl.AttachBottomCenter)
    assert(bf.z_index.v == 10)
    assert(bf.pointer_capture == Decl.Capture)

    print("  test 6 (floating bind): ok")
end

---------------------------------------------------------------------------
-- Test 7: Indexed id
---------------------------------------------------------------------------

do
    local comp = component(
        "indexed_test",
        List(),
        List(),
        node(
            Decl.Indexed("item", Decl.NumLit(42)),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil, List()))

    local bound = bind.bind_component(comp)
    assert(bound.root.stable_id.base == "item")
    assert(bound.root.stable_id.salt == 42)

    print("  test 7 (indexed id): ok")
end

---------------------------------------------------------------------------
-- Test 8: Auto id
---------------------------------------------------------------------------

do
    local comp = component(
        "auto_test",
        List(),
        List(),
        node(
            Decl.Auto,
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil, List()))

    local bound = bind.bind_component(comp)
    assert(bound.root.stable_id.base:match("__auto_0"))
    assert(bound.root.stable_id.salt == 0)

    print("  test 8 (auto id): ok")
end

---------------------------------------------------------------------------
-- Test 9: Image leaf
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()

    local img = Decl.ImageLeaf(
        Decl.StringLit("tex_01"),
        Decl.ColorLit(1, 1, 1, 1),
        Decl.ImageStretch)

    local bi = img:bind(ctx)
    assert(bi.image_id.kind == "ConstString")
    assert(bi.image_id.v == "tex_01")
    assert(bi.tint.kind == "ConstColor")
    assert(bi.fit == Decl.ImageStretch)

    print("  test 9 (image leaf): ok")
end

---------------------------------------------------------------------------
-- Test 10: Custom leaf
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()

    local cust = Decl.CustomLeaf("canvas", Decl.NumLit(99))
    local bc = cust:bind(ctx)
    assert(bc.kind == "canvas")
    assert(bc.payload.v == 99)

    print("  test 10 (custom leaf): ok")
end

---------------------------------------------------------------------------
-- Test 11: Error on unknown param
---------------------------------------------------------------------------

do
    local ctx = bind.BindCtx.new()
    local ok, err = pcall(function()
        Decl.ParamRef("missing"):bind(ctx)
    end)
    assert(not ok)
    assert(err:match("unknown param"))

    print("  test 11 (unknown param error): ok")
end

---------------------------------------------------------------------------
-- Test 12: Error on duplicate param
---------------------------------------------------------------------------

do
    local ok, err = pcall(function()
        bind.bind_component(component(
            "dup_test",
            List{ Decl.Param("x", Decl.TNumber, nil),
                  Decl.Param("x", Decl.TNumber, nil) },
            List(),
            node(Decl.Auto, no_vis(), fit_layout(), no_decor(),
                nil, nil, no_input(), nil, nil, List())))
    end)
    assert(not ok)
    assert(err:match("duplicate param"))

    print("  test 12 (duplicate param error): ok")
end

---------------------------------------------------------------------------
-- Test 13: Multiple params get distinct slots
---------------------------------------------------------------------------

do
    local comp = component(
        "multi_param",
        List{ Decl.Param("a", Decl.TNumber, nil),
              Decl.Param("b", Decl.TString, nil),
              Decl.Param("c", Decl.TBool, nil) },
        List(),
        node(Decl.Auto, no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil, List()))

    local bound = bind.bind_component(comp)
    assert(bound.params[1].slot == 0)
    assert(bound.params[2].slot == 1)
    assert(bound.params[3].slot == 2)

    print("  test 13 (multi param slots): ok")
end

---------------------------------------------------------------------------
-- Test 14: Visibility with expressions
---------------------------------------------------------------------------

do
    local comp = component(
        "vis_test",
        List{ Decl.Param("show", Decl.TBool, nil) },
        List(),
        node(
            Decl.Stable("root"),
            Decl.Visibility(
                Decl.ParamRef("show"),
                nil),
            fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil, List()))

    local bound = bind.bind_component(comp)
    assert(bound.root.visibility.visible_when ~= nil)
    assert(bound.root.visibility.visible_when.kind == "ParamSlot")
    assert(bound.root.visibility.visible_when.slot == 0)
    assert(bound.root.visibility.enabled_when == nil)

    print("  test 14 (visibility bind): ok")
end

---------------------------------------------------------------------------
-- Test 15: widget calls elaborate during bind with scoped ids
---------------------------------------------------------------------------

do
    local card = Decl.WidgetDef(
        "Card",
        List{ Decl.WidgetProp("title", Decl.TString, nil) },
        List(),
        List{ Decl.WidgetSlot("children") },
        List(),
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil,
            child_list {
                node(
                    Decl.Stable("title"),
                    no_vis(), fit_layout(), no_decor(),
                    nil, nil, no_input(), nil,
                    Decl.Text(Decl.TextLeaf(Decl.WidgetPropRef("title"), text_style())),
                    List()),
                Decl.SlotRef("children"),
            }))

    local comp = component(
        "widget_bind",
        List(),
        List(),
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil,
            child_list {
                Decl.WidgetChild(Decl.WidgetCall(
                    Decl.Stable("card1"),
                    "Card",
                    List{ Decl.PropArg("title", Decl.StringLit("Inspector")) },
                    List(),
                    List{ Decl.SlotArg("children", child_list { make_label("body", "Hello") }) }, nil))
            }),
        List{ card })

    local bound = bind.bind_component(comp)
    assert(#bound.root.children == 1)
    assert(bound.root.children[1].stable_id.base == "card1")
    assert(#bound.root.children[1].children == 2)
    assert(bound.root.children[1].children[1].stable_id.base == "card1/title")
    assert(bound.root.children[1].children[2].stable_id.base == "card1/body")

    local title_leaf = bound.root.children[1].children[1].leaf
    assert(title_leaf.kind == "Text")
    assert(title_leaf.value.content.kind == "ConstString")
    assert(title_leaf.value.content.v == "Inspector")

    print("  test 15 (widget bind elaboration): ok")
end

---------------------------------------------------------------------------
-- Test 16: widget-local state expands into component state slots
---------------------------------------------------------------------------

do
    local meter = Decl.WidgetDef(
        "Meter",
        List(),
        List{ Decl.StateSlot("level", Decl.TNumber, Decl.NumLit(7)) },
        List(),
        List(),
        node(
            Decl.Stable("root"),
            no_vis(),
            Decl.Layout(
                Decl.Row,
                Decl.Fit(nil, nil),
                Decl.Fit(nil, nil),
                zero_padding(),
                Decl.StateRef("level"),
                Decl.AlignLeft,
                Decl.AlignTop),
            no_decor(),
            nil, nil, no_input(), nil, nil,
            List()))

    local comp = component(
        "widget_state_bind",
        List(),
        List(),
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil,
            child_list {
                Decl.WidgetChild(Decl.WidgetCall(Decl.Stable("m1"), "Meter", List(), List(), List(), nil)),
                Decl.WidgetChild(Decl.WidgetCall(Decl.Stable("m2"), "Meter", List(), List(), List(), nil)),
            }),
        List{ meter })

    local bound = bind.bind_component(comp)
    assert(#bound.state == 2)
    assert(bound.state[1].name == "m1/level")
    assert(bound.state[1].slot == 0)
    assert(bound.state[1].initial.kind == "ConstNumber")
    assert(bound.state[1].initial.v == 7)
    assert(bound.state[2].name == "m2/level")
    assert(bound.state[2].slot == 1)
    assert(bound.root.children[1].layout.gap.kind == "StateSlotRef")
    assert(bound.root.children[1].layout.gap.slot == 0)
    assert(bound.root.children[2].layout.gap.kind == "StateSlotRef")
    assert(bound.root.children[2].layout.gap.slot == 1)

    print("  test 16 (widget local state): ok")
end

---------------------------------------------------------------------------
-- Test 17: widget prop types validate against component param types at bind
---------------------------------------------------------------------------

do
    local card = Decl.WidgetDef(
        "TypedCard",
        List{ Decl.WidgetProp("title", Decl.TString, nil) },
        List(),
        List{ Decl.WidgetSlot("children") },
        List(),
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil,
            Decl.Text(Decl.TextLeaf(Decl.WidgetPropRef("title"), text_style())),
            List()))

    local bad = component(
        "widget_type_bind",
        List{ Decl.Param("count", Decl.TNumber, nil) },
        List(),
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil,
            child_list {
                Decl.WidgetChild(Decl.WidgetCall(
                    Decl.Stable("card1"),
                    "TypedCard",
                    List{ Decl.PropArg("title", Decl.ParamRef("count")) },
                    List(),
                    List(),
                    nil))
            }),
        List{ card })

    local ok, err = pcall(function()
        bind.bind_component(bad)
    end)
    assert(not ok)
    assert(err:match("widget prop type mismatch"))

    print("  test 17 (widget prop type validation): ok")
end

----------------------------------------------------------------------------
-- Test 18: theme scopes and part style patches elaborate during bind
---------------------------------------------------------------------------

do
    local badge = Decl.WidgetDef(
        "Badge",
        List{ Decl.WidgetProp("text", Decl.TString, nil) },
        List(),
        List(),
        List{ Decl.WidgetPart("root"), Decl.WidgetPart("label") },
        Decl.Node(
            Decl.Stable("root"), "root", nil,
            no_vis(), fit_layout(),
            Decl.Decor(Decl.TokenRef("color.surface.panel"), nil, nil, nil),
            nil, nil, nil, nil, no_input(), nil, nil,
            child_list {
                Decl.Node(
                    Decl.Stable("label"), "label", nil,
                    no_vis(), fit_layout(), no_decor(),
                    nil, nil, nil, nil, no_input(), nil,
                    Decl.Text(Decl.TextLeaf(Decl.WidgetPropRef("text"), Decl.TextStyle(
                        Decl.TokenRef("color.text.primary"),
                        Decl.StringLit("default"),
                        Decl.NumLit(14),
                        Decl.NumLit(0),
                        Decl.NumLit(1.2),
                        Decl.WrapNone,
                        Decl.TextAlignLeft))),
                    List()),
            }))

    local comp = Decl.Component(
        "theme_bind",
        List(),
        List(),
        List{ Decl.ThemeDef("dark", nil, List{
            Decl.ThemeToken("color.surface.panel", Decl.TColor, Decl.ColorLit(0.1, 0.2, 0.3, 1)),
            Decl.ThemeToken("color.text.primary", Decl.TColor, Decl.ColorLit(0.9, 0.8, 0.7, 1)),
        }) },
        List{ badge },
        node(
            Decl.Stable("root"),
            no_vis(), fit_layout(), no_decor(),
            nil, nil, no_input(), nil, nil,
            child_list {
                Decl.WidgetChild(Decl.WidgetCall(
                        Decl.Stable("badge1"),
                        "Badge",
                        List{ Decl.PropArg("text", Decl.StringLit("Hello")) },
                        List{ Decl.PartStyleArg("root", Decl.StylePatch(
                            Decl.ColorLit(1, 0, 0, 1), nil, nil, nil,
                            nil, nil, nil, nil, nil, nil, nil, nil)) },
                        List(),
                        Decl.ThemeScope("dark", List()))),
            }))

    local bound = bind.bind_component(comp)
    assert(bound.root.children[1].decor.background.kind == "ConstColor")
    assert(bound.root.children[1].decor.background.r == 1)
    assert(bound.root.children[1].children[1].leaf.value.style.color.kind == "ConstColor")
    assert(bound.root.children[1].children[1].leaf.value.style.color.r == 0.9)

    print("  test 18 (theme scopes + part style patches): ok")
end

---------------------------------------------------------------------------
print("bind test passed")
