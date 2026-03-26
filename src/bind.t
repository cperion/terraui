-- src/bind.t
-- Decl → Bound phase implementation.
-- Factory: receives types, installs internal ASDL methods, returns module.

return function(types)

local Decl = types.Decl
local Bound = types.Bound
local List = require("terralist")


---------------------------------------------------------------------------
-- BindCtx
---------------------------------------------------------------------------

local BindCtx = {}
BindCtx.__index = BindCtx

local function text_backend_key(opts)
    local tb = opts and opts.text_backend
    if type(tb) == "table" and tb.key ~= nil then
        return tostring(tb.key)
    elseif tb ~= nil then
        return tostring(tb)
    end
    return "default"
end

function BindCtx.new(opts)
    opts = opts or {}
    return setmetatable({
        _param_slots       = {},
        _param_types       = {},
        _state_slots       = {},
        _state_types       = {},
        _widget_defs       = {},
        _theme_defs        = {},
        _theme_stack       = {},
        _part_style_stack  = {},
        _bound_widget_state = nil,
        _next_param        = 0,
        _next_state        = 0,
        _next_node_id      = 0,
        _next_widget_id    = 0,
        _path_stack        = {},
        _named_scopes      = {},
        _widget_frames     = {},
        _override_ids      = {},
        _renderer          = opts.renderer or "default",
        _text_backend      = text_backend_key(opts),
    }, BindCtx)
end

function BindCtx:register_param(name, ty)
    if self._param_slots[name] ~= nil then
        error("duplicate param name: " .. name)
    end
    self._param_slots[name] = self._next_param
    self._param_types[name] = ty
    self._next_param = self._next_param + 1
end

function BindCtx:register_state(name, ty)
    if self._state_slots[name] ~= nil then
        error("duplicate state name: " .. name)
    end
    self._state_slots[name] = self._next_state
    self._state_types[name] = ty
    self._next_state = self._next_state + 1
end

function BindCtx:param_slot(name)
    local slot = self._param_slots[name]
    if slot == nil then error("unknown param: " .. name) end
    return slot
end

function BindCtx:param_type(name)
    local ty = self._param_types[name]
    if ty == nil then error("unknown param: " .. name) end
    return ty
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

function BindCtx:state_type(name)
    local frame = self:current_widget_frame()
    if frame and frame.local_state_types[name] ~= nil then
        return frame.local_state_types[name]
    end
    local ty = self._state_types[name]
    if ty == nil then error("unknown state: " .. name) end
    return ty
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

function BindCtx:register_theme(def)
    if self._theme_defs[def.name] ~= nil then
        error("duplicate theme name: " .. def.name)
    end
    self._theme_defs[def.name] = def
end

function BindCtx:theme_def(name)
    local def = self._theme_defs[name]
    if def == nil then error("unknown theme: " .. tostring(name)) end
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

function BindCtx:push_theme_scope(scope)
    self._theme_stack[#self._theme_stack + 1] = scope
end

function BindCtx:pop_theme_scope()
    self._theme_stack[#self._theme_stack] = nil
end

function BindCtx:push_part_styles(widget_name, part_defs, styles)
    self._part_style_stack[#self._part_style_stack + 1] = {
        widget_name = widget_name,
        part_defs = part_defs,
        styles = styles,
    }
end

function BindCtx:pop_part_styles()
    self._part_style_stack[#self._part_style_stack] = nil
end

function BindCtx:validate_widget_part(name)
    local frame = self._part_style_stack[#self._part_style_stack]
    if frame == nil then
        error("widget part outside widget body: " .. tostring(name))
    end
    if frame.part_defs[name] == nil then
        error("unknown widget part for " .. frame.widget_name .. ": " .. tostring(name))
    end
end

function BindCtx:part_style_patch(name)
    local frame = self._part_style_stack[#self._part_style_stack]
    if frame == nil then return nil end
    return frame.styles[name]
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

local function theme_token_decl(ctx, theme_name, token_name, seen)
    if theme_name == nil then return nil end
    seen = seen or {}
    local key = theme_name .. "\0" .. token_name
    if seen[key] then return nil end
    seen[key] = true

    local def = ctx._theme_defs[theme_name]
    if def == nil then
        error("unknown theme: " .. tostring(theme_name))
    end
    for _, tok in ipairs(def.tokens) do
        if tok.name == token_name then return tok end
    end
    if def.parent ~= nil then
        return theme_token_decl(ctx, def.parent, token_name, seen)
    end
    return nil
end

function BindCtx:resolve_token(name)
    for i = #self._theme_stack, 1, -1 do
        local scope = self._theme_stack[i]
        local override = scope.overrides and scope.overrides[name] or nil
        if override ~= nil then
            return override:bind(self)
        end
        if scope.base_theme ~= nil then
            local tok = theme_token_decl(self, scope.base_theme, name)
            if tok ~= nil then
                return tok.value:bind(self)
            end
        end
    end
    return Bound.EnvSlot("token:" .. name)
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
    self:register_state(scoped_name, decl_state.ty)
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

function BindCtx:push_named_scope(id)
    self._named_scopes[#self._named_scopes + 1] = id
end

function BindCtx:pop_named_scope()
    self._named_scopes[#self._named_scopes] = nil
end

function BindCtx:current_named_scope()
    return self._named_scopes[#self._named_scopes]
end

function BindCtx:resolve_intrinsic(fn_name, arity)
    return fn_name  -- v1: pass through
end

---------------------------------------------------------------------------
-- Id resolution helper (not a schema-declared method)
---------------------------------------------------------------------------

local function is_explicit_path_name(name)
    return type(name) == "string" and name:find("/", 1, true) ~= nil
end

local function current_scope_id(ctx)
    return ctx:current_named_scope()
end

local function scoped_base_and_salt(ctx, base, salt, is_indexed)
    local scope = current_scope_id(ctx)
    if scope == nil or is_explicit_path_name(base) then
        return base, salt
    end
    base = scope.base .. "/" .. base
    if is_indexed then
        if scope.salt ~= 0 then
            error("nested indexed ids inside indexed scopes are not supported without an explicit composed key: " .. base)
        end
        return base, salt
    end
    return base, scope.salt
end

local function resolve_id(decl_id, ctx, local_id, opts)
    opts = opts or {}
    if decl_id.kind == "Auto" then
        return Bound.ResolvedId(
            ctx:path_string() .. "/__auto_" .. local_id, 0)
    elseif decl_id.kind == "Stable" then
        local base, salt = decl_id.name, 0
        if not opts.suppress_scope_prefix then
            base, salt = scoped_base_and_salt(ctx, base, salt, false)
        end
        return Bound.ResolvedId(base, salt)
    elseif decl_id.kind == "Indexed" then
        local bound_idx = decl_id.index:bind(ctx)
        local salt = local_id
        if bound_idx.kind == "ConstNumber" then
            salt = bound_idx.v
        end
        local base = decl_id.name
        if not opts.suppress_scope_prefix then
            base, salt = scoped_base_and_salt(ctx, base, salt, true)
        end
        return Bound.ResolvedId(base, salt)
    else
        error("unknown Decl.Id kind: " .. tostring(decl_id.kind))
    end
end

local function scope_string_from_scope_id(scope)
    if scope == nil then return nil end
    if scope.salt ~= 0 then
        return scope.base .. "/" .. tostring(scope.salt)
    end
    return scope.base
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
        local scope = current_scope_id(ctx)
        if scope ~= nil and not is_explicit_path_name(call.id.name) then
            return scope_string_from_scope_id(scope) .. "/" .. call.id.name
        end
        return call.id.name
    elseif call.id.kind == "Indexed" then
        local bound_idx = call.id.index:bind(ctx)
        local salt = ctx:alloc_widget_id()
        if bound_idx.kind == "ConstNumber" then salt = bound_idx.v end
        local base = call.id.name
        local scope = current_scope_id(ctx)
        if scope ~= nil and not is_explicit_path_name(base) then
            if scope.salt ~= 0 then
                error("nested indexed widget keys inside indexed scopes are not supported without an explicit composed key: " .. base)
            end
            base = scope.base .. "/" .. base
        end
        return base .. "/" .. tostring(salt)
    else
        error("unknown WidgetCall id kind: " .. tostring(call.id.kind))
    end
end

---------------------------------------------------------------------------
-- Decl expression typing helpers
---------------------------------------------------------------------------

local function type_name(ty)
    if ty == Decl.TBool then return "bool"
    elseif ty == Decl.TNumber then return "number"
    elseif ty == Decl.TString then return "string"
    elseif ty == Decl.TColor then return "color"
    elseif ty == Decl.TImage then return "image"
    elseif ty == Decl.TVec2 then return "vec2"
    elseif ty == Decl.TAny then return "any"
    end
    return tostring(ty)
end

local function is_type_compatible(expected, got)
    if expected == nil or got == nil then return true end
    if expected == Decl.TAny then return true end
    if expected == got then return true end
    if expected == Decl.TImage and got == Decl.TString then return true end
    return false
end

local function infer_decl_expr_type(ctx, expr)
    if expr == nil then return nil end
    local k = expr.kind
    if k == "BoolLit" then return Decl.TBool
    elseif k == "NumLit" then return Decl.TNumber
    elseif k == "StringLit" then return Decl.TString
    elseif k == "ColorLit" then return Decl.TColor
    elseif k == "Vec2Lit" then return Decl.TVec2
    elseif k == "ParamRef" then return ctx:param_type(expr.name)
    elseif k == "StateRef" then return ctx:state_type(expr.name)
    elseif k == "WidgetPropRef" then
        local frame = ctx:current_widget_frame()
        return frame and frame.prop_types[expr.name] or nil
    elseif k == "TokenRef" then
        return ctx:token_type(expr.name)
    elseif k == "Unary" then
        local rhs = infer_decl_expr_type(ctx, expr.rhs)
        if expr.op == "not" and rhs == Decl.TBool then return Decl.TBool end
        if expr.op == "-" and rhs == Decl.TNumber then return Decl.TNumber end
        return nil
    elseif k == "Binary" then
        local lhs = infer_decl_expr_type(ctx, expr.lhs)
        local rhs = infer_decl_expr_type(ctx, expr.rhs)
        if lhs == nil or rhs == nil then return nil end
        if (expr.op == "+" or expr.op == "-" or expr.op == "*" or expr.op == "/")
            and lhs == Decl.TNumber and rhs == Decl.TNumber then
            return Decl.TNumber
        end
        if (expr.op == "and" or expr.op == "or")
            and lhs == Decl.TBool and rhs == Decl.TBool then
            return Decl.TBool
        end
        if expr.op == "==" or expr.op == "!=" or expr.op == "<" or expr.op == ">" or expr.op == "<=" or expr.op == ">=" then
            return Decl.TBool
        end
        return nil
    elseif k == "Select" then
        local y = infer_decl_expr_type(ctx, expr.yes)
        local n = infer_decl_expr_type(ctx, expr.no)
        if y ~= nil and n ~= nil and (y == n or is_type_compatible(y, n) or is_type_compatible(n, y)) then
            return y
        end
        return nil
    else
        return nil
    end
end

function BindCtx:token_type(name)
    for i = #self._theme_stack, 1, -1 do
        local scope = self._theme_stack[i]
        local override = scope.overrides and scope.overrides[name] or nil
        if override ~= nil then
            return infer_decl_expr_type(self, override)
        end
        if scope.base_theme ~= nil then
            local tok = theme_token_decl(self, scope.base_theme, name)
            if tok ~= nil then return tok.ty end
        end
    end
    return nil
end

local function assert_expr_type_compatible(ctx, expr, expected, label)
    local got = infer_decl_expr_type(ctx, expr)
    if got ~= nil and not is_type_compatible(expected, got) then
        error(label .. " expected " .. type_name(expected) .. ", got " .. type_name(got))
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

function Decl.TokenRef:bind(ctx)
    return ctx:resolve_token(self.name)
end

function Decl.EnvRef:bind(ctx)
    return Bound.EnvSlot(self.name)
end

function Decl.ScrollMetric:bind(ctx)
    return Bound.ScrollMetric(
        resolve_id(self.id, ctx, -1),
        self.metric)
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
        self.vertical)
end

function Decl.Scroll:bind(ctx)
    return Bound.Scroll(
        self.horizontal,
        self.vertical)
end

function Decl.ScrollControl:bind(ctx)
    return Bound.ScrollControl(
        resolve_id(self.target, ctx, -1),
        self.axis,
        self.kind)
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

local function bind_border_with_patch(border, patch, ctx)
    local p = patch and patch.border or nil
    local src = p or border
    if src == nil then return nil end
    return Bound.Border(
        src.left:bind(ctx),
        src.top:bind(ctx),
        src.right:bind(ctx),
        src.bottom:bind(ctx),
        src.between_children:bind(ctx),
        src.color:bind(ctx))
end

local function bind_radius_with_patch(radius, patch, ctx)
    local p = patch and patch.radius or nil
    local src = p or radius
    if src == nil then return nil end
    return Bound.CornerRadius(
        src.top_left:bind(ctx),
        src.top_right:bind(ctx),
        src.bottom_right:bind(ctx),
        src.bottom_left:bind(ctx))
end

local function bind_decor_with_patch(decor, patch, ctx)
    local background = decor.background
    local opacity = decor.opacity
    if patch ~= nil then
        if patch.background ~= nil then background = patch.background end
        if patch.opacity ~= nil then opacity = patch.opacity end
    end
    return Bound.Decor(
        background and background:bind(ctx) or nil,
        bind_border_with_patch(decor.border, patch, ctx),
        bind_radius_with_patch(decor.radius, patch, ctx),
        opacity and opacity:bind(ctx) or nil)
end

local function bind_text_style_with_patch(style, patch, ctx)
    local color = style.color
    local font_id = style.font_id
    local font_size = style.font_size
    local letter_spacing = style.letter_spacing
    local line_height = style.line_height
    local wrap = style.wrap
    local align = style.align
    if patch ~= nil then
        if patch.text_color ~= nil then color = patch.text_color end
        if patch.font_id ~= nil then font_id = patch.font_id end
        if patch.font_size ~= nil then font_size = patch.font_size end
        if patch.letter_spacing ~= nil then letter_spacing = patch.letter_spacing end
        if patch.line_height ~= nil then line_height = patch.line_height end
        if patch.wrap ~= nil then wrap = patch.wrap end
        if patch.text_align ~= nil then align = patch.text_align end
    end
    return Bound.TextStyle(
        color:bind(ctx),
        font_id:bind(ctx),
        font_size:bind(ctx),
        letter_spacing:bind(ctx),
        line_height:bind(ctx),
        wrap,
        align)
end

local function bind_leaf_with_patch(leaf, patch, ctx)
    if leaf == nil then return nil end
    if leaf.kind == "Text" then
        local tl = leaf.value
        return Bound.Text(Bound.TextLeaf(
            tl.content:bind(ctx),
            bind_text_style_with_patch(tl.style, patch, ctx)))
    elseif leaf.kind == "Image" then
        local il = leaf.value
        local tint = il.tint
        if patch ~= nil and patch.image_tint ~= nil then tint = patch.image_tint end
        return Bound.Image(Bound.ImageLeaf(
            il.image_id:bind(ctx),
            tint:bind(ctx),
            il.fit))
    elseif leaf.kind == "Custom" then
        return leaf:bind(ctx)
    end
    error("unknown Decl.Leaf kind: " .. tostring(leaf.kind))
end

local function push_decl_theme_scope(ctx, scope)
    local overrides = {}
    if scope ~= nil then
        for _, ov in ipairs(scope.overrides) do
            overrides[ov.name] = ov.value
            if scope.base_theme ~= nil then
                local tok = theme_token_decl(ctx, scope.base_theme, ov.name)
                if tok ~= nil then
                    assert_expr_type_compatible(ctx, ov.value, tok.ty,
                        "theme override type mismatch for token " .. ov.name)
                end
            end
        end
    end
    ctx:push_theme_scope({
        base_theme = scope and scope.base_theme or nil,
        overrides = overrides,
    })
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
            local theme_scope = child.value.theme_scope
            if theme_scope ~= nil then
                push_decl_theme_scope(ctx, theme_scope)
            end
            out:insert(ctx:bind_widget_call(child.value))
            if theme_scope ~= nil then
                ctx:pop_theme_scope()
            end
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

    local part_defs = {}
    for _, p in ipairs(def.parts) do
        if part_defs[p.name] ~= nil then
            error("duplicate widget part in def " .. def.name .. ": " .. p.name)
        end
        part_defs[p.name] = true
    end

    local props = {}
    for _, arg in ipairs(call.props) do
        if props[arg.name] ~= nil then
            error("duplicate widget prop arg for " .. call.name .. ": " .. arg.name)
        end
        if prop_defs[arg.name] == nil then
            error("unknown widget prop for " .. call.name .. ": " .. arg.name)
        end
        assert_expr_type_compatible(self, arg.value, prop_defs[arg.name].ty,
            "widget prop type mismatch for " .. call.name .. ": " .. arg.name)
        props[arg.name] = arg.value
    end
    for name, p in pairs(prop_defs) do
        if props[name] == nil then
            if p.default ~= nil then
                assert_expr_type_compatible(self, p.default, p.ty,
                    "widget prop default type mismatch for " .. def.name .. ": " .. name)
                props[name] = p.default
            else
                error("missing widget prop for " .. call.name .. ": " .. name)
            end
        end
    end

    local styles = {}
    for _, arg in ipairs(call.styles) do
        if styles[arg.name] ~= nil then
            error("duplicate widget style arg for " .. call.name .. ": " .. arg.name)
        end
        if part_defs[arg.name] == nil then
            error("unknown widget part for " .. call.name .. ": " .. arg.name)
        end
        styles[arg.name] = arg.patch
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

    local prop_types = {}
    for name, p in pairs(prop_defs) do prop_types[name] = p.ty end
    local local_state_types = {}
    for _, s in ipairs(def.state) do local_state_types[s.name] = s.ty end

    local frame = {
        name = call.name,
        scope = scope,
        props = props,
        prop_types = prop_types,
        slots = slots,
        local_state_slots = local_state_slots,
        local_state_names = local_state_names,
        local_state_types = local_state_types,
        _resolving = {},
    }

    self:push_widget_frame(frame)
    self:push_part_styles(call.name, part_defs, styles)
    for _, s in ipairs(def.state) do
        if s.initial ~= nil then
            assert_expr_type_compatible(self, s.initial, s.ty,
                "widget state initial type mismatch for " .. def.name .. ": " .. s.name)
        end
        local initial = s.initial and s.initial:bind(self) or nil
        self._bound_widget_state:insert(Bound.StateSlot(
            local_state_names[s.name], s.ty, local_state_slots[s.name], initial))
    end
    local bound = def.root:bind(self)
    self:pop_part_styles()
    self:pop_widget_frame()
    return bound
end

---------------------------------------------------------------------------
-- Node:bind
---------------------------------------------------------------------------

function Decl.Node:bind(ctx)
    local local_id = ctx:alloc_node_id()
    local override_id = ctx:take_override_id()
    local id_mode = override_id ~= nil and "key" or self.id_mode or "auto"
    local stable_id = resolve_id(override_id or self.id, ctx, local_id, {
        suppress_scope_prefix = override_id ~= nil,
    })

    ctx:push_path(stable_id.base)
    if id_mode == "key" then
        ctx:push_named_scope(stable_id)
    end
    if self.theme_scope ~= nil then
        push_decl_theme_scope(ctx, self.theme_scope)
    end

    local patch = nil
    if self.part ~= nil then
        ctx:validate_widget_part(self.part)
        patch = ctx:part_style_patch(self.part)
    end

    local visibility  = self.visibility:bind(ctx)
    local layout      = self.layout:bind(ctx)
    local decor       = bind_decor_with_patch(self.decor, patch, ctx)
    local clip        = self.clip and self.clip:bind(ctx) or nil
    local scroll      = self.scroll and self.scroll:bind(ctx) or nil
    local scroll_control = self.scroll_control and self.scroll_control:bind(ctx) or nil
    local floating    = self.floating and self.floating:bind(ctx) or nil
    local input       = self.input:bind(ctx)
    local aspect_ratio = self.aspect_ratio and self.aspect_ratio:bind(ctx) or nil
    local leaf        = bind_leaf_with_patch(self.leaf, patch, ctx)
    local children    = bind_children(ctx, self.children)

    if self.theme_scope ~= nil then
        ctx:pop_theme_scope()
    end
    if id_mode == "key" then
        ctx:pop_named_scope()
    end
    ctx:pop_path()

    return Bound.Node(
        local_id, stable_id, visibility, layout, decor,
        clip, scroll, scroll_control, floating, input, aspect_ratio, leaf, children)
end

---------------------------------------------------------------------------
-- Param:bind, StateSlot:bind
---------------------------------------------------------------------------

function Decl.Param:bind(ctx)
    if self.default ~= nil then
        assert_expr_type_compatible(ctx, self.default, self.ty,
            "param default type mismatch for " .. self.name)
    end
    return Bound.Param(self.name, self.ty, ctx:param_slot(self.name))
end

function Decl.StateSlot:bind(ctx)
    if self.initial ~= nil then
        assert_expr_type_compatible(ctx, self.initial, self.ty,
            "state initial type mismatch for " .. self.name)
    end
    local initial = self.initial and self.initial:bind(ctx) or nil
    return Bound.StateSlot(
        self.name, self.ty, ctx:state_slot(self.name), initial)
end

---------------------------------------------------------------------------
-- Component:bind
---------------------------------------------------------------------------

function Decl.Component:bind_impl(ctx)
    -- Register slots before binding anything
    ctx._bound_widget_state = List()
    for _, p in ipairs(self.params) do ctx:register_param(p.name, p.ty) end
    for _, s in ipairs(self.state) do ctx:register_state(s.name, s.ty) end
    for _, t in ipairs(self.themes) do ctx:register_theme(t) end
    for _, w in ipairs(self.widgets) do ctx:register_widget(w) end

    for _, t in ipairs(self.themes) do
        local seen = {}
        for _, tok in ipairs(t.tokens) do
            if seen[tok.name] then
                error("duplicate theme token in theme " .. t.name .. ": " .. tok.name)
            end
            seen[tok.name] = true
            assert_expr_type_compatible(ctx, tok.value, tok.ty,
                "theme token type mismatch for " .. t.name .. ": " .. tok.name)
        end
        if t.parent ~= nil then
            local walk = t.parent
            local cycle_seen = { [t.name] = true }
            while walk ~= nil do
                if cycle_seen[walk] then
                    error("cyclic theme parent chain involving: " .. t.name)
                end
                cycle_seen[walk] = true
                local parent = ctx._theme_defs[walk]
                if parent == nil then
                    error("unknown parent theme for " .. t.name .. ": " .. walk)
                end
                walk = parent.parent
            end
        end
    end

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

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local M = {}

-- Schema boundary: explicit params, no opaque ctx
function M.boundary(self, renderer, text_backend_key)
    local ctx = BindCtx.new({
        renderer = renderer or "default",
        text_backend = text_backend_key or "default",
    })
    return self:bind_impl(ctx)
end

-- Convenience for non-schema callers
function M.bind_component(decl_component, opts)
    opts = opts or {}
    local renderer = opts.renderer or "default"
    local tb = opts.text_backend
    local tb_key
    if type(tb) == "table" and tb.key ~= nil then
        tb_key = tostring(tb.key)
    elseif tb ~= nil then
        tb_key = tostring(tb)
    else
        tb_key = "default"
    end
    local ctx = BindCtx.new({ renderer = renderer, text_backend = tb_key })
    return decl_component:bind_impl(ctx)
end

M.BindCtx = BindCtx

return M

end -- factory
