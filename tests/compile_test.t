-- tests/compile_test.t
-- Tests: Plan -> Kernel phase transition via lib/compile.t

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")

local Decl = TerraUI.types.Decl
local Kernel = TerraUI.types.Kernel

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
local function make_node(name, axis, w, h, pad, gap, children)
    return Decl.Node(
        Decl.Stable(name), no_vis(),
        Decl.Layout(axis, w, h, pad or zero_padding(),
            gap or zero, Decl.AlignLeft, Decl.AlignTop),
        no_decor(), nil, nil, no_input(), nil, nil,
        children or List())
end

local function full_pipeline(decl_comp)
    local b = bind.bind_component(decl_comp)
    local p = plan.plan_component(b)
    return compile.compile_component(p)
end

---------------------------------------------------------------------------
-- Test 1: types are generated
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "types_test",
        List{ Decl.Param("x", Decl.TNumber, nil) },
        List{ Decl.StateSlot("y", Decl.TNumber, nil) },
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil))))

    assert(terralib.types.istype(k.types.params_t))
    assert(terralib.types.istype(k.types.state_t))
    assert(terralib.types.istype(k.types.frame_t))
    assert(terralib.types.istype(k.types.node_t))
    assert(terralib.types.istype(k.types.input_t))
    assert(terralib.types.istype(k.types.hit_t))
    assert(k:frame_type() == k.types.frame_t)
    assert(terralib.isquote(k:run_quote()))

    print("  test 1 (types generated): ok")
end

---------------------------------------------------------------------------
-- Test 2: column with two fixed-height children
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "col_fixed", List(), List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(30))),
                make_node("b", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(50))),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)

        -- root fills viewport
        if f.nodes[0].x ~= 0 or f.nodes[0].y ~= 0 then return 1 end
        if f.nodes[0].w ~= 800 or f.nodes[0].h ~= 600 then return 2 end

        -- child a: y=0, h=30, w=800
        if f.nodes[1].y ~= 0 then return 3 end
        if f.nodes[1].h ~= 30 then return 4 end
        if f.nodes[1].w ~= 800 then return 5 end

        -- child b: y=30, h=50, w=800
        if f.nodes[2].y ~= 30 then return 6 end
        if f.nodes[2].h ~= 50 then return 7 end
        if f.nodes[2].w ~= 800 then return 8 end

        return 0
    end

    local result = test()
    assert(result == 0, "test 2 failed at check " .. tostring(result))
    print("  test 2 (column fixed children): ok")
end

---------------------------------------------------------------------------
-- Test 3: column with gap
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "col_gap", List(), List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, Decl.NumLit(10),
            List{
                make_node("a", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(30))),
                make_node("b", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(50))),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- b starts at y = 30 + 10(gap) = 40
        if f.nodes[2].y ~= 40 then return 1 end
        return 0
    end

    assert(test() == 0, "test 3 failed")
    print("  test 3 (column gap): ok")
end

---------------------------------------------------------------------------
-- Test 4: row layout
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "row_test", List(), List(),
        make_node("root", Decl.Row,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Column,
                    Decl.Fixed(Decl.NumLit(200)), Decl.Grow(nil, nil)),
                make_node("b", Decl.Column,
                    Decl.Fixed(Decl.NumLit(300)), Decl.Grow(nil, nil)),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- a: x=0, w=200, h=600
        if f.nodes[1].x ~= 0   then return 1 end
        if f.nodes[1].w ~= 200  then return 2 end
        if f.nodes[1].h ~= 600  then return 3 end
        -- b: x=200, w=300, h=600
        if f.nodes[2].x ~= 200  then return 4 end
        if f.nodes[2].w ~= 300  then return 5 end
        return 0
    end

    assert(test() == 0, "test 4 failed at " .. tostring(test()))
    print("  test 4 (row layout): ok")
end

---------------------------------------------------------------------------
-- Test 5: grow distribution
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "grow_test", List(), List(),
        make_node("root", Decl.Row,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Column,
                    Decl.Fixed(Decl.NumLit(100)), Decl.Grow(nil, nil)),
                make_node("b", Decl.Column,
                    Decl.Grow(nil, nil), Decl.Grow(nil, nil)),
                make_node("c", Decl.Column,
                    Decl.Grow(nil, nil), Decl.Grow(nil, nil)),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- a: fixed 100
        if f.nodes[1].w ~= 100 then return 1 end
        -- remaining 700 split between b and c: 350 each
        if f.nodes[2].w ~= 350 then return 2 end
        if f.nodes[3].w ~= 350 then return 3 end
        -- b starts at x=100
        if f.nodes[2].x ~= 100 then return 4 end
        -- c starts at x=450
        if f.nodes[3].x ~= 450 then return 5 end
        return 0
    end

    assert(test() == 0, "test 5 failed at " .. tostring(test()))
    print("  test 5 (grow distribution): ok")
end

---------------------------------------------------------------------------
-- Test 6: padding
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "pad_test", List(), List(),
        Decl.Node(
            Decl.Stable("root"), no_vis(),
            Decl.Layout(Decl.Column,
                Decl.Grow(nil, nil), Decl.Grow(nil, nil),
                Decl.Padding(
                    Decl.NumLit(10), Decl.NumLit(20),
                    Decl.NumLit(10), Decl.NumLit(20)),
                zero, Decl.AlignLeft, Decl.AlignTop),
            no_decor(), nil, nil, no_input(), nil, nil,
            List{
                make_node("a", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(40))),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- child a: x=10(pad_l), y=20(pad_t), w=800-10-10=780
        if f.nodes[1].x ~= 10  then return 1 end
        if f.nodes[1].y ~= 20  then return 2 end
        if f.nodes[1].w ~= 780 then return 3 end
        if f.nodes[1].h ~= 40  then return 4 end
        return 0
    end

    assert(test() == 0, "test 6 failed at " .. tostring(test()))
    print("  test 6 (padding): ok")
end

---------------------------------------------------------------------------
-- Test 7: param-driven sizing
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "param_test",
        List{ Decl.Param("h", Decl.TNumber, nil) },
        List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Row,
                    Decl.Grow(nil, nil),
                    Decl.Fixed(Decl.ParamRef("h"))),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        f.params.p0 = 42
        [layout_q](&f)
        if f.nodes[1].h ~= 42 then return 1 end
        return 0
    end

    assert(test() == 0, "test 7 failed")
    print("  test 7 (param-driven sizing): ok")
end

---------------------------------------------------------------------------
-- Test 8: percent sizing
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "pct_test", List(), List(),
        make_node("root", Decl.Row,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Column,
                    Decl.Percent(Decl.NumLit(0.25)),
                    Decl.Grow(nil, nil)),
                make_node("b", Decl.Column,
                    Decl.Grow(nil, nil),
                    Decl.Grow(nil, nil)),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- a: 25% of 800 = 200
        if f.nodes[1].w ~= 200 then return 1 end
        -- b: 800 - 200 = 600
        if f.nodes[2].w ~= 600 then return 2 end
        if f.nodes[2].x ~= 200 then return 3 end
        return 0
    end

    assert(test() == 0, "test 8 failed at " .. tostring(test()))
    print("  test 8 (percent sizing): ok")
end

---------------------------------------------------------------------------
-- Test 9: nested layout
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "nested", List(), List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("top", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Fixed(Decl.NumLit(100)),
                    nil, nil,
                    List{
                        make_node("tl", Decl.Column,
                            Decl.Fixed(Decl.NumLit(200)),
                            Decl.Grow(nil, nil)),
                        make_node("tr", Decl.Column,
                            Decl.Grow(nil, nil),
                            Decl.Grow(nil, nil)),
                    }),
                make_node("bottom", Decl.Row,
                    Decl.Grow(nil, nil), Decl.Grow(nil, nil)),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        [layout_q](&f)
        -- root: 800x600
        -- top: y=0, h=100, w=800
        -- bottom: y=100, h=grow(500), w=800
        if f.nodes[1].h ~= 100 then return 1 end
        if f.nodes[4].y ~= 100 then return 2 end
        if f.nodes[4].h ~= 500 then return 3 end
        -- tl: x=0, w=200, h=100
        if f.nodes[2].w ~= 200 then return 4 end
        if f.nodes[2].h ~= 100 then return 5 end
        -- tr: x=200, w=600, h=100
        if f.nodes[3].x ~= 200 then return 6 end
        if f.nodes[3].w ~= 600 then return 7 end
        return 0
    end

    assert(test() == 0, "test 9 failed at " .. tostring(test()))
    print("  test 9 (nested layout): ok")
end

---------------------------------------------------------------------------
-- Test 10: expr binding (addition)
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "expr_test",
        List{ Decl.Param("base", Decl.TNumber, nil) },
        List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil),
            nil, nil,
            List{
                make_node("a", Decl.Row,
                    Decl.Grow(nil, nil),
                    Decl.Fixed(
                        Decl.Binary("+",
                            Decl.ParamRef("base"),
                            Decl.NumLit(10)))),
            })))

    local Frame = k.types.frame_t
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 800; f.viewport_h = 600
        f.params.p0 = 20
        [layout_q](&f)
        -- height = base(20) + 10 = 30
        if f.nodes[1].h ~= 30 then return 1 end
        return 0
    end

    assert(test() == 0, "test 10 failed")
    print("  test 10 (expr binding): ok")
end

---------------------------------------------------------------------------
-- Test 11: expanded frame/node runtime fields are initialized
---------------------------------------------------------------------------

do
    local k = full_pipeline(Decl.Component(
        "runtime_fields", List(), List(),
        make_node("root", Decl.Column,
            Decl.Grow(nil, nil), Decl.Grow(nil, nil))))

    local Frame = k:frame_type()
    local layout_q = k.kernels.layout_fn

    local test = terra()
        var f : Frame
        f.viewport_w = 320; f.viewport_h = 200
        [layout_q](&f)

        if f.action_node ~= -1 then return 1 end
        if f.hit.hot ~= -1 then return 2 end
        if f.hit.active ~= -1 then return 3 end
        if f.hit.focus ~= -1 then return 4 end

        if f.nodes[0].content_w ~= 320 then return 5 end
        if f.nodes[0].content_h ~= 200 then return 6 end
        if f.nodes[0].clip_x1 ~= 320 then return 7 end
        if f.nodes[0].clip_y1 ~= 200 then return 8 end
        if f.nodes[0].visible ~= true then return 9 end
        if f.nodes[0].enabled ~= true then return 10 end

        return 0
    end

    assert(test() == 0, "test 11 failed at " .. tostring(test()))
    print("  test 11 (runtime fields): ok")
end

---------------------------------------------------------------------------
print("compile test passed")
