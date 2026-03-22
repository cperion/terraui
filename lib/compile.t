-- lib/compile.t
-- Plan -> Kernel phase transition
--
-- Installs compile methods on Plan / Kernel ASDL types.
-- Provides CompileCtx and compile_component() convenience.
--
-- Current scope:
--   * runtime type synthesis
--   * binding compilation
--   * basic row/column layout code generation
--   * contract-aligned compile method surface with stubs for later passes

local TerraUI = require("lib/terraui_schema")
local Decl = TerraUI.types.Decl
local Plan = TerraUI.types.Plan
local Kernel = TerraUI.types.Kernel
local C = terralib.includecstring [[
    #include <string.h>
]]

---------------------------------------------------------------------------
-- Shared runtime types
---------------------------------------------------------------------------

struct Color { r: float; g: float; b: float; a: float }
struct Vec2  { x: float; y: float }

struct NodeState {
    x: float; y: float; w: float; h: float

    content_x: float; content_y: float
    content_w: float; content_h: float

    want_w: float; want_h: float

    clip_x0: float; clip_y0: float
    clip_x1: float; clip_y1: float

    visible: bool
    enabled: bool
}

struct InputState {
    mouse_x: float; mouse_y: float
    mouse_down: bool
    mouse_pressed: bool
    mouse_released: bool
    wheel_dx: float; wheel_dy: float
}

struct HitState {
    hot: int32
    active: int32
    focus: int32
}

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
        params_t.entries:insert({
            field = "p" .. p.slot,
            type = vtype_to_terra(p.ty),
        })
    end
    if #key.params == 0 then
        params_t.entries:insert({ field = "_pad", type = uint8 })
    end

    local state_t = terralib.types.newstruct("State")
    for _, s in ipairs(key.state) do
        state_t.entries:insert({
            field = "s" .. s.slot,
            type = vtype_to_terra(s.ty),
        })
    end
    if #key.state == 0 then
        state_t.entries:insert({ field = "_pad", type = uint8 })
    end

    local node_t         = NodeState
    local input_t        = InputState
    local hit_t          = HitState
    local clip_state_t   = ClipState
    local scroll_state_t = ScrollState
    local node_count     = #pc.nodes

    local frame_t = terralib.types.newstruct("Frame")
    frame_t.entries:insert({ field = "params",      type = params_t })
    frame_t.entries:insert({ field = "state",       type = state_t })
    frame_t.entries:insert({ field = "nodes",       type = node_t[node_count] })
    frame_t.entries:insert({ field = "input",       type = input_t })
    frame_t.entries:insert({ field = "hit",         type = hit_t })
    frame_t.entries:insert({ field = "viewport_w",  type = float })
    frame_t.entries:insert({ field = "viewport_h",  type = float })
    frame_t.entries:insert({ field = "draw_seq",    type = uint32 })
    frame_t.entries:insert({ field = "action_node", type = int32 })
    frame_t.entries:insert({ field = "action_name", type = rawstring })
    frame_t.entries:insert({ field = "cursor_name", type = rawstring })

    local frame_sym = symbol(&frame_t, "frame")

    return setmetatable({
        plan            = pc,
        params_t        = params_t,
        state_t         = state_t,
        node_t          = node_t,
        input_t         = input_t,
        hit_t           = hit_t,
        clip_state_t    = clip_state_t,
        scroll_state_t  = scroll_state_t,
        frame_t         = frame_t,
        node_count      = node_count,
        frame_sym       = frame_sym,
    }, CompileCtx)
end

---------------------------------------------------------------------------
-- Binding compilation
---------------------------------------------------------------------------

function Plan.Binding:compile_number(ctx)
    error("compile_number: unhandled " .. tostring(self.kind))
end

function Plan.ConstNumber:compile_number(ctx)
    local v = self.v
    return `[float](v)
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
    if     op == "+" then
        return `[a[1]] + [a[2]]
    elseif op == "-" then
        if #a == 1 then return `-[a[1]]
        else return `[a[1]] - [a[2]] end
    elseif op == "*" then
        return `[a[1]] * [a[2]]
    elseif op == "/" then
        return `[a[1]] / [a[2]]
    elseif op == "select" then
        return `terralib.select([a[1]] ~= 0.0f, [a[2]], [a[3]])
    else
        error("unknown op for number: " .. op)
    end
end

function Plan.Binding:compile_bool(ctx)
    error("compile_bool: unhandled " .. tostring(self.kind))
end

function Plan.ConstBool:compile_bool(ctx)
    local v = self.v
    return `v
end

function Plan.ConstNumber:compile_bool(ctx)
    local v = self.v
    return `[v] ~= 0.0f
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

function Plan.Binding:compile_color(ctx)
    error("compile_color: unhandled " .. tostring(self.kind))
end

function Plan.ConstColor:compile_color(ctx)
    local r, g, b, a = self.r, self.g, self.b, self.a
    return `Color { [float](r), [float](g), [float](b), [float](a) }
end

function Plan.Binding:compile_string(ctx)
    error("compile_string: unhandled " .. tostring(self.kind))
end

function Plan.ConstString:compile_string(ctx)
    local v = self.v
    return `v
end

function Plan.Param:compile_string(ctx)
    local frame = ctx.frame_sym
    local f = "p" .. self.slot
    return `[frame].params.[f]
end

function Plan.Binding:compile_vec2(ctx)
    error("compile_vec2: unhandled " .. tostring(self.kind))
end

function Plan.ConstVec2:compile_vec2(ctx)
    local x, y = self.x, self.y
    return `Vec2 { [float](x), [float](y) }
end

---------------------------------------------------------------------------
-- Size rule helpers / methods
---------------------------------------------------------------------------

local function resolve_size(rule, available, intrinsic, ctx)
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
        local r = intrinsic
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

local function apply_aspect_ratio(node, width_q, height_q, ctx)
    if not node.aspect_ratio then
        return width_q, height_q
    end

    local ratio = node.aspect_ratio:compile_number(ctx)
    local width_drives = (node.width.kind ~= "Grow") and (node.height.kind == "Grow" or node.height.kind == "Fit")
    local height_drives = (node.height.kind ~= "Grow") and (node.width.kind == "Grow" or node.width.kind == "Fit")

    if width_drives and not height_drives then
        return width_q, `[width_q] / [ratio]
    elseif height_drives and not width_drives then
        return `[height_q] * [ratio], height_q
    end

    return width_q, height_q
end

function Plan.SizeRule:compile_axis(ctx, axis_name)
    error("compile_axis not implemented for " .. tostring(self.kind))
end

function Plan.Fit:compile_axis(ctx, axis_name)
    return resolve_size(self, axis_name, `0.0f, ctx)
end

function Plan.Grow:compile_axis(ctx, axis_name)
    return resolve_size(self, axis_name, `0.0f, ctx)
end

function Plan.Fixed:compile_axis(ctx, axis_name)
    return resolve_size(self, axis_name, `0.0f, ctx)
end

function Plan.Percent:compile_axis(ctx, axis_name)
    return resolve_size(self, axis_name, `0.0f, ctx)
end

---------------------------------------------------------------------------
-- Planned-node layout helpers
---------------------------------------------------------------------------

function CompileCtx:direct_children(parent)
    local children = {}
    if not parent.first_child or parent.child_count == 0 then
        return children
    end
    local ci = parent.first_child
    for _ = 1, parent.child_count do
        local child = self.plan.nodes[ci + 1]
        children[#children + 1] = child
        ci = child.subtree_end
    end
    return children
end

function CompileCtx:flow_children(parent)
    local all = self:direct_children(parent)
    local out = {}
    for _, child in ipairs(all) do
        if not child.float_slot then
            out[#out + 1] = child
        end
    end
    return out
end

function CompileCtx:emit_node_measure(node)
    local frame = self.frame_sym
    local i = node.index
    local stmts = terralib.newlist()

    local pad_l = node.padding_left:compile_number(self)
    local pad_t = node.padding_top:compile_number(self)
    local pad_r = node.padding_right:compile_number(self)
    local pad_b = node.padding_bottom:compile_number(self)
    local gap_v = node.gap:compile_number(self)

    local leaf_w = `0.0f
    local leaf_h = `0.0f

    if node.text_slot then
        local ts = self.plan.texts[node.text_slot + 1]
        leaf_w = ts:compile_measure(self, Plan.MeasureWidth)
        leaf_h = ts:compile_measure(self, Plan.MeasureHeight)
    end

    local children = self:flow_children(node)
    local child_w = symbol(float, "want_child_w" .. i)
    local child_h = symbol(float, "want_child_h" .. i)

    stmts:insert(quote
        var [child_w] = 0.0f
        var [child_h] = 0.0f
        [frame].nodes[i].visible = true
        [frame].nodes[i].enabled = true
    end)

    local child_count = #children
    if child_count > 0 then
        if node.axis == Decl.Row then
            if child_count > 1 then
                stmts:insert(quote [child_w] = [gap_v] * [float](child_count - 1) end)
            end
            for _, child in ipairs(children) do
                local ci = child.index
                stmts:insert(quote
                    [child_w] = [child_w] + [frame].nodes[ci].want_w
                    [child_h] = terralib.select([child_h] > [frame].nodes[ci].want_h,
                                                [child_h],
                                                [frame].nodes[ci].want_h)
                end)
            end
        else
            if child_count > 1 then
                stmts:insert(quote [child_h] = [gap_v] * [float](child_count - 1) end)
            end
            for _, child in ipairs(children) do
                local ci = child.index
                stmts:insert(quote
                    [child_h] = [child_h] + [frame].nodes[ci].want_h
                    [child_w] = terralib.select([child_w] > [frame].nodes[ci].want_w,
                                                [child_w],
                                                [frame].nodes[ci].want_w)
                end)
            end
        end
    end

    stmts:insert(quote
        [frame].nodes[i].want_w = terralib.select([leaf_w] > [child_w], [leaf_w], [child_w]) + [pad_l] + [pad_r]
        [frame].nodes[i].want_h = terralib.select([leaf_h] > [child_h], [leaf_h], [child_h]) + [pad_t] + [pad_b]
    end)

    return quote [stmts] end
end

function CompileCtx:emit_node_content_box(node)
    local frame = self.frame_sym
    local i = node.index
    local pad_l = node.padding_left:compile_number(self)
    local pad_t = node.padding_top:compile_number(self)
    local pad_r = node.padding_right:compile_number(self)
    local pad_b = node.padding_bottom:compile_number(self)

    return quote
        [frame].nodes[i].content_x = [frame].nodes[i].x + [pad_l]
        [frame].nodes[i].content_y = [frame].nodes[i].y + [pad_t]
        [frame].nodes[i].content_w = [frame].nodes[i].w - [pad_l] - [pad_r]
        [frame].nodes[i].content_h = [frame].nodes[i].h - [pad_t] - [pad_b]
    end
end

function CompileCtx:emit_children_placement(parent)
    local frame = self.frame_sym
    local pi    = parent.index
    local plan  = self.plan
    local stmts = terralib.newlist()

    local gap_v = parent.gap:compile_number(self)
    local is_row = (parent.axis == Decl.Row)

    local cx = symbol(float, "cx" .. pi)
    local cy = symbol(float, "cy" .. pi)
    local cw = symbol(float, "cw" .. pi)
    local ch = symbol(float, "ch" .. pi)

    stmts:insert(quote
        var [cx] = [frame].nodes[pi].content_x
        var [cy] = [frame].nodes[pi].content_y
        var [cw] = [frame].nodes[pi].content_w
        var [ch] = [frame].nodes[pi].content_h
    end)

    local children = self:flow_children(parent)

    local avail_main  = is_row and cw or ch
    local avail_cross = is_row and ch or cw

    local grow_count = 0
    for _, child in ipairs(children) do
        local rule = is_row and child.width or child.height
        if rule.kind == "Grow" then
            grow_count = grow_count + 1
        end
    end

    local total_fixed = symbol(float, "tf" .. pi)
    stmts:insert(quote var [total_fixed] = 0.0f end)

    local child_main = {}
    for idx, child in ipairs(children) do
        local rule = is_row and child.width or child.height
        local sym  = symbol(float, "cm" .. child.index)
        child_main[idx] = sym

        if rule.kind == "Grow" then
            stmts:insert(quote var [sym] = 0.0f end)
        else
            local intrinsic_main
            if is_row then
                intrinsic_main = `[frame].nodes[child.index].want_w
            else
                intrinsic_main = `[frame].nodes[child.index].want_h
            end
            local val = resolve_size(rule, avail_main, intrinsic_main, self)
            stmts:insert(quote
                var [sym] = [val]
                [total_fixed] = [total_fixed] + [sym]
            end)
        end
    end

    if grow_count > 0 then
        local gap_count = parent.child_count - 1
        local rem = symbol(float, "rem" .. pi)
        local ge  = symbol(float, "ge" .. pi)

        stmts:insert(quote
            var [rem] = [avail_main] - [total_fixed] - [gap_v] * [float](gap_count)
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
            end
        end
    end

    local cur = symbol(float, "cur" .. pi)
    stmts:insert(quote var [cur] = [is_row and cx or cy] end)

    for idx, child in ipairs(children) do
        local ci_node = child.index
        local main_sz = child_main[idx]
        local cross_rule = is_row and child.height or child.width
        local intrinsic_cross
        if is_row then
            intrinsic_cross = `[frame].nodes[ci_node].want_h
        else
            intrinsic_cross = `[frame].nodes[ci_node].want_w
        end
        local cross_sz = resolve_size(cross_rule, avail_cross, intrinsic_cross, self)

        local child_w, child_h
        if is_row then
            child_w, child_h = apply_aspect_ratio(child, `[main_sz], cross_sz, self)
        else
            child_w, child_h = apply_aspect_ratio(child, cross_sz, `[main_sz], self)
        end

        local cross_pos
        if is_row then
            if parent.align_y == Decl.AlignCenterY then
                cross_pos = `[cy] + ([ch] - [child_h]) / 2.0f
            elseif parent.align_y == Decl.AlignBottom then
                cross_pos = `[cy] + ([ch] - [child_h])
            else
                cross_pos = `[cy]
            end
            stmts:insert(quote
                [frame].nodes[ci_node].x = [cur]
                [frame].nodes[ci_node].y = [cross_pos]
                [frame].nodes[ci_node].w = [child_w]
                [frame].nodes[ci_node].h = [child_h]
            end)
        else
            if parent.align_x == Decl.AlignCenterX then
                cross_pos = `[cx] + ([cw] - [child_w]) / 2.0f
            elseif parent.align_x == Decl.AlignRight then
                cross_pos = `[cx] + ([cw] - [child_w])
            else
                cross_pos = `[cx]
            end
            stmts:insert(quote
                [frame].nodes[ci_node].x = [cross_pos]
                [frame].nodes[ci_node].y = [cur]
                [frame].nodes[ci_node].w = [child_w]
                [frame].nodes[ci_node].h = [child_h]
            end)
        end

        stmts:insert(self:emit_node_content_box(child))
        stmts:insert(quote
            [frame].nodes[ci_node].clip_x0 = [frame].nodes[pi].clip_x0
            [frame].nodes[ci_node].clip_y0 = [frame].nodes[pi].clip_y0
            [frame].nodes[ci_node].clip_x1 = [frame].nodes[pi].clip_x1
            [frame].nodes[ci_node].clip_y1 = [frame].nodes[pi].clip_y1
        end)
        stmts:insert(quote [cur] = [cur] + [main_sz] + [gap_v] end)
    end

    return stmts
end

---------------------------------------------------------------------------
-- Plan compile methods
---------------------------------------------------------------------------

function Plan.Node:compile_layout(ctx)
    local frame = ctx.frame_sym
    local stmts = terralib.newlist()

    if self.parent == nil then
        local i = self.index
        local w0 = resolve_size(self.width, `[frame].viewport_w, `[frame].nodes[i].want_w, ctx)
        local h0 = resolve_size(self.height, `[frame].viewport_h, `[frame].nodes[i].want_h, ctx)
        local w, h = apply_aspect_ratio(self, w0, h0, ctx)
        stmts:insert(quote
            [frame].nodes[i].x = 0
            [frame].nodes[i].y = 0
            [frame].nodes[i].w = [w]
            [frame].nodes[i].h = [h]
            [frame].nodes[i].clip_x0 = 0
            [frame].nodes[i].clip_y0 = 0
            [frame].nodes[i].clip_x1 = [frame].viewport_w
            [frame].nodes[i].clip_y1 = [frame].viewport_h
        end)
        stmts:insert(ctx:emit_node_content_box(self))
    end

    if self.clip_slot then
        local clip = ctx.plan.clips[self.clip_slot + 1]
        stmts:insert(clip:compile_apply(ctx))
    end

    if self.child_count > 0 then
        stmts:insertall(ctx:emit_children_placement(self))
    end

    return quote [stmts] end
end

function Plan.Node:compile_hit(ctx)
    return quote end
end

function Plan.Paint:compile_emit(ctx, node_index)
    return quote end
end

function Plan.InputSpec:compile_input(ctx, node_index)
    return quote end
end

local function attach_point_xy(xq, yq, wq, hq, point)
    if point == Decl.AttachLeftTop then
        return xq, yq
    elseif point == Decl.AttachTopCenter then
        return `[xq] + [wq] / 2.0f, yq
    elseif point == Decl.AttachRightTop then
        return `[xq] + [wq], yq
    elseif point == Decl.AttachLeftCenter then
        return xq, `[yq] + [hq] / 2.0f
    elseif point == Decl.AttachCenter then
        return `[xq] + [wq] / 2.0f, `[yq] + [hq] / 2.0f
    elseif point == Decl.AttachRightCenter then
        return `[xq] + [wq], `[yq] + [hq] / 2.0f
    elseif point == Decl.AttachLeftBottom then
        return xq, `[yq] + [hq]
    elseif point == Decl.AttachBottomCenter then
        return `[xq] + [wq] / 2.0f, `[yq] + [hq]
    elseif point == Decl.AttachRightBottom then
        return `[xq] + [wq], `[yq] + [hq]
    end
    error("unknown attach point")
end

function Plan.ClipSpec:compile_apply(ctx)
    local frame = ctx.frame_sym
    local i = self.node_index
    local stmts = terralib.newlist()

    if self.horizontal then
        stmts:insert(quote
            [frame].nodes[i].clip_x0 = terralib.select([frame].nodes[i].clip_x0 > [frame].nodes[i].content_x,
                                                       [frame].nodes[i].clip_x0,
                                                       [frame].nodes[i].content_x)
            [frame].nodes[i].clip_x1 = terralib.select([frame].nodes[i].clip_x1 < [frame].nodes[i].content_x + [frame].nodes[i].content_w,
                                                       [frame].nodes[i].clip_x1,
                                                       [frame].nodes[i].content_x + [frame].nodes[i].content_w)
        end)
    end
    if self.vertical then
        stmts:insert(quote
            [frame].nodes[i].clip_y0 = terralib.select([frame].nodes[i].clip_y0 > [frame].nodes[i].content_y,
                                                       [frame].nodes[i].clip_y0,
                                                       [frame].nodes[i].content_y)
            [frame].nodes[i].clip_y1 = terralib.select([frame].nodes[i].clip_y1 < [frame].nodes[i].content_y + [frame].nodes[i].content_h,
                                                       [frame].nodes[i].clip_y1,
                                                       [frame].nodes[i].content_y + [frame].nodes[i].content_h)
        end)
    end

    if self.child_offset_x then
        local ox = self.child_offset_x:compile_number(ctx)
        stmts:insert(quote [frame].nodes[i].content_x = [frame].nodes[i].content_x - [ox] end)
    end
    if self.child_offset_y then
        local oy = self.child_offset_y:compile_number(ctx)
        stmts:insert(quote [frame].nodes[i].content_y = [frame].nodes[i].content_y - [oy] end)
    end

    return quote [stmts] end
end

function Plan.ClipSpec:compile_emit_begin(ctx)
    return quote end
end

function Plan.ClipSpec:compile_emit_end(ctx)
    return quote end
end

function Plan.TextSpec:compile_measure(ctx, mode)
    local content = self.content:compile_string(ctx)
    local font_size = self.font_size:compile_number(ctx)
    local line_height = self.line_height:compile_number(ctx)

    if mode == Plan.MeasureWidth then
        return `[float](C.strlen([content])) * [font_size] * 0.6f
    else
        return `[font_size] * [line_height]
    end
end

function Plan.TextSpec:compile_emit(ctx)
    return quote end
end

function Plan.ImageSpec:compile_emit(ctx)
    return quote end
end

function Plan.CustomSpec:compile_emit(ctx)
    return quote end
end

function Plan.FloatSpec:compile_place(ctx)
    local frame = ctx.frame_sym
    local node = ctx.plan.nodes[self.node_index + 1]
    local target = self.attach_parent_slot

    local target_x = `[frame].nodes[target].x
    local target_y = `[frame].nodes[target].y
    local target_w = `[frame].nodes[target].w
    local target_h = `[frame].nodes[target].h

    local intrinsic_w = `[frame].nodes[self.node_index].want_w
    local intrinsic_h = `[frame].nodes[self.node_index].want_h

    local base_w = resolve_size(node.width, target_w, intrinsic_w, ctx)
    local base_h = resolve_size(node.height, target_h, intrinsic_h, ctx)
    local w0, h0 = apply_aspect_ratio(node, base_w, base_h, ctx)

    local exw = self.expand_w:compile_number(ctx)
    local exh = self.expand_h:compile_number(ctx)
    local w = `[w0] + [exw]
    local h = `[h0] + [exh]

    local tx, ty = attach_point_xy(target_x, target_y, target_w, target_h, self.parent_point)
    local ex, ey = attach_point_xy(`0.0f, `0.0f, w, h, self.element_point)
    local ox = self.offset_x:compile_number(ctx)
    local oy = self.offset_y:compile_number(ctx)

    return quote
        [frame].nodes[self.node_index].x = [tx] - [ex] + [ox]
        [frame].nodes[self.node_index].y = [ty] - [ey] + [oy]
        [frame].nodes[self.node_index].w = [w]
        [frame].nodes[self.node_index].h = [h]
        [frame].nodes[self.node_index].clip_x0 = [frame].nodes[target].clip_x0
        [frame].nodes[self.node_index].clip_y0 = [frame].nodes[target].clip_y0
        [frame].nodes[self.node_index].clip_x1 = [frame].nodes[target].clip_x1
        [frame].nodes[self.node_index].clip_y1 = [frame].nodes[target].clip_y1
        [ctx:emit_node_content_box(node)]
    end
end

function CompileCtx:compile_layout_fn()
    local frame = self.frame_sym
    local nodes = self.plan.nodes
    local stmts = terralib.newlist()

    stmts:insert(quote
        [frame].draw_seq = 0
        [frame].action_node = -1
        [frame].action_name = nil
        [frame].cursor_name = nil
        [frame].hit.hot = -1
        [frame].hit.active = -1
        [frame].hit.focus = -1
    end)

    -- pass 1: intrinsic measure (postorder)
    for i = #nodes, 1, -1 do
        stmts:insert(self:emit_node_measure(nodes[i]))
    end

    -- pass 2: normal-flow layout (preorder), skipping floating subtrees
    local i = 1
    while i <= #nodes do
        local node = nodes[i]
        if node.float_slot then
            i = node.subtree_end + 1
        else
            stmts:insert(node:compile_layout(self))
            i = i + 1
        end
    end

    -- pass 3: floating placement + subtree layout
    for _, fs in ipairs(self.plan.floats) do
        local root = nodes[fs.node_index + 1]
        stmts:insert(fs:compile_place(self))
        stmts:insert(root:compile_layout(self))

        local j = root.index + 2
        while j <= root.subtree_end do
            local node = nodes[j]
            if node.float_slot then
                j = node.subtree_end + 1
            else
                stmts:insert(node:compile_layout(self))
                j = j + 1
            end
        end
    end

    return terra([frame])
        escape
            for _, s in ipairs(stmts) do emit(s) end
        end
    end
end

function Plan.Component:compile(ctx)
    local layout_fn = ctx:compile_layout_fn()
    local noop_fn   = terra(frame: &ctx.frame_t) end

    local runtime_types = Kernel.RuntimeTypes(
        ctx.params_t,
        ctx.state_t,
        ctx.frame_t,
        ctx.input_t,
        ctx.node_t,
        ctx.clip_state_t,
        ctx.scroll_state_t,
        ctx.hit_t)

    local kernels = Kernel.Kernels(
        `noop_fn,
        `layout_fn,
        `noop_fn,
        `noop_fn,
        `noop_fn)

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
-- Kernel methods
---------------------------------------------------------------------------

function Kernel.Component:frame_type()
    return self.types.frame_t
end

function Kernel.Component:run_quote()
    return self.kernels.run_fn
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local M = {}

M.CompileCtx = CompileCtx
M.Color      = Color
M.Vec2       = Vec2
M.NodeState  = NodeState
M.NodeRect   = NodeState -- compatibility alias with earlier tests/notes

function M.compile_component(plan_component)
    local ctx = CompileCtx.new(plan_component)
    return plan_component:compile(ctx)
end

return M
