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
        _param_slots       = {},
        _state_slots       = {},
        _widget_defs       = {},
        _bound_widget_state = nil,
        _next_param        = 0,
        _next_state        = 0,
        _next_node_id      = 0,
        _next_widget_id    = 0,
        _path_stack        = {},
        _widget_frames     = {},
        _override_ids      = {},
        _renderer          = opts.renderer or "default",
        _text_backend      = opts.text_backend or "default",
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
    local frame = self:current_widget_frame()
    if frame and frame.local_state_slots[name] ~= nil then
        return frame.local_state_slots[name]
    end
    local slot = self._state_slots[name]
    if slot == nil then error("unknown state: " .. name) end
    return slot
end

function BindCtx:alloc_node_id()
    local id = self._next_node_id
    self._next_node_id = self._next_node_id + 1
    return id
end

function BindCtx:alloc_widget_id()
    local id = self._next_widget_id
    self._next_widget_id = self._next_widget_id + 1
    return id
end

function BindCtx:register_widget(def)
    if self._widget_defs[def.name] ~= nil then
        error("duplicate widget name: " .. def.name)
    end
    self._widget_defs[def.name] = def
end

function BindCtx:widget_def(name)
    local def = self._widget_defs[name]
    if def == nil then error("unknown widget: " .. name) end
    return def
end

function BindCtx:current_widget_frame()
    return self._widget_frames[#self._widget_frames]
end

function BindCtx:push_widget_frame(frame)
    self._widget_frames[#self._widget_frames + 1] = frame
end

function BindCtx:pop_widget_frame()
    self._widget_frames[#self._widget_frames] = nil
end

function BindCtx:push_override_id(id)
    self._override_ids[#self._override_ids + 1] = id
end

function BindCtx:take_override_id()
    local n = #self._override_ids
    if n == 0 then return nil end
    local id = self._override_ids[n]
    self._override_ids[n] = nil
    return id
end

function BindCtx:widget_scope_string()
    local frame = self:current_widget_frame()
    return frame and frame.scope or nil
end

function BindCtx:resolve_widget_prop(name)
    local frame = self:current_widget_frame()
    if frame == nil then
        error("WidgetPropRef outside widget body: " .. name)
    end
    local expr = frame.props[name]
    if expr == nil then
        error("unknown widget prop: " .. name)
    end
    if frame._resolving[name] then
        error("cyclic widget prop expansion: " .. name)
    end
    frame._resolving[name] = true
    local ok, result = pcall(function() return expr:bind(self) end)
    frame._resolving[name] = nil
    if not ok then error(result) end
    return result
end

function BindCtx:resolve_slot_children(name)
    local frame = self:current_widget_frame()
    if frame == nil then
        error("SlotRef outside widget body: " .. name)
    end
    local children = frame.slots[name]
    if children == nil then
        error("unknown widget slot: " .. name)
    end
    return children
end

function BindCtx:register_widget_state_decl(scope, decl_state)
    local scoped_name = scope .. "/" .. decl_state.name
    self:register_state(scoped_name)
    local slot = self._state_slots[scoped_name]
    return scoped_name, slot
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

local function widget_prefix(ctx)
    local scope = ctx:widget_scope_string()
    if scope == nil or scope == "" then return "" end
    return scope .. "/"
end

local function resolve_id(decl_id, ctx, local_id, opts)
    opts = opts or {}
    if decl_id.kind == "Auto" then
        return Bound.ResolvedId(
            ctx:path_string() .. "/__auto_" .. local_id, 0)
    elseif decl_id.kind == "Stable" then
        local base = decl_id.name
        if not opts.suppress_widget_prefix then
            base = widget_prefix(ctx) .. base
        end
        return Bound.ResolvedId(base, 0)
    elseif decl_id.kind == "Indexed" then
        local bound_idx = decl_id.index:bind(ctx)
        local salt = local_id
        if bound_idx.kind == "ConstNumber" then
            salt = bound_idx.v
        end
        local base = decl_id.name
        if not opts.suppress_widget_prefix then
            base = widget_prefix(ctx) .. base
        end
        return Bound.ResolvedId(base, salt)
    else
        error("unknown Decl.Id kind: " .. tostring(decl_id.kind))
    end
end

local function widget_scope_from_id(call, ctx)
    if call.id == nil then
        local base = "__widget_" .. call.name .. "_" .. ctx:alloc_widget_id()
        local path = ctx:path_string()
        if path ~= "" then return path .. "/" .. base end
        return base
    end

    if call.id.kind == "Auto" then
        local base = "__widget_" .. call.name .. "_" .. ctx:alloc_widget_id()
        local path = ctx:path_string()
        if path ~= "" then return path .. "/" .. base end
        return base
    elseif call.id.kind == "Stable" then
        return call.id.name
    elseif call.id.kind == "Indexed" then
        local bound_idx = call.id.index:bind(ctx)
        local salt = ctx:alloc_widget_id()
        if bound_idx.kind == "ConstNumber" then salt = bound_idx.v end
        return call.id.name .. "/" .. tostring(salt)
    else
        error("unknown WidgetCall id kind: " .. tostring(call.id.kind))
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

function Decl.WidgetPropRef:bind(ctx)
    return ctx:resolve_widget_prop(self.name)
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
-- Child/widget elaboration helpers
---------------------------------------------------------------------------

local function bind_children(ctx, decl_children)
    local out = List()
    for _, child in ipairs(decl_children) do
        if child.kind == "NodeChild" then
            out:insert(child.value:bind(ctx))
        elseif child.kind == "WidgetChild" then
            out:insert(ctx:bind_widget_call(child.value))
        elseif child.kind == "SlotRef" then
            local slot_children = ctx:resolve_slot_children(child.name)
            local bound = bind_children(ctx, slot_children)
            for _, node in ipairs(bound) do out:insert(node) end
        else
            error("unknown Decl.Child kind: " .. tostring(child.kind))
        end
    end
    return out
end

function BindCtx:bind_widget_call(call)
    local def = self:widget_def(call.name)

    for _, frame in ipairs(self._widget_frames) do
        if frame.name == call.name then
            error("recursive widget expansion: " .. call.name)
        end
    end

    local prop_defs = {}
    for _, p in ipairs(def.props) do
        if prop_defs[p.name] ~= nil then
            error("duplicate widget prop in def " .. def.name .. ": " .. p.name)
        end
        prop_defs[p.name] = p
    end

    local slot_defs = {}
    for _, s in ipairs(def.slots) do
        if slot_defs[s.name] ~= nil then
            error("duplicate widget slot in def " .. def.name .. ": " .. s.name)
        end
        slot_defs[s.name] = true
    end
    slot_defs.children = slot_defs.children or false

    local state_defs = {}
    for _, s in ipairs(def.state) do
        if state_defs[s.name] ~= nil then
            error("duplicate widget state in def " .. def.name .. ": " .. s.name)
        end
        state_defs[s.name] = s
    end

    local props = {}
    for _, arg in ipairs(call.props) do
        if props[arg.name] ~= nil then
            error("duplicate widget prop arg for " .. call.name .. ": " .. arg.name)
        end
        if prop_defs[arg.name] == nil then
            error("unknown widget prop for " .. call.name .. ": " .. arg.name)
        end
        props[arg.name] = arg.value
    end
    for name, p in pairs(prop_defs) do
        if props[name] == nil then
            if p.default ~= nil then
                props[name] = p.default
            else
                error("missing widget prop for " .. call.name .. ": " .. name)
            end
        end
    end

    local slots = {}
    local slot_seen = {}
    for name, _ in pairs(slot_defs) do
        slots[name] = List()
    end
    for _, arg in ipairs(call.slots) do
        if slots[arg.name] == nil then
            error("unknown widget slot for " .. call.name .. ": " .. arg.name)
        end
        if slot_seen[arg.name] then
            error("duplicate widget slot arg for " .. call.name .. ": " .. arg.name)
        end
        slot_seen[arg.name] = true
        slots[arg.name] = arg.children
    end

    local scope = widget_scope_from_id(call, self)
    local local_state_slots = {}
    local local_state_names = {}
    for _, s in ipairs(def.state) do
        local scoped_name, slot = self:register_widget_state_decl(scope, s)
        local_state_slots[s.name] = slot
        local_state_names[s.name] = scoped_name
    end

    if call.id ~= nil then
        self:push_override_id(call.id)
    end

    local frame = {
        name = call.name,
        scope = scope,
        props = props,
        slots = slots,
        local_state_slots = local_state_slots,
        local_state_names = local_state_names,
        _resolving = {},
    }

    self:push_widget_frame(frame)
    for _, s in ipairs(def.state) do
        local initial = s.initial and s.initial:bind(self) or nil
        self._bound_widget_state:insert(Bound.StateSlot(
            local_state_names[s.name], s.ty, local_state_slots[s.name], initial))
    end
    local bound = def.root:bind(self)
    self:pop_widget_frame()
    return bound
end

---------------------------------------------------------------------------
-- Node:bind
---------------------------------------------------------------------------

function Decl.Node:bind(ctx)
    local local_id = ctx:alloc_node_id()
    local override_id = ctx:take_override_id()
    local stable_id = resolve_id(override_id or self.id, ctx, local_id, {
        suppress_widget_prefix = override_id ~= nil,
    })

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
    local children    = bind_children(ctx, self.children)

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
    ctx._bound_widget_state = List()
    for _, p in ipairs(self.params) do ctx:register_param(p.name) end
    for _, s in ipairs(self.state) do ctx:register_state(s.name) end
    for _, w in ipairs(self.widgets) do ctx:register_widget(w) end

    local bound_params = List()
    for _, p in ipairs(self.params) do
        bound_params:insert(p:bind(ctx))
    end

    local bound_state = List()
    for _, s in ipairs(self.state) do
        bound_state:insert(s:bind(ctx))
    end

    local bound_root = self.root:bind(ctx)
    for _, s in ipairs(ctx._bound_widget_state) do
        bound_state:insert(s)
    end

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
