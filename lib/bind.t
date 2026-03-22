-- lib/bind.t
-- Decl -> Bound phase transition
--
-- Installs :bind() methods on Decl ASDL types.
-- Provides BindCtx and bind_component() convenience.

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound

---------------------------------------------------------------------------
-- BindCtx
---------------------------------------------------------------------------

local BindCtx = {}
BindCtx.__index = BindCtx

function BindCtx.new(opts)
    opts = opts or {}
    return setmetatable({
        _param_slots   = {},
        _state_slots   = {},
        _next_param    = 0,
        _next_state    = 0,
        _next_node_id  = 0,
        _path_stack    = {},
        _renderer      = opts.renderer or "default",
        _text_backend  = opts.text_backend or "default",
    }, BindCtx)
end

function BindCtx:register_param(name)
    if self._param_slots[name] ~= nil then
        error("duplicate param name: " .. name)
    end
    self._param_slots[name] = self._next_param
    self._next_param = self._next_param + 1
end

function BindCtx:register_state(name)
    if self._state_slots[name] ~= nil then
        error("duplicate state name: " .. name)
    end
    self._state_slots[name] = self._next_state
    self._next_state = self._next_state + 1
end

function BindCtx:param_slot(name)
    local slot = self._param_slots[name]
    if slot == nil then error("unknown param: " .. name) end
    return slot
end

function BindCtx:state_slot(name)
    local slot = self._state_slots[name]
    if slot == nil then error("unknown state: " .. name) end
    return slot
end

function BindCtx:alloc_node_id()
    local id = self._next_node_id
    self._next_node_id = self._next_node_id + 1
    return id
end

function BindCtx:push_path(segment)
    self._path_stack[#self._path_stack + 1] = segment
end

function BindCtx:pop_path()
    self._path_stack[#self._path_stack] = nil
end

function BindCtx:path_string()
    return table.concat(self._path_stack, "/")
end

function BindCtx:resolve_intrinsic(fn_name, arity)
    return fn_name  -- v1: pass through
end

---------------------------------------------------------------------------
-- Id resolution helper (not a schema-declared method)
---------------------------------------------------------------------------

local function resolve_id(decl_id, ctx, local_id)
    if decl_id.kind == "Auto" then
        return Bound.ResolvedId(
            ctx:path_string() .. "/__auto_" .. local_id, 0)
    elseif decl_id.kind == "Stable" then
        return Bound.ResolvedId(decl_id.name, 0)
    elseif decl_id.kind == "Indexed" then
        local bound_idx = decl_id.index:bind(ctx)
        local salt = local_id
        if bound_idx.kind == "ConstNumber" then
            salt = bound_idx.v
        end
        return Bound.ResolvedId(decl_id.name, salt)
    else
        error("unknown Decl.Id kind: " .. tostring(decl_id.kind))
    end
end

---------------------------------------------------------------------------
-- Expr:bind   (Decl.Expr -> Bound.Value)
---------------------------------------------------------------------------

function Decl.Expr:bind(ctx)
    error("Decl.Expr:bind not implemented for " .. tostring(self.kind))
end

function Decl.BoolLit:bind(ctx)
    return Bound.ConstBool(self.v)
end

function Decl.NumLit:bind(ctx)
    return Bound.ConstNumber(self.v)
end

function Decl.StringLit:bind(ctx)
    return Bound.ConstString(self.v)
end

function Decl.ColorLit:bind(ctx)
    return Bound.ConstColor(self.r, self.g, self.b, self.a)
end

function Decl.Vec2Lit:bind(ctx)
    return Bound.ConstVec2(self.x, self.y)
end

function Decl.ParamRef:bind(ctx)
    return Bound.ParamSlot(ctx:param_slot(self.name))
end

function Decl.StateRef:bind(ctx)
    return Bound.StateSlotRef(ctx:state_slot(self.name))
end

function Decl.ThemeRef:bind(ctx)
    -- v1: theme refs become env slots with a prefix
    return Bound.EnvSlot("theme:" .. self.name)
end

function Decl.EnvRef:bind(ctx)
    return Bound.EnvSlot(self.name)
end

function Decl.Unary:bind(ctx)
    return Bound.Unary(self.op, self.rhs:bind(ctx))
end

function Decl.Binary:bind(ctx)
    return Bound.Binary(self.op, self.lhs:bind(ctx), self.rhs:bind(ctx))
end

function Decl.Select:bind(ctx)
    return Bound.Select(
        self.cond:bind(ctx), self.yes:bind(ctx), self.no:bind(ctx))
end

function Decl.Call:bind(ctx)
    local bound_args = List()
    for _, a in ipairs(self.args) do
        bound_args:insert(a:bind(ctx))
    end
    return Bound.Intrinsic(
        ctx:resolve_intrinsic(self.fn, #self.args), bound_args)
end

---------------------------------------------------------------------------
-- Size:bind   (Decl.Size -> Bound.Size)
---------------------------------------------------------------------------

function Decl.Size:bind(ctx)
    error("Decl.Size:bind not implemented for " .. tostring(self.kind))
end

function Decl.Fit:bind(ctx)
    return Bound.Fit(
        self.min and self.min:bind(ctx) or nil,
        self.max and self.max:bind(ctx) or nil)
end

function Decl.Grow:bind(ctx)
    return Bound.Grow(
        self.min and self.min:bind(ctx) or nil,
        self.max and self.max:bind(ctx) or nil)
end

function Decl.Fixed:bind(ctx)
    return Bound.Fixed(self.value:bind(ctx))
end

function Decl.Percent:bind(ctx)
    return Bound.Percent(self.value:bind(ctx))
end

---------------------------------------------------------------------------
-- Leaf:bind   (Decl.Leaf -> Bound.Leaf)
---------------------------------------------------------------------------

function Decl.Leaf:bind(ctx)
    error("Decl.Leaf:bind not implemented for " .. tostring(self.kind))
end

function Decl.Text:bind(ctx)
    return Bound.Text(self.value:bind(ctx))
end

function Decl.Image:bind(ctx)
    return Bound.Image(self.value:bind(ctx))
end

function Decl.Custom:bind(ctx)
    return Bound.Custom(self.value:bind(ctx))
end

---------------------------------------------------------------------------
-- Leaf sub-records
---------------------------------------------------------------------------

function Decl.TextLeaf:bind(ctx)
    return Bound.TextLeaf(self.content:bind(ctx), self.style:bind(ctx))
end

function Decl.TextStyle:bind(ctx)
    return Bound.TextStyle(
        self.color:bind(ctx),
        self.font_id:bind(ctx),
        self.font_size:bind(ctx),
        self.letter_spacing:bind(ctx),
        self.line_height:bind(ctx),
        self.wrap,
        self.align)
end

function Decl.ImageLeaf:bind(ctx)
    return Bound.ImageLeaf(
        self.image_id:bind(ctx),
        self.tint:bind(ctx),
        self.fit)
end

function Decl.CustomLeaf:bind(ctx)
    return Bound.CustomLeaf(
        self.kind,
        self.payload and self.payload:bind(ctx) or nil)
end

---------------------------------------------------------------------------
-- Record bind methods
---------------------------------------------------------------------------

function Decl.Visibility:bind(ctx)
    return Bound.Visibility(
        self.visible_when and self.visible_when:bind(ctx) or nil,
        self.enabled_when and self.enabled_when:bind(ctx) or nil)
end

function Decl.Layout:bind(ctx)
    return Bound.Layout(
        self.axis,
        self.width:bind(ctx),
        self.height:bind(ctx),
        self.padding:bind(ctx),
        self.gap:bind(ctx),
        self.align_x,
        self.align_y)
end

function Decl.Padding:bind(ctx)
    return Bound.Padding(
        self.left:bind(ctx),
        self.top:bind(ctx),
        self.right:bind(ctx),
        self.bottom:bind(ctx))
end

function Decl.Decor:bind(ctx)
    return Bound.Decor(
        self.background and self.background:bind(ctx) or nil,
        self.border and self.border:bind(ctx) or nil,
        self.radius and self.radius:bind(ctx) or nil,
        self.opacity and self.opacity:bind(ctx) or nil)
end

function Decl.Border:bind(ctx)
    return Bound.Border(
        self.left:bind(ctx),
        self.top:bind(ctx),
        self.right:bind(ctx),
        self.bottom:bind(ctx),
        self.between_children:bind(ctx),
        self.color:bind(ctx))
end

function Decl.CornerRadius:bind(ctx)
    return Bound.CornerRadius(
        self.top_left:bind(ctx),
        self.top_right:bind(ctx),
        self.bottom_right:bind(ctx),
        self.bottom_left:bind(ctx))
end

function Decl.Clip:bind(ctx)
    return Bound.Clip(
        self.horizontal,
        self.vertical,
        self.child_offset_x and self.child_offset_x:bind(ctx) or nil,
        self.child_offset_y and self.child_offset_y:bind(ctx) or nil)
end

function Decl.Floating:bind(ctx)
    local target
    if self.target.kind == "FloatParent" then
        target = Bound.FloatParent
    elseif self.target.kind == "FloatById" then
        local rid = resolve_id(self.target.id, ctx, -1)
        target = Bound.FloatByStableId(rid)
    else
        error("unknown FloatTarget kind: " .. tostring(self.target.kind))
    end
    return Bound.Floating(
        target,
        self.element_point,
        self.parent_point,
        self.offset_x:bind(ctx),
        self.offset_y:bind(ctx),
        self.expand_w:bind(ctx),
        self.expand_h:bind(ctx),
        self.z_index:bind(ctx),
        self.pointer_capture)
end

function Decl.Input:bind(ctx)
    return Bound.Input(
        self.hover,
        self.press,
        self.focus,
        self.wheel,
        self.cursor,
        self.action)
end

---------------------------------------------------------------------------
-- Node:bind
---------------------------------------------------------------------------

function Decl.Node:bind(ctx)
    local local_id = ctx:alloc_node_id()
    local stable_id = resolve_id(self.id, ctx, local_id)

    ctx:push_path(stable_id.base)

    local visibility  = self.visibility:bind(ctx)
    local layout      = self.layout:bind(ctx)
    local decor       = self.decor:bind(ctx)
    local clip        = self.clip and self.clip:bind(ctx) or nil
    local floating    = self.floating and self.floating:bind(ctx) or nil
    local input       = self.input:bind(ctx)
    local aspect_ratio = self.aspect_ratio
                         and self.aspect_ratio:bind(ctx) or nil
    local leaf        = self.leaf and self.leaf:bind(ctx) or nil

    local children = List()
    for _, child in ipairs(self.children) do
        children:insert(child:bind(ctx))
    end

    ctx:pop_path()

    return Bound.Node(
        local_id, stable_id, visibility, layout, decor,
        clip, floating, input, aspect_ratio, leaf, children)
end

---------------------------------------------------------------------------
-- Param:bind, StateSlot:bind
---------------------------------------------------------------------------

function Decl.Param:bind(ctx)
    return Bound.Param(self.name, self.ty, ctx:param_slot(self.name))
end

function Decl.StateSlot:bind(ctx)
    local initial = self.initial and self.initial:bind(ctx) or nil
    return Bound.StateSlot(
        self.name, self.ty, ctx:state_slot(self.name), initial)
end

---------------------------------------------------------------------------
-- Component:bind
---------------------------------------------------------------------------

function Decl.Component:bind(ctx)
    -- Register slots before binding anything
    for _, p in ipairs(self.params) do ctx:register_param(p.name) end
    for _, s in ipairs(self.state) do ctx:register_state(s.name) end

    local bound_params = List()
    for _, p in ipairs(self.params) do
        bound_params:insert(p:bind(ctx))
    end

    local bound_state = List()
    for _, s in ipairs(self.state) do
        bound_state:insert(s:bind(ctx))
    end

    local bound_root = self.root:bind(ctx)

    local key = Bound.SpecializationKey(
        ctx._renderer,
        ctx._text_backend,
        bound_params,
        bound_state,
        bound_root)

    return Bound.Component(
        self.name, bound_params, bound_state, key, bound_root)
end

---------------------------------------------------------------------------
-- Public module
---------------------------------------------------------------------------

local M = {}

M.BindCtx = BindCtx

function M.bind_component(decl_component, opts)
    local ctx = BindCtx.new(opts)
    return decl_component:bind(ctx)
end

return M
