-- lib/compile.t
-- Plan -> Kernel phase transition
--
-- Installs compile methods on Plan ASDL types.
-- Provides CompileCtx and compile_component() convenience.
--
-- v1 scope: layout generation + binding compilation.
-- Stubs for command emission, hit testing, input handling.

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound
local Plan = TerraUI.types.Plan
local Kernel = TerraUI.types.Kernel

---------------------------------------------------------------------------
-- Shared runtime types
---------------------------------------------------------------------------

struct Color    { r: float; g: float; b: float; a: float }
struct Vec2     { x: float; y: float }
struct NodeRect { x: float; y: float; w: float; h: float }

struct InputState  { mouse_x: float; mouse_y: float; mouse_down: bool }
struct HitState    { hot: int32; active: int32; focus: int32 }
struct ClipState   { count: int32 }
struct ScrollState { _pad: uint8 }
struct StubCmd     { seq: int32 }

local function vtype_to_terra(vt)
    if     vt == Decl.TBool   then return bool
    elseif vt == Decl.TNumber then return float
    elseif vt == Decl.TString then return rawstring
    elseif vt == Decl.TColor  then return Color
    elseif vt == Decl.TImage  then return rawstring
    elseif vt == Decl.TVec2   then return Vec2
    elseif vt == Decl.TAny    then return &opaque
    else error("unknown ValueType") end
end

---------------------------------------------------------------------------
-- CompileCtx
---------------------------------------------------------------------------

local CompileCtx = {}
CompileCtx.__index = CompileCtx

function CompileCtx.new(plan_component)
    local pc  = plan_component
    local key = pc.key

    local params_t = terralib.types.newstruct("Params")
    for _, p in ipairs(key.params) do
        params_t.entries:insert(
            {field = "p"..p.slot, type = vtype_to_terra(p.ty)})
    end
    if #key.params == 0 then
        params_t.entries:insert({field = "_pad", type = uint8})
    end

    local state_t = terralib.types.newstruct("State")
    for _, s in ipairs(key.state) do
        state_t.entries:insert(
            {field = "s"..s.slot, type = vtype_to_terra(s.ty)})
    end
    if #key.state == 0 then
        state_t.entries:insert({field = "_pad", type = uint8})
    end

    local node_count = #pc.nodes

    local frame_t = terralib.types.newstruct("Frame")
    frame_t.entries:insert({field = "params",     type = params_t})
    frame_t.entries:insert({field = "state",      type = state_t})
    frame_t.entries:insert({field = "nodes",      type = NodeRect[node_count]})
    frame_t.entries:insert({field = "viewport_w", type = float})
    frame_t.entries:insert({field = "viewport_h", type = float})
    frame_t.entries:insert({field = "draw_seq",   type = int32})

    local frame_sym = symbol(&frame_t, "frame")

    return setmetatable({
        plan       = pc,
        params_t   = params_t,
        state_t    = state_t,
        frame_t    = frame_t,
        node_count = node_count,
        frame_sym  = frame_sym,
    }, CompileCtx)
end

---------------------------------------------------------------------------
-- Binding: compile_number  (-> float quote)
---------------------------------------------------------------------------

function Plan.Binding:compile_number(ctx)
    error("compile_number: unhandled " .. tostring(self.kind))
end

function Plan.ConstNumber:compile_number(ctx)
    local v = self.v;  return `[float](v)
end

function Plan.ConstBool:compile_number(ctx)
    if self.v then return `1.0f else return `0.0f end
end

function Plan.ConstString:compile_number(ctx) return `0.0f end
function Plan.ConstColor:compile_number(ctx)  return `0.0f end
function Plan.ConstVec2:compile_number(ctx)   return `0.0f end

function Plan.Param:compile_number(ctx)
    local frame = ctx.frame_sym
    local f = "p" .. self.slot
    return `[frame].params.[f]
end

function Plan.State:compile_number(ctx)
    local frame = ctx.frame_sym
    local f = "s" .. self.slot
    return `[frame].state.[f]
end

function Plan.Env:compile_number(ctx)
    error("env binding not yet supported: " .. self.name)
end

function Plan.Expr:compile_number(ctx)
    local a = {}
    for i, arg in ipairs(self.args) do
        a[i] = arg:compile_number(ctx)
    end
    local op = self.op
    if     op == "+"  then return `[a[1]] + [a[2]]
    elseif op == "-"  then
        if #a == 1 then return `-[a[1]]
        else return `[a[1]] - [a[2]] end
    elseif op == "*"  then return `[a[1]] * [a[2]]
    elseif op == "/"  then return `[a[1]] / [a[2]]
    elseif op == "select" then
        return `terralib.select([a[1]] ~= 0.0f, [a[2]], [a[3]])
    else error("unknown op for number: " .. op) end
end

---------------------------------------------------------------------------
-- Binding: compile_bool  (-> bool quote)
---------------------------------------------------------------------------

function Plan.Binding:compile_bool(ctx)
    error("compile_bool: unhandled " .. tostring(self.kind))
end

function Plan.ConstBool:compile_bool(ctx)
    local v = self.v;  return `v
end

function Plan.ConstNumber:compile_bool(ctx)
    local v = self.v;  return `[v] ~= 0.0f
end

function Plan.Param:compile_bool(ctx)
    local frame = ctx.frame_sym
    local f = "p" .. self.slot
    return `[frame].params.[f]
end

function Plan.State:compile_bool(ctx)
    local frame = ctx.frame_sym
    local f = "s" .. self.slot
    return `[frame].state.[f]
end

function Plan.Expr:compile_bool(ctx)
    local num = self:compile_number(ctx)
    return `[num] ~= 0.0f
end

---------------------------------------------------------------------------
-- Binding: compile_color  (-> Color quote)
---------------------------------------------------------------------------

function Plan.Binding:compile_color(ctx)
    error("compile_color: unhandled " .. tostring(self.kind))
end

function Plan.ConstColor:compile_color(ctx)
    local r, g, b, a2 = self.r, self.g, self.b, self.a
    return `Color { [float](r), [float](g), [float](b), [float](a2) }
end

---------------------------------------------------------------------------
-- Binding: compile_string  (-> rawstring quote)
---------------------------------------------------------------------------

function Plan.Binding:compile_string(ctx)
    error("compile_string: unhandled " .. tostring(self.kind))
end

function Plan.ConstString:compile_string(ctx)
    local v = self.v;  return `v
end

function Plan.Param:compile_string(ctx)
    local frame = ctx.frame_sym
    local f = "p" .. self.slot
    return `[frame].params.[f]
end

---------------------------------------------------------------------------
-- Binding: compile_vec2  (-> Vec2 quote)
---------------------------------------------------------------------------

function Plan.Binding:compile_vec2(ctx)
    error("compile_vec2: unhandled " .. tostring(self.kind))
end

function Plan.ConstVec2:compile_vec2(ctx)
    local x, y = self.x, self.y
    return `Vec2 { [float](x), [float](y) }
end

---------------------------------------------------------------------------
-- Size rule helpers
---------------------------------------------------------------------------

local function resolve_size(rule, available, ctx)
    if rule.kind == "Fixed" then
        return rule.value:compile_number(ctx)
    elseif rule.kind == "Grow" then
        local r = available
        if rule.min then
            local mn = rule.min:compile_number(ctx)
            r = `terralib.select([r] < [mn], [mn], [r])
        end
        if rule.max then
            local mx = rule.max:compile_number(ctx)
            r = `terralib.select([r] > [mx], [mx], [r])
        end
        return r
    elseif rule.kind == "Percent" then
        local frac = rule.value:compile_number(ctx)
        return `[available] * [frac]
    elseif rule.kind == "Fit" then
        -- v1: use available, clamped by min/max
        local r = available
        if rule.min then
            local mn = rule.min:compile_number(ctx)
            r = `terralib.select([r] < [mn], [mn], [r])
        end
        if rule.max then
            local mx = rule.max:compile_number(ctx)
            r = `terralib.select([r] > [mx], [mx], [r])
        end
        return r
    end
    error("unknown SizeRule: " .. tostring(rule.kind))
end

---------------------------------------------------------------------------
-- Layout code generation
---------------------------------------------------------------------------

function CompileCtx:emit_children_placement(parent)
    local frame = self.frame_sym
    local pi    = parent.index
    local plan  = self.plan
    local stmts = terralib.newlist()

    local pad_l = parent.padding_left:compile_number(self)
    local pad_t = parent.padding_top:compile_number(self)
    local pad_r = parent.padding_right:compile_number(self)
    local pad_b = parent.padding_bottom:compile_number(self)
    local gap_v = parent.gap:compile_number(self)

    local is_row = (parent.axis == Decl.Row)

    -- content area symbols
    local cx = symbol(float, "cx"..pi)
    local cy = symbol(float, "cy"..pi)
    local cw = symbol(float, "cw"..pi)
    local ch = symbol(float, "ch"..pi)

    stmts:insert(quote
        var [cx] = [frame].nodes[pi].x + [pad_l]
        var [cy] = [frame].nodes[pi].y + [pad_t]
        var [cw] = [frame].nodes[pi].w - [pad_l] - [pad_r]
        var [ch] = [frame].nodes[pi].h - [pad_t] - [pad_b]
    end)

    -- collect direct children (skip subtrees in preorder)
    local children = {}
    local ci = parent.first_child
    for c = 1, parent.child_count do
        local child = plan.nodes[ci + 1]   -- 1-indexed List
        children[#children + 1] = child
        ci = child.subtree_end             -- jump past subtree
    end

    local avail_main  = is_row and cw or ch
    local avail_cross = is_row and ch or cw

    -- classify children by main-axis sizing
    local grow_count = 0
    for _, child in ipairs(children) do
        local rule = is_row and child.width or child.height
        if rule.kind == "Grow" or rule.kind == "Fit" then
            grow_count = grow_count + 1
        end
    end

    -- per-child main size symbols, accumulate fixed total
    local total_fixed = symbol(float, "tf"..pi)
    stmts:insert(quote var [total_fixed] = 0.0f end)

    local child_main = {}
    for idx, child in ipairs(children) do
        local rule = is_row and child.width or child.height
        local sym  = symbol(float, "cm"..child.index)
        child_main[idx] = sym

        if rule.kind == "Fixed" then
            local val = rule.value:compile_number(self)
            stmts:insert(quote
                var [sym] = [val]
                [total_fixed] = [total_fixed] + [sym]
            end)
        elseif rule.kind == "Percent" then
            local frac = rule.value:compile_number(self)
            stmts:insert(quote
                var [sym] = [avail_main] * [frac]
                [total_fixed] = [total_fixed] + [sym]
            end)
        else
            stmts:insert(quote var [sym] = 0.0f end)
        end
    end

    -- remaining for Grow/Fit children
    if grow_count > 0 then
        local gap_count = parent.child_count - 1
        local rem = symbol(float, "rem"..pi)
        local ge  = symbol(float, "ge"..pi)

        stmts:insert(quote
            var [rem] = [avail_main] - [total_fixed]
                        - [gap_v] * [float](gap_count)
            if [rem] < 0 then [rem] = 0 end
            var [ge] = [rem] / [float](grow_count)
        end)

        for idx, child in ipairs(children) do
            local rule = is_row and child.width or child.height
            if rule.kind == "Grow" then
                local r = `[ge]
                if rule.min then
                    local mn = rule.min:compile_number(self)
                    r = `terralib.select([r] < [mn], [mn], [r])
                end
                if rule.max then
                    local mx = rule.max:compile_number(self)
                    r = `terralib.select([r] > [mx], [mx], [r])
                end
                stmts:insert(quote [child_main[idx]] = [r] end)
            elseif rule.kind == "Fit" then
                -- v1: give equal share
                stmts:insert(quote [child_main[idx]] = [ge] end)
            end
        end
    end

    -- place children along axis
    local cur = symbol(float, "cur"..pi)
    stmts:insert(quote var [cur] = [is_row and cx or cy] end)

    for idx, child in ipairs(children) do
        local ci       = child.index
        local main_sz  = child_main[idx]
        local cross_rule = is_row and child.height or child.width
        local cross_sz = resolve_size(cross_rule, avail_cross, self)

        if is_row then
            stmts:insert(quote
                [frame].nodes[ci].x = [cur]
                [frame].nodes[ci].y = [cy]
                [frame].nodes[ci].w = [main_sz]
                [frame].nodes[ci].h = [cross_sz]
            end)
        else
            stmts:insert(quote
                [frame].nodes[ci].x = [cx]
                [frame].nodes[ci].y = [cur]
                [frame].nodes[ci].w = [cross_sz]
                [frame].nodes[ci].h = [main_sz]
            end)
        end

        stmts:insert(quote
            [cur] = [cur] + [main_sz] + [gap_v]
        end)
    end

    return stmts
end

function CompileCtx:compile_layout_fn()
    local frame = self.frame_sym
    local plan  = self.plan
    local nodes = plan.nodes
    local stmts = terralib.newlist()

    for _, node in ipairs(nodes) do
        -- root: fill viewport (resolved by size rule)
        if node.parent == nil then
            local i = node.index
            local w = resolve_size(node.width,  `[frame].viewport_w, self)
            local h = resolve_size(node.height, `[frame].viewport_h, self)
            stmts:insert(quote
                [frame].nodes[i].x = 0
                [frame].nodes[i].y = 0
                [frame].nodes[i].w = [w]
                [frame].nodes[i].h = [h]
            end)
        end
        -- non-root: already placed by parent
        if node.child_count > 0 then
            stmts:insertall(self:emit_children_placement(node))
        end
    end

    return terra([frame])
        escape for _, s in ipairs(stmts) do emit(s) end end
    end
end

---------------------------------------------------------------------------
-- Component:compile
---------------------------------------------------------------------------

function Plan.Component:compile(ctx)
    local layout_fn = ctx:compile_layout_fn()
    local noop_fn   = terra(frame: &ctx.frame_t) end

    local runtime_types = Kernel.RuntimeTypes(
        ctx.params_t, ctx.state_t, ctx.frame_t,
        InputState, NodeRect, ClipState, ScrollState, HitState)

    local kernels = Kernel.Kernels(
        `noop_fn, `layout_fn, `noop_fn, `noop_fn, `noop_fn)

    local stub_q = `noop_fn
    return Kernel.Component(
        self.key,
        runtime_types,
        Kernel.RectStream(StubCmd, stub_q),
        Kernel.BorderStream(StubCmd, stub_q),
        Kernel.TextStream(StubCmd, stub_q, stub_q),
        Kernel.ImageStream(StubCmd, stub_q),
        Kernel.ScissorStream(StubCmd, stub_q),
        Kernel.CustomStream(StubCmd, stub_q),
        kernels)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local M = {}

M.CompileCtx = CompileCtx
M.Color      = Color
M.Vec2       = Vec2
M.NodeRect   = NodeRect

function M.compile_component(plan_component)
    local ctx = CompileCtx.new(plan_component)
    return plan_component:compile(ctx)
end

return M
