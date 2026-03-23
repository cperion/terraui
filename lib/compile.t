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
    #include <math.h>
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

    content_extent_w: float; content_extent_h: float
    scroll_x: float; scroll_y: float
    scroll_need_x: bool; scroll_need_y: bool

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
    active_offset_x: float
    active_offset_y: float
}

struct ClipState   { count: int32 }
struct ScrollState { _pad: uint8 }
struct StubCmd     { seq: int32 }

struct RectCmd {
    x: float; y: float; w: float; h: float
    color: Color
    opacity: float
    z: float
    seq: uint32
}

struct BorderCmd {
    x: float; y: float; w: float; h: float
    left: float; top: float; right: float; bottom: float
    color: Color
    opacity: float
    z: float
    seq: uint32
}

struct TextCmd {
    x: float; y: float; w: float; h: float
    text: rawstring
    font_id: rawstring
    font_size: float
    letter_spacing: float
    line_height: float
    wrap: int32
    align: int32
    color: Color
    z: float
    seq: uint32
}

local TEXT_WRAP_NONE = 0
local TEXT_WRAP_WORDS = 1
local TEXT_WRAP_NEWLINES = 2

local TEXT_ALIGN_LEFT = 0
local TEXT_ALIGN_CENTER = 1
local TEXT_ALIGN_RIGHT = 2

terra approx_text_line_width(chars: int32, font_size: float, letter_spacing: float) : float
    if chars <= 0 then return 0.0f end
    var width = [float](chars) * font_size * 0.6f
    if chars > 1 then
        width = width + [float](chars - 1) * letter_spacing
    end
    return width
end

terra approx_text_max_explicit_line_width(text: rawstring, font_size: float, letter_spacing: float) : float
    if text == nil then return 0.0f end

    var max_chars: int32 = 0
    var cur_chars: int32 = 0
    var i: int32 = 0
    while text[i] ~= 0 do
        if text[i] == 10 then
            if cur_chars > max_chars then max_chars = cur_chars end
            cur_chars = 0
        else
            cur_chars = cur_chars + 1
        end
        i = i + 1
    end
    if cur_chars > max_chars then max_chars = cur_chars end
    return approx_text_line_width(max_chars, font_size, letter_spacing)
end

terra approx_text_explicit_line_count(text: rawstring) : int32
    if text == nil then return 1 end

    var lines: int32 = 1
    var i: int32 = 0
    while text[i] ~= 0 do
        if text[i] == 10 then
            lines = lines + 1
        end
        i = i + 1
    end
    return lines
end

terra approx_text_chars_per_line(max_width: float, font_size: float, letter_spacing: float) : int32
    var adv = font_size * 0.6f + letter_spacing
    if adv <= 0.0f then return 1 end

    var limit = [int32](max_width / adv)
    if limit < 1 then limit = 1 end
    return limit
end

terra place_wrapped_word(line_chars: int32, word_chars: int32, pending_space: int32, limit: int32, lines: &int32) : int32
    if word_chars <= 0 then return line_chars end

    var cur = line_chars
    var need = word_chars
    if cur > 0 then need = need + pending_space end

    if cur > 0 and cur + need <= limit then
        return cur + need
    end

    if cur > 0 then
        @lines = @lines + 1
        cur = 0
    end

    while word_chars > limit do
        cur = limit
        word_chars = word_chars - limit
        if word_chars > 0 then
            @lines = @lines + 1
            cur = 0
        end
    end

    return cur + word_chars
end

terra approx_text_wrapped_line_count(text: rawstring, max_width: float, font_size: float, letter_spacing: float) : int32
    if text == nil then return 1 end

    var limit = approx_text_chars_per_line(max_width, font_size, letter_spacing)
    var lines: int32 = 1
    var line_chars: int32 = 0
    var word_chars: int32 = 0
    var pending_space: int32 = 0
    var i: int32 = 0

    while text[i] ~= 0 do
        if text[i] == 10 then
            line_chars = place_wrapped_word(line_chars, word_chars, pending_space, limit, &lines)
            word_chars = 0
            pending_space = 0
            lines = lines + 1
            line_chars = 0
        elseif text[i] == 32 or text[i] == 9 or text[i] == 13 then
            line_chars = place_wrapped_word(line_chars, word_chars, pending_space, limit, &lines)
            word_chars = 0
            pending_space = pending_space + 1
        else
            word_chars = word_chars + 1
        end
        i = i + 1
    end

    line_chars = place_wrapped_word(line_chars, word_chars, pending_space, limit, &lines)
    return lines
end

struct ImageCmd {
    x: float; y: float; w: float; h: float
    image_id: rawstring
    tint: Color
    z: float
    seq: uint32
}

struct ScissorCmd {
    is_begin: bool
    x0: float; y0: float; x1: float; y1: float
    z: float
    seq: uint32
}

struct CustomCmd {
    x: float; y: float; w: float; h: float
    kind: rawstring
    z: float
    seq: uint32
}

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

local function wrap_mode_code(mode)
    if mode == Decl.WrapWords then return TEXT_WRAP_WORDS end
    if mode == Decl.WrapNewlines then return TEXT_WRAP_NEWLINES end
    return TEXT_WRAP_NONE
end

local function text_align_code(align)
    if align == Decl.TextAlignCenter then return TEXT_ALIGN_CENTER end
    if align == Decl.TextAlignRight then return TEXT_ALIGN_RIGHT end
    return TEXT_ALIGN_LEFT
end

local DefaultTextBackend = { key = "default" }

function DefaultTextBackend:measure_width(ctx, spec)
    local content = spec.content:compile_string(ctx)
    local font_size = spec.font_size:compile_number(ctx)
    local letter_spacing = spec.letter_spacing:compile_number(ctx)
    return `approx_text_max_explicit_line_width([content], [font_size], [letter_spacing])
end

function DefaultTextBackend:measure_height_for_width(ctx, spec, max_width)
    local content = spec.content:compile_string(ctx)
    local font_size = spec.font_size:compile_number(ctx)
    local letter_spacing = spec.letter_spacing:compile_number(ctx)
    local line_height = spec.line_height:compile_number(ctx)

    local line_count
    if spec.wrap == Decl.WrapWords then
        line_count = `approx_text_wrapped_line_count([content], [max_width], [font_size], [letter_spacing])
    elseif spec.wrap == Decl.WrapNewlines then
        line_count = `approx_text_explicit_line_count([content])
    else
        line_count = `1
    end

    return `[float]([line_count]) * [font_size] * [line_height]
end

local function text_backend_key(backend)
    if type(backend) == "table" and backend.key ~= nil then
        return tostring(backend.key)
    elseif backend ~= nil then
        return tostring(backend)
    end
    return tostring(DefaultTextBackend.key)
end

---------------------------------------------------------------------------
-- CompileCtx
---------------------------------------------------------------------------

local CompileCtx = {}
CompileCtx.__index = CompileCtx

function CompileCtx.new(plan_component, opts)
    opts = opts or {}
    local pc  = plan_component
    local key = pc.key
    local text_backend = opts.text_backend
    if text_backend == nil then
        if key.text_backend == nil or key.text_backend == "default" then
            text_backend = DefaultTextBackend
        else
            error("compile.text_backend required for specialization: " .. tostring(key.text_backend))
        end
    end
    assert(type(text_backend) == "table", "compile.text_backend must be a table")
    assert(type(text_backend.measure_width) == "function", "compile.text_backend.measure_width required")
    assert(type(text_backend.measure_height_for_width) == "function", "compile.text_backend.measure_height_for_width required")
    assert(text_backend_key(text_backend) == tostring(key.text_backend),
        "compile.text_backend key mismatch: expected " .. tostring(key.text_backend) .. ", got " .. text_backend_key(text_backend))

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

    local rect_cap = 0
    local border_cap = 0
    for _, p in ipairs(pc.paints) do
        if p.background then rect_cap = rect_cap + 1 end
        if p.border then border_cap = border_cap + 1 end
    end
    local text_cap = #pc.texts
    local image_cap = #pc.images
    local scissor_cap = #pc.clips * 2
    local custom_cap = #pc.customs

    local frame_t = terralib.types.newstruct("Frame")
    frame_t.entries:insert({ field = "params",      type = params_t })
    frame_t.entries:insert({ field = "state",       type = state_t })
    frame_t.entries:insert({ field = "nodes",       type = node_t[node_count] })
    frame_t.entries:insert({ field = "input",       type = input_t })
    frame_t.entries:insert({ field = "hit",         type = hit_t })
    frame_t.entries:insert({ field = "text_backend_state", type = &opaque })
    frame_t.entries:insert({ field = "viewport_w",  type = float })
    frame_t.entries:insert({ field = "viewport_h",  type = float })
    frame_t.entries:insert({ field = "draw_seq",    type = uint32 })
    frame_t.entries:insert({ field = "action_node", type = int32 })
    frame_t.entries:insert({ field = "action_name", type = rawstring })
    frame_t.entries:insert({ field = "cursor_name", type = rawstring })
    frame_t.entries:insert({ field = "rects",         type = RectCmd[math.max(rect_cap, 1)] })
    frame_t.entries:insert({ field = "rect_count",    type = int32 })
    frame_t.entries:insert({ field = "borders",       type = BorderCmd[math.max(border_cap, 1)] })
    frame_t.entries:insert({ field = "border_count",  type = int32 })
    frame_t.entries:insert({ field = "texts",         type = TextCmd[math.max(text_cap, 1)] })
    frame_t.entries:insert({ field = "text_count",    type = int32 })
    frame_t.entries:insert({ field = "images",        type = ImageCmd[math.max(image_cap, 1)] })
    frame_t.entries:insert({ field = "image_count",   type = int32 })
    frame_t.entries:insert({ field = "scissors",      type = ScissorCmd[math.max(scissor_cap, 1)] })
    frame_t.entries:insert({ field = "scissor_count", type = int32 })
    frame_t.entries:insert({ field = "customs",       type = CustomCmd[math.max(custom_cap, 1)] })
    frame_t.entries:insert({ field = "custom_count",  type = int32 })

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
        rect_cmd_t      = RectCmd,
        border_cmd_t    = BorderCmd,
        text_cmd_t      = TextCmd,
        image_cmd_t     = ImageCmd,
        scissor_cmd_t   = ScissorCmd,
        custom_cmd_t    = CustomCmd,
        frame_t         = frame_t,
        node_count      = node_count,
        frame_sym       = frame_sym,
        text_backend    = text_backend,
    }, CompileCtx)
end

function CompileCtx:measure_text_width(spec)
    return self.text_backend:measure_width(self, spec)
end

function CompileCtx:measure_text_height_for_width(spec, max_width)
    return self.text_backend:measure_height_for_width(self, spec, max_width)
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

function Plan.ScrollMetric:compile_number(ctx)
    local frame = ctx.frame_sym
    local n = self.node_index
    local metric = self.metric
    if metric == Decl.ScrollOffsetX then
        return `[frame].nodes[n].scroll_x
    elseif metric == Decl.ScrollOffsetY then
        return `[frame].nodes[n].scroll_y
    elseif metric == Decl.ScrollViewportW then
        return `[frame].nodes[n].content_w
    elseif metric == Decl.ScrollViewportH then
        return `[frame].nodes[n].content_h
    elseif metric == Decl.ScrollContentW then
        return `[frame].nodes[n].content_extent_w
    elseif metric == Decl.ScrollContentH then
        return `[frame].nodes[n].content_extent_h
    elseif metric == Decl.ScrollMaxX then
        return `terralib.select([frame].nodes[n].content_extent_w - [frame].nodes[n].content_w > 0.0f,
                                 [frame].nodes[n].content_extent_w - [frame].nodes[n].content_w,
                                 0.0f)
    elseif metric == Decl.ScrollMaxY then
        return `terralib.select([frame].nodes[n].content_extent_h - [frame].nodes[n].content_h > 0.0f,
                                 [frame].nodes[n].content_extent_h - [frame].nodes[n].content_h,
                                 0.0f)
    elseif metric == Decl.ScrollNeedX then
        return `terralib.select([frame].nodes[n].scroll_need_x, 1.0f, 0.0f)
    elseif metric == Decl.ScrollNeedY then
        return `terralib.select([frame].nodes[n].scroll_need_y, 1.0f, 0.0f)
    end
    error("unknown scroll metric")
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
    elseif op == "max" then
        return `terralib.select([a[1]] > [a[2]], [a[1]], [a[2]])
    elseif op == "min" then
        return `terralib.select([a[1]] < [a[2]], [a[1]], [a[2]])
    elseif op == ">" then
        return `terralib.select([a[1]] > [a[2]], 1.0f, 0.0f)
    elseif op == "<" then
        return `terralib.select([a[1]] < [a[2]], 1.0f, 0.0f)
    elseif op == ">=" then
        return `terralib.select([a[1]] >= [a[2]], 1.0f, 0.0f)
    elseif op == "<=" then
        return `terralib.select([a[1]] <= [a[2]], 1.0f, 0.0f)
    elseif op == "==" then
        return `terralib.select([a[1]] == [a[2]], 1.0f, 0.0f)
    elseif op == "!=" then
        return `terralib.select([a[1]] ~= [a[2]], 1.0f, 0.0f)
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

function Plan.ScrollMetric:compile_bool(ctx)
    local frame = ctx.frame_sym
    local n = self.node_index
    local metric = self.metric
    if metric == Decl.ScrollNeedX then
        return `[frame].nodes[n].scroll_need_x
    elseif metric == Decl.ScrollNeedY then
        return `[frame].nodes[n].scroll_need_y
    end
    local num = self:compile_number(ctx)
    return `[num] ~= 0.0f
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

function Plan.Param:compile_color(ctx)
    local frame = ctx.frame_sym
    local f = "p" .. self.slot
    return `[frame].params.[f]
end

function Plan.State:compile_color(ctx)
    local frame = ctx.frame_sym
    local f = "s" .. self.slot
    return `[frame].state.[f]
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

function Plan.State:compile_string(ctx)
    local frame = ctx.frame_sym
    local f = "s" .. self.slot
    return `[frame].state.[f]
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

local function measure_rule_size(rule, want_q, ctx)
    return resolve_size(rule, `0.0f, want_q, ctx)
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

---------------------------------------------------------------------------
-- Width-first layout: measure widths, resolve widths, measure heights
---------------------------------------------------------------------------

-- Pass A: bottom-up width measure — compute want_w, content_extent_w
function CompileCtx:emit_width_measure(node)
    local frame = self.frame_sym
    local i = node.index
    local stmts = terralib.newlist()

    local pad_l = node.padding_left:compile_number(self)
    local pad_r = node.padding_right:compile_number(self)

    local leaf_w = `0.0f
    if node.text_slot then
        local ts = self.plan.texts[node.text_slot + 1]
        leaf_w = ts:compile_measure_width(self)
    end

    local children = self:flow_children(node)
    local child_w = symbol(float, "wm_cw" .. i)
    stmts:insert(quote var [child_w] = 0.0f end)

    local child_count = #children
    if child_count > 0 then
        local gap_v = node.gap:compile_number(self)
        if node.axis == Decl.Row then
            if child_count > 1 then
                stmts:insert(quote [child_w] = [gap_v] * [float](child_count - 1) end)
            end
            for _, child in ipairs(children) do
                local ci = child.index
                stmts:insert(quote
                    [child_w] = [child_w] + [measure_rule_size(child.width, `[frame].nodes[ci].want_w, self)]
                end)
            end
        else
            for _, child in ipairs(children) do
                local ci = child.index
                local mw = measure_rule_size(child.width, `[frame].nodes[ci].want_w, self)
                stmts:insert(quote
                    [child_w] = terralib.select([child_w] > [mw], [child_w], [mw])
                end)
            end
        end
    end

    stmts:insert(quote
        if [frame].nodes[i].visible then
            [frame].nodes[i].content_extent_w = terralib.select([leaf_w] > [child_w], [leaf_w], [child_w])
            [frame].nodes[i].want_w = [frame].nodes[i].content_extent_w + [pad_l] + [pad_r]
        else
            [frame].nodes[i].content_extent_w = 0.0f
            [frame].nodes[i].want_w = 0.0f
        end
    end)

    return quote [stmts] end
end

-- Pass B: top-down width resolve — assign w and content_w for every node
function CompileCtx:emit_width_resolve(node)
    local frame = self.frame_sym
    local i = node.index
    local active = terralib.newlist()

    local pad_l = node.padding_left:compile_number(self)
    local pad_r = node.padding_right:compile_number(self)

    if node.parent == nil then
        local w = resolve_size(node.width, `[frame].viewport_w, `[frame].nodes[i].want_w, self)
        active:insert(quote [frame].nodes[i].w = [w] end)
    end
    -- Non-root: w was already set by parent's width distribution

    -- Snap content_w to floor BEFORE height measurement so that text
    -- wrapping during measure uses the same pixel-exact width as the
    -- renderer.  Without this, a fractional content_w lets a word "fit"
    -- during measurement that then wraps during rendering.
    active:insert(quote
        [frame].nodes[i].content_w = C.floorf([frame].nodes[i].w - [pad_l] - [pad_r])
    end)

    -- Distribute widths to flow children
    local children = self:flow_children(node)
    if #children > 0 then
        active:insertall(self:emit_width_distribution(node, children))
    end

    return quote
        if [frame].nodes[i].visible then
            [active]
        else
            [frame].nodes[i].w = 0
            [frame].nodes[i].content_w = 0
        end
    end
end

function CompileCtx:emit_width_distribution(parent, children)
    local frame = self.frame_sym
    local pi = parent.index
    local stmts = terralib.newlist()
    local is_row = (parent.axis == Decl.Row)
    local avail_w = `[frame].nodes[pi].content_w

    if is_row then
        -- Row: width is the main axis — distribute among children
        local gap_v = parent.gap:compile_number(self)
        local grow_count = 0
        for _, child in ipairs(children) do
            if child.width.kind == "Grow" then grow_count = grow_count + 1 end
        end

        local total_fixed = symbol(float, "wd_tf" .. pi)
        stmts:insert(quote var [total_fixed] = 0.0f end)

        local child_syms = {}
        for idx, child in ipairs(children) do
            local sym = symbol(float, "wd_w" .. child.index)
            child_syms[idx] = sym
            if child.width.kind == "Grow" then
                stmts:insert(quote var [sym] = 0.0f end)
            else
                local val = resolve_size(child.width, avail_w, `[frame].nodes[child.index].want_w, self)
                stmts:insert(quote
                    var [sym] = [val]
                    [total_fixed] = [total_fixed] + [sym]
                end)
            end
        end

        if grow_count > 0 then
            local rem = symbol(float, "wd_rem" .. pi)
            local ge  = symbol(float, "wd_ge" .. pi)
            stmts:insert(quote
                var [rem] = [avail_w] - [total_fixed] - [gap_v] * [float]([#children - 1])
                if [rem] < 0 then [rem] = 0 end
                var [ge] = [rem] / [float](grow_count)
            end)
            for idx, child in ipairs(children) do
                if child.width.kind == "Grow" then
                    local r = `[ge]
                    if child.width.min then
                        local mn = child.width.min:compile_number(self)
                        r = `terralib.select([r] < [mn], [mn], [r])
                    end
                    if child.width.max then
                        local mx = child.width.max:compile_number(self)
                        r = `terralib.select([r] > [mx], [mx], [r])
                    end
                    stmts:insert(quote [child_syms[idx]] = [r] end)
                end
            end
        end

        for idx, child in ipairs(children) do
            stmts:insert(quote [frame].nodes[child.index].w = [child_syms[idx]] end)
        end
    else
        -- Column: width is the cross axis — each child resolved independently
        for _, child in ipairs(children) do
            local w = resolve_size(child.width, avail_w, `[frame].nodes[child.index].want_w, self)
            stmts:insert(quote [frame].nodes[child.index].w = [w] end)
        end
    end

    return stmts
end

-- Float width resolve — set w and content_w from anchor dimensions
function CompileCtx:emit_float_width_resolve(fs)
    local frame = self.frame_sym
    local node = self.plan.nodes[fs.node_index + 1]
    local target = fs.attach_parent_slot

    local pad_l = node.padding_left:compile_number(self)
    local pad_r = node.padding_right:compile_number(self)
    local base_w = resolve_size(node.width, `[frame].nodes[target].w, `[frame].nodes[fs.node_index].want_w, self)
    local exw = fs.expand_w:compile_number(self)

    return quote
        if [frame].nodes[fs.node_index].visible then
            [frame].nodes[fs.node_index].w = [base_w] + [exw]
            [frame].nodes[fs.node_index].content_w = C.floorf([frame].nodes[fs.node_index].w - [pad_l] - [pad_r])
        else
            [frame].nodes[fs.node_index].w = 0
            [frame].nodes[fs.node_index].content_w = 0
        end
    end
end

-- Pass C: bottom-up height measure — compute want_h, content_extent_h
-- using the real content_w assigned by the width resolve pass
function CompileCtx:emit_height_measure(node)
    local frame = self.frame_sym
    local i = node.index
    local pad_t = node.padding_top:compile_number(self)
    local pad_b = node.padding_bottom:compile_number(self)
    local gap_v = node.gap:compile_number(self)

    local leaf_h = `0.0f
    if node.text_slot then
        local ts = self.plan.texts[node.text_slot + 1]
        leaf_h = ts:compile_measure_height_for_width(self, `[frame].nodes[i].content_w)
    end

    local children = self:flow_children(node)
    local child_h = symbol(float, "hm_ch" .. i)
    local stmts = terralib.newlist()
    stmts:insert(quote var [child_h] = 0.0f end)

    local child_count = #children
    if child_count > 0 then
        if node.axis == Decl.Row then
            for _, child in ipairs(children) do
                local ci = child.index
                local mh = measure_rule_size(child.height, `[frame].nodes[ci].want_h, self)
                stmts:insert(quote
                    [child_h] = terralib.select([child_h] > [mh], [child_h], [mh])
                end)
            end
        else
            if child_count > 1 then
                stmts:insert(quote [child_h] = [gap_v] * [float](child_count - 1) end)
            end
            for _, child in ipairs(children) do
                local ci = child.index
                stmts:insert(quote
                    [child_h] = [child_h] + [measure_rule_size(child.height, `[frame].nodes[ci].want_h, self)]
                end)
            end
        end
    end

    stmts:insert(quote
        if [frame].nodes[i].visible then
            [frame].nodes[i].content_extent_h = terralib.select([leaf_h] > [child_h], [leaf_h], [child_h])
            [frame].nodes[i].want_h = [frame].nodes[i].content_extent_h + [pad_t] + [pad_b]
        else
            [frame].nodes[i].content_extent_h = 0.0f
            [frame].nodes[i].want_h = 0.0f
        end
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
    local i = self.index
    local active = terralib.newlist()

    if self.parent == nil then
        local w0 = resolve_size(self.width, `[frame].viewport_w, `[frame].nodes[i].want_w, ctx)
        local h0 = resolve_size(self.height, `[frame].viewport_h, `[frame].nodes[i].want_h, ctx)
        local w, h = apply_aspect_ratio(self, w0, h0, ctx)
        active:insert(quote
            [frame].nodes[i].x = 0
            [frame].nodes[i].y = 0
            [frame].nodes[i].w = [w]
            [frame].nodes[i].h = [h]
            [frame].nodes[i].clip_x0 = 0
            [frame].nodes[i].clip_y0 = 0
            [frame].nodes[i].clip_x1 = [frame].viewport_w
            [frame].nodes[i].clip_y1 = [frame].viewport_h
        end)
        active:insert(ctx:emit_node_content_box(self))
    end

    if self.clip_slot then
        local clip = ctx.plan.clips[self.clip_slot + 1]
        active:insert(clip:compile_apply(ctx))
    end

    if self.scroll_slot then
        local scroll = ctx.plan.scrolls[self.scroll_slot + 1]
        active:insert(scroll:compile_apply(ctx))
    end

    if self.child_count > 0 then
        active:insertall(ctx:emit_children_placement(self))
    end

    return quote
        if [frame].nodes[i].visible then
            [active]
        else
            [frame].nodes[i].x = 0
            [frame].nodes[i].y = 0
            [frame].nodes[i].w = 0
            [frame].nodes[i].h = 0
            [frame].nodes[i].content_x = 0
            [frame].nodes[i].content_y = 0
            [frame].nodes[i].content_w = 0
            [frame].nodes[i].content_h = 0
            [frame].nodes[i].content_extent_w = 0
            [frame].nodes[i].content_extent_h = 0
            [frame].nodes[i].scroll_x = 0
            [frame].nodes[i].scroll_y = 0
            [frame].nodes[i].scroll_need_x = false
            [frame].nodes[i].scroll_need_y = false
            [frame].nodes[i].clip_x0 = 0
            [frame].nodes[i].clip_y0 = 0
            [frame].nodes[i].clip_x1 = 0
            [frame].nodes[i].clip_y1 = 0
        end
    end
end

local function node_z_binding(ctx, node_index)
    local node = ctx.plan.nodes[node_index + 1]
    while node do
        if node.float_slot then
            local fs = ctx.plan.floats[node.float_slot + 1]
            return fs.z_index:compile_number(ctx)
        end
        if node.parent == nil then break end
        node = ctx.plan.nodes[node.parent + 1]
    end
    return `0.0f
end

function Plan.Node:compile_hit(ctx)
    local frame = ctx.frame_sym
    local input = ctx.plan.inputs[self.input_slot + 1]

    local interactive = input.hover or input.press or input.focus or input.wheel
                        or input.cursor ~= nil or input.action ~= nil
                        or self.scroll_slot ~= nil
    if not interactive then
        return quote end
    end

    local i = self.index
    local stmts = terralib.newlist()
    stmts:insert(quote
        if [frame].hit.hot == -1 and [frame].nodes[i].visible and [frame].nodes[i].enabled then
            if [frame].input.mouse_x >= [frame].nodes[i].x and [frame].input.mouse_x <= [frame].nodes[i].x + [frame].nodes[i].w and
               [frame].input.mouse_y >= [frame].nodes[i].y and [frame].input.mouse_y <= [frame].nodes[i].y + [frame].nodes[i].h and
               [frame].input.mouse_x >= [frame].nodes[i].clip_x0 and [frame].input.mouse_x <= [frame].nodes[i].clip_x1 and
               [frame].input.mouse_y >= [frame].nodes[i].clip_y0 and [frame].input.mouse_y <= [frame].nodes[i].clip_y1 then
                [frame].hit.hot = i
            end
        end
    end)
    if input.cursor then
        local c = input.cursor
        stmts:insert(quote
            if [frame].hit.hot == i then
                [frame].cursor_name = c
            end
        end)
    end
    return quote [stmts] end
end

function Plan.Paint:compile_emit(ctx, node_index)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, node_index)
    local opacity = self.opacity and self.opacity:compile_number(ctx) or `1.0f
    local stmts = terralib.newlist()

    if self.background then
        local color = self.background:compile_color(ctx)
        stmts:insert(quote
            var idx = [frame].rect_count
            [frame].rects[idx].x = [frame].nodes[node_index].x
            [frame].rects[idx].y = [frame].nodes[node_index].y
            [frame].rects[idx].w = [frame].nodes[node_index].w
            [frame].rects[idx].h = [frame].nodes[node_index].h
            [frame].rects[idx].color = [color]
            [frame].rects[idx].opacity = [opacity]
            [frame].rects[idx].z = [z]
            [frame].rects[idx].seq = [frame].draw_seq
            [frame].rect_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end)
    end

    if self.border then
        local color = self.border.color:compile_color(ctx)
        local l = self.border.left:compile_number(ctx)
        local t = self.border.top:compile_number(ctx)
        local r = self.border.right:compile_number(ctx)
        local b = self.border.bottom:compile_number(ctx)
        stmts:insert(quote
            var idx = [frame].border_count
            [frame].borders[idx].x = [frame].nodes[node_index].x
            [frame].borders[idx].y = [frame].nodes[node_index].y
            [frame].borders[idx].w = [frame].nodes[node_index].w
            [frame].borders[idx].h = [frame].nodes[node_index].h
            [frame].borders[idx].left = [l]
            [frame].borders[idx].top = [t]
            [frame].borders[idx].right = [r]
            [frame].borders[idx].bottom = [b]
            [frame].borders[idx].color = [color]
            [frame].borders[idx].opacity = [opacity]
            [frame].borders[idx].z = [z]
            [frame].borders[idx].seq = [frame].draw_seq
            [frame].border_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end)
    end

    return quote
        if [frame].nodes[node_index].visible then
            [stmts]
        end
    end
end

function Plan.InputSpec:compile_input(ctx, node_index)
    local frame = ctx.frame_sym
    local stmts = terralib.newlist()

    if self.press then
        stmts:insert(quote
            if [frame].input.mouse_pressed and [frame].hit.hot == node_index then
                [frame].hit.active = node_index
                [frame].hit.active_offset_x = [frame].input.mouse_x - [frame].nodes[node_index].x
                [frame].hit.active_offset_y = [frame].input.mouse_y - [frame].nodes[node_index].y
            end
        end)
    end

    if self.focus then
        stmts:insert(quote
            if [frame].input.mouse_pressed and [frame].hit.hot == node_index then
                [frame].hit.focus = node_index
            end
        end)
    end

    if self.action then
        local action = self.action
        stmts:insert(quote
            if [frame].input.mouse_released and [frame].hit.active == node_index then
                if [frame].hit.hot == node_index then
                    [frame].action_node = node_index
                    [frame].action_name = action
                end
                [frame].hit.active = -1
                [frame].hit.active_offset_x = 0.0f
                [frame].hit.active_offset_y = 0.0f
            end
        end)
    elseif self.press then
        stmts:insert(quote
            if [frame].input.mouse_released and [frame].hit.active == node_index then
                [frame].hit.active = -1
                [frame].hit.active_offset_x = 0.0f
                [frame].hit.active_offset_y = 0.0f
            end
        end)
    end

    return quote [stmts] end
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

    return quote [stmts] end
end

function Plan.ScrollSpec:compile_apply(ctx)
    local frame = ctx.frame_sym
    local i = self.node_index
    local stmts = terralib.newlist()

    if self.horizontal then
        stmts:insert(quote
            var max_scroll_x = [frame].nodes[i].content_extent_w - [frame].nodes[i].content_w
            [frame].nodes[i].scroll_need_x = max_scroll_x > 0.0f
            if max_scroll_x > 0.0f then
                if [frame].nodes[i].scroll_x < 0.0f then [frame].nodes[i].scroll_x = 0.0f end
                if [frame].nodes[i].scroll_x > max_scroll_x then [frame].nodes[i].scroll_x = max_scroll_x end
                [frame].nodes[i].content_x = [frame].nodes[i].content_x - [frame].nodes[i].scroll_x
            end
        end)
    else
        stmts:insert(quote
            [frame].nodes[i].scroll_x = 0.0f
            [frame].nodes[i].scroll_need_x = false
        end)
    end

    if self.vertical then
        stmts:insert(quote
            var max_scroll_y = [frame].nodes[i].content_extent_h - [frame].nodes[i].content_h
            [frame].nodes[i].scroll_need_y = max_scroll_y > 0.0f
            if max_scroll_y > 0.0f then
                if [frame].nodes[i].scroll_y < 0.0f then [frame].nodes[i].scroll_y = 0.0f end
                if [frame].nodes[i].scroll_y > max_scroll_y then [frame].nodes[i].scroll_y = max_scroll_y end
                [frame].nodes[i].content_y = [frame].nodes[i].content_y - [frame].nodes[i].scroll_y
            end
        end)
    else
        stmts:insert(quote
            [frame].nodes[i].scroll_y = 0.0f
            [frame].nodes[i].scroll_need_y = false
        end)
    end

    return quote [stmts] end
end

function Plan.ScrollSpec:compile_input(ctx)
    local frame = ctx.frame_sym
    local i = self.node_index
    local body = terralib.newlist()

    if self.horizontal then
        body:insert(quote
            if [frame].input.wheel_dx ~= 0.0f then
                [frame].nodes[i].scroll_x = [frame].nodes[i].scroll_x + [frame].input.wheel_dx * 32.0f
                [frame].input.wheel_dx = 0.0f
            end
        end)
    end

    if self.vertical then
        body:insert(quote
            if [frame].input.wheel_dy ~= 0.0f then
                [frame].nodes[i].scroll_y = [frame].nodes[i].scroll_y + [frame].input.wheel_dy * 32.0f
                [frame].input.wheel_dy = 0.0f
            end
        end)
    end

    -- Route wheel events when the hot node falls inside the scroll_area's
    -- subtree.  The scroll_area outer container is the scroll node's parent;
    -- its subtree covers the viewport, overlay bars, and all descendants.
    local parent_node = ctx.plan.nodes[i + 1].parent
    local area_start = parent_node or i
    local area_end = ctx.plan.nodes[area_start + 1].subtree_end

    return quote
        if [frame].nodes[i].visible and [frame].nodes[i].enabled and
           [frame].hit.hot >= [area_start] and [frame].hit.hot < [area_end] then
            [body]
        end
    end
end

function Plan.ScrollControlSpec:compile_input(ctx)
    local frame = ctx.frame_sym
    local node = ctx.plan.nodes[self.node_index + 1]
    if node.parent == nil then
        return quote end
    end

    local track = node.parent
    local target = self.target_node_index
    local i = self.node_index
    local kind = self.kind

    if self.axis == Decl.ScrollAxisY then
        if kind == Decl.ScrollThumbKind then
            return quote
                if [frame].hit.active == i and [frame].input.mouse_down and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    var max_scroll = [frame].nodes[target].content_extent_h - [frame].nodes[target].content_h
                    if max_scroll < 0.0f then max_scroll = 0.0f end
                    var travel = [frame].nodes[track].content_h - [frame].nodes[i].h
                    if travel <= 0.0f or max_scroll <= 0.0f then
                        [frame].nodes[target].scroll_y = 0.0f
                    else
                        var pos = [frame].input.mouse_y - [frame].nodes[track].content_y - [frame].hit.active_offset_y
                        if pos < 0.0f then pos = 0.0f end
                        if pos > travel then pos = travel end
                        [frame].nodes[target].scroll_y = pos / travel * max_scroll
                    end
                end
            end
        elseif kind == Decl.ScrollPageDecKind then
            return quote
                if [frame].input.mouse_pressed and [frame].hit.hot == i and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    [frame].nodes[target].scroll_y = [frame].nodes[target].scroll_y - [frame].nodes[target].content_h
                    [frame].hit.active = -1
                    [frame].hit.active_offset_x = 0.0f
                    [frame].hit.active_offset_y = 0.0f
                end
            end
        else
            return quote
                if [frame].input.mouse_pressed and [frame].hit.hot == i and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    [frame].nodes[target].scroll_y = [frame].nodes[target].scroll_y + [frame].nodes[target].content_h
                    [frame].hit.active = -1
                    [frame].hit.active_offset_x = 0.0f
                    [frame].hit.active_offset_y = 0.0f
                end
            end
        end
    else
        if kind == Decl.ScrollThumbKind then
            return quote
                if [frame].hit.active == i and [frame].input.mouse_down and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    var max_scroll = [frame].nodes[target].content_extent_w - [frame].nodes[target].content_w
                    if max_scroll < 0.0f then max_scroll = 0.0f end
                    var travel = [frame].nodes[track].content_w - [frame].nodes[i].w
                    if travel <= 0.0f or max_scroll <= 0.0f then
                        [frame].nodes[target].scroll_x = 0.0f
                    else
                        var pos = [frame].input.mouse_x - [frame].nodes[track].content_x - [frame].hit.active_offset_x
                        if pos < 0.0f then pos = 0.0f end
                        if pos > travel then pos = travel end
                        [frame].nodes[target].scroll_x = pos / travel * max_scroll
                    end
                end
            end
        elseif kind == Decl.ScrollPageDecKind then
            return quote
                if [frame].input.mouse_pressed and [frame].hit.hot == i and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    [frame].nodes[target].scroll_x = [frame].nodes[target].scroll_x - [frame].nodes[target].content_w
                    [frame].hit.active = -1
                    [frame].hit.active_offset_x = 0.0f
                    [frame].hit.active_offset_y = 0.0f
                end
            end
        else
            return quote
                if [frame].input.mouse_pressed and [frame].hit.hot == i and [frame].nodes[i].visible and [frame].nodes[i].enabled then
                    [frame].nodes[target].scroll_x = [frame].nodes[target].scroll_x + [frame].nodes[target].content_w
                    [frame].hit.active = -1
                    [frame].hit.active_offset_x = 0.0f
                    [frame].hit.active_offset_y = 0.0f
                end
            end
        end
    end
end

function Plan.ClipSpec:compile_emit_begin(ctx)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, self.node_index)
    return quote
        if [frame].nodes[self.node_index].visible then
            var idx = [frame].scissor_count
            [frame].scissors[idx].is_begin = true
            [frame].scissors[idx].x0 = [frame].nodes[self.node_index].clip_x0
            [frame].scissors[idx].y0 = [frame].nodes[self.node_index].clip_y0
            [frame].scissors[idx].x1 = [frame].nodes[self.node_index].clip_x1
            [frame].scissors[idx].y1 = [frame].nodes[self.node_index].clip_y1
            [frame].scissors[idx].z = [z]
            [frame].scissors[idx].seq = [frame].draw_seq
            [frame].scissor_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end
    end
end

function Plan.ClipSpec:compile_emit_end(ctx)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, self.node_index)
    return quote
        if [frame].nodes[self.node_index].visible then
            var idx = [frame].scissor_count
            [frame].scissors[idx].is_begin = false
            [frame].scissors[idx].x0 = [frame].nodes[self.node_index].clip_x0
            [frame].scissors[idx].y0 = [frame].nodes[self.node_index].clip_y0
            [frame].scissors[idx].x1 = [frame].nodes[self.node_index].clip_x1
            [frame].scissors[idx].y1 = [frame].nodes[self.node_index].clip_y1
            [frame].scissors[idx].z = [z]
            [frame].scissors[idx].seq = [frame].draw_seq
            [frame].scissor_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end
    end
end

function Plan.TextSpec:compile_measure_width(ctx)
    return ctx:measure_text_width(self)
end

function Plan.TextSpec:compile_measure_height_for_width(ctx, max_width)
    return ctx:measure_text_height_for_width(self, max_width)
end

function Plan.TextSpec:compile_emit(ctx)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, self.node_index)
    local text = self.content:compile_string(ctx)
    local font_id = self.font_id:compile_string(ctx)
    local font_size = self.font_size:compile_number(ctx)
    local letter_spacing = self.letter_spacing:compile_number(ctx)
    local line_height = self.line_height:compile_number(ctx)
    local color = self.color:compile_color(ctx)
    local wrap = wrap_mode_code(self.wrap)
    local align = text_align_code(self.align)

    return quote
        if [frame].nodes[self.node_index].visible then
            var idx = [frame].text_count
            [frame].texts[idx].x = [frame].nodes[self.node_index].content_x
            [frame].texts[idx].y = [frame].nodes[self.node_index].content_y
            [frame].texts[idx].w = [frame].nodes[self.node_index].content_w
            [frame].texts[idx].h = [frame].nodes[self.node_index].content_h
            [frame].texts[idx].text = [text]
            [frame].texts[idx].font_id = [font_id]
            [frame].texts[idx].font_size = [font_size]
            [frame].texts[idx].letter_spacing = [letter_spacing]
            [frame].texts[idx].line_height = [line_height]
            [frame].texts[idx].wrap = wrap
            [frame].texts[idx].align = align
            [frame].texts[idx].color = [color]
            [frame].texts[idx].z = [z]
            [frame].texts[idx].seq = [frame].draw_seq
            [frame].text_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end
    end
end

function Plan.ImageSpec:compile_emit(ctx)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, self.node_index)
    local image_id = self.image_id:compile_string(ctx)
    local tint = self.tint:compile_color(ctx)

    return quote
        if [frame].nodes[self.node_index].visible then
            var idx = [frame].image_count
            [frame].images[idx].x = [frame].nodes[self.node_index].x
            [frame].images[idx].y = [frame].nodes[self.node_index].y
            [frame].images[idx].w = [frame].nodes[self.node_index].w
            [frame].images[idx].h = [frame].nodes[self.node_index].h
            [frame].images[idx].image_id = [image_id]
            [frame].images[idx].tint = [tint]
            [frame].images[idx].z = [z]
            [frame].images[idx].seq = [frame].draw_seq
            [frame].image_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end
    end
end

function Plan.CustomSpec:compile_emit(ctx)
    local frame = ctx.frame_sym
    local z = node_z_binding(ctx, self.node_index)
    local kind = self.kind
    return quote
        if [frame].nodes[self.node_index].visible then
            var idx = [frame].custom_count
            [frame].customs[idx].x = [frame].nodes[self.node_index].x
            [frame].customs[idx].y = [frame].nodes[self.node_index].y
            [frame].customs[idx].w = [frame].nodes[self.node_index].w
            [frame].customs[idx].h = [frame].nodes[self.node_index].h
            [frame].customs[idx].kind = kind
            [frame].customs[idx].z = [z]
            [frame].customs[idx].seq = [frame].draw_seq
            [frame].custom_count = idx + 1
            [frame].draw_seq = [frame].draw_seq + 1
        end
    end
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

function CompileCtx:emit_guard_eval(node)
    local frame = self.frame_sym
    local i = node.index
    local guard = self.plan.guards[node.guard_slot + 1]
    local visible = guard.visible_when and guard.visible_when:compile_bool(self) or `true
    local enabled = guard.enabled_when and guard.enabled_when:compile_bool(self) or `true

    if node.parent == nil then
        return quote
            [frame].nodes[i].visible = [visible]
            [frame].nodes[i].enabled = [enabled]
        end
    end

    local p = node.parent
    return quote
        [frame].nodes[i].visible = [frame].nodes[p].visible and [visible]
        [frame].nodes[i].enabled = [frame].nodes[p].enabled and [enabled]
    end
end

function CompileCtx:compile_layout_fn()
    local frame = self.frame_sym
    local nodes = self.plan.nodes
    local stmts = terralib.newlist()

    ---------------------------------------------------------------------------
    -- Width-first layout: 5 passes, single iteration
    --
    --   1. guard_eval    (TD)  — visibility / enabled flags
    --   2. width_measure (BU)  — intrinsic want_w, content_extent_w
    --   3. width_resolve (TD)  — assign w, content_w to every node
    --   4. height_measure(BU)  — want_h using real content_w (text wrapping)
    --   5. layout        (TD)  — assign h, x, y; scroll clamp; clip
    --
    -- Scrollbars are overlay floats (don't take width), so there is no
    -- vbar-visibility ↔ viewport-width cycle.  One iteration suffices.
    ---------------------------------------------------------------------------

    -- Pass 1: guard eval (top-down, preorder)
    for _, node in ipairs(nodes) do
        stmts:insert(self:emit_guard_eval(node))
    end

    -- Pass 2: width measure (bottom-up, postorder)
    for i = #nodes, 1, -1 do
        stmts:insert(self:emit_width_measure(nodes[i]))
    end

    -- Pass 3: width resolve (top-down, preorder; floats after flow nodes)
    local i = 1
    while i <= #nodes do
        local node = nodes[i]
        if node.float_slot then
            i = node.subtree_end + 1
        else
            stmts:insert(self:emit_width_resolve(node))
            i = i + 1
        end
    end
    for _, fs in ipairs(self.plan.floats) do
        stmts:insert(self:emit_float_width_resolve(fs))
        local root = nodes[fs.node_index + 1]
        -- width-resolve the float root itself (sets content_w, distributes to children)
        stmts:insert(self:emit_width_resolve(root))
        local j = root.index + 2
        while j <= root.subtree_end do
            local node = nodes[j]
            if node.float_slot then
                j = node.subtree_end + 1
            else
                stmts:insert(self:emit_width_resolve(node))
                j = j + 1
            end
        end
    end

    -- Pass 4: height measure (bottom-up, postorder)
    for i = #nodes, 1, -1 do
        stmts:insert(self:emit_height_measure(nodes[i]))
    end

    -- Pass 5: full layout (top-down, preorder; floats after flow)
    do
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
    end

    -- Pass 6: pixel-snap — round all positions to integer pixels so text
    -- and rects share the same grid.  Positions floor, sizes preserve the
    -- snapped right/bottom edge, clips snap inward.
    local node_count = self.node_count
    return terra([frame])
        escape
            for _, s in ipairs(stmts) do emit(s) end
        end
        for i = 0, [node_count - 1] do
            var x0 = C.floorf([frame].nodes[i].x)
            var y0 = C.floorf([frame].nodes[i].y)
            [frame].nodes[i].w = C.floorf([frame].nodes[i].x + [frame].nodes[i].w + 0.5f) - x0
            [frame].nodes[i].h = C.floorf([frame].nodes[i].y + [frame].nodes[i].h + 0.5f) - y0
            [frame].nodes[i].x = x0
            [frame].nodes[i].y = y0

            var cx0 = C.floorf([frame].nodes[i].content_x)
            var cy0 = C.floorf([frame].nodes[i].content_y)
            [frame].nodes[i].content_w = C.floorf([frame].nodes[i].content_x + [frame].nodes[i].content_w + 0.5f) - cx0
            [frame].nodes[i].content_h = C.floorf([frame].nodes[i].content_y + [frame].nodes[i].content_h + 0.5f) - cy0
            [frame].nodes[i].content_x = cx0
            [frame].nodes[i].content_y = cy0

            [frame].nodes[i].clip_x0 = C.ceilf([frame].nodes[i].clip_x0)
            [frame].nodes[i].clip_y0 = C.ceilf([frame].nodes[i].clip_y0)
            [frame].nodes[i].clip_x1 = C.floorf([frame].nodes[i].clip_x1)
            [frame].nodes[i].clip_y1 = C.floorf([frame].nodes[i].clip_y1)
        end
    end
end

function CompileCtx:compile_hit_test_fn()
    local frame = self.frame_sym
    local nodes = self.plan.nodes
    local stmts = terralib.newlist()

    stmts:insert(quote
        [frame].hit.hot = -1
        [frame].cursor_name = nil
    end)

    for i = #nodes, 1, -1 do
        stmts:insert(nodes[i]:compile_hit(self))
    end

    return terra([frame])
        escape
            for _, s in ipairs(stmts) do emit(s) end
        end
    end
end

function CompileCtx:compile_input_fn()
    local frame = self.frame_sym
    local nodes = self.plan.nodes
    local stmts = terralib.newlist()

    stmts:insert(quote
        [frame].action_node = -1
        [frame].action_name = nil
    end)

    for _, node in ipairs(nodes) do
        local input = self.plan.inputs[node.input_slot + 1]
        stmts:insert(input:compile_input(self, node.index))
    end

    for _, sc in ipairs(self.plan.scroll_controls) do
        stmts:insert(sc:compile_input(self))
    end

    for i = #self.plan.scrolls, 1, -1 do
        stmts:insert(self.plan.scrolls[i]:compile_input(self))
    end

    return terra([frame])
        escape
            for _, s in ipairs(stmts) do emit(s) end
        end
    end
end

function CompileCtx:emit_node_commands(node, stmts)
    if node.clip_slot then
        local clip = self.plan.clips[node.clip_slot + 1]
        stmts:insert(clip:compile_emit_begin(self))
    end

    local paint = self.plan.paints[node.paint_slot + 1]
    stmts:insert(paint:compile_emit(self, node.index))

    if node.text_slot then
        stmts:insert(self.plan.texts[node.text_slot + 1]:compile_emit(self))
    end
    if node.image_slot then
        stmts:insert(self.plan.images[node.image_slot + 1]:compile_emit(self))
    end
    if node.custom_slot then
        stmts:insert(self.plan.customs[node.custom_slot + 1]:compile_emit(self))
    end

    for _, child in ipairs(self:direct_children(node)) do
        self:emit_node_commands(child, stmts)
    end

    if node.clip_slot then
        local clip = self.plan.clips[node.clip_slot + 1]
        stmts:insert(clip:compile_emit_end(self))
    end
end

function CompileCtx:compile_emit_fn()
    local frame = self.frame_sym
    local root = self.plan.nodes[self.plan.root_index + 1]
    local stmts = terralib.newlist()

    stmts:insert(quote
        [frame].draw_seq = 0
        [frame].rect_count = 0
        [frame].border_count = 0
        [frame].text_count = 0
        [frame].image_count = 0
        [frame].scissor_count = 0
        [frame].custom_count = 0
    end)

    self:emit_node_commands(root, stmts)

    return terra([frame])
        escape
            for _, s in ipairs(stmts) do emit(s) end
        end
    end
end

function Plan.Component:compile(ctx)
    local node_count = ctx.node_count
    local init_fn     = terra(frame: &ctx.frame_t)
        frame.draw_seq = 0
        frame.action_node = -1
        frame.action_name = nil
        frame.cursor_name = nil
        frame.text_backend_state = nil
        frame.hit.hot = -1
        frame.hit.active = -1
        frame.hit.focus = -1
        frame.hit.active_offset_x = 0.0f
        frame.hit.active_offset_y = 0.0f
        frame.rect_count = 0
        frame.border_count = 0
        frame.text_count = 0
        frame.image_count = 0
        frame.scissor_count = 0
        frame.custom_count = 0
        for i = 0, [node_count - 1] do
            frame.nodes[i].content_extent_w = 0.0f
            frame.nodes[i].content_extent_h = 0.0f
            frame.nodes[i].scroll_x = 0.0f
            frame.nodes[i].scroll_y = 0.0f
            frame.nodes[i].scroll_need_x = false
            frame.nodes[i].scroll_need_y = false
        end
    end
    local layout_fn   = ctx:compile_layout_fn()
    local hit_test_fn = ctx:compile_hit_test_fn()
    local input_fn    = ctx:compile_input_fn()
    local emit_fn     = ctx:compile_emit_fn()
    local run_fn      = terra(frame: &ctx.frame_t)
        layout_fn(frame)
        hit_test_fn(frame)
        input_fn(frame)
        layout_fn(frame)
        hit_test_fn(frame)
        emit_fn(frame)
    end
    local noop_fn     = terra(frame: &ctx.frame_t) end

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
        `init_fn,
        `layout_fn,
        `input_fn,
        `hit_test_fn,
        `run_fn)

    local stub_q = `noop_fn
    return Kernel.Component(
        self.key,
        runtime_types,
        Kernel.RectStream(RectCmd, stub_q),
        Kernel.BorderStream(BorderCmd, stub_q),
        Kernel.TextStream(TextCmd, stub_q, stub_q),
        Kernel.ImageStream(ImageCmd, stub_q),
        Kernel.ScissorStream(ScissorCmd, stub_q),
        Kernel.CustomStream(CustomCmd, stub_q),
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
M.default_text_backend = DefaultTextBackend
M.text_backend_key = text_backend_key
M.NodeState  = NodeState
M.NodeRect   = NodeState -- compatibility alias with earlier tests/notes
M.InputState = InputState
M.HitState   = HitState
M.RectCmd    = RectCmd
M.BorderCmd  = BorderCmd
M.TextCmd    = TextCmd
M.ImageCmd   = ImageCmd
M.ScissorCmd = ScissorCmd
M.CustomCmd  = CustomCmd
M.TEXT_WRAP_NONE = TEXT_WRAP_NONE
M.TEXT_WRAP_WORDS = TEXT_WRAP_WORDS
M.TEXT_WRAP_NEWLINES = TEXT_WRAP_NEWLINES
M.TEXT_ALIGN_LEFT = TEXT_ALIGN_LEFT
M.TEXT_ALIGN_CENTER = TEXT_ALIGN_CENTER
M.TEXT_ALIGN_RIGHT = TEXT_ALIGN_RIGHT

function M.compile_component(plan_component, opts)
    local ctx = CompileCtx.new(plan_component, opts)
    return plan_component:compile(ctx)
end

return M
