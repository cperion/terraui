-- lib/dsl.t
-- Declarative authoring DSL lowering directly into Decl.* values.

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local Decl = TerraUI.types.Decl

local M = {}

local function is_decl_expr(v)
    return type(v) == "table" and Decl.Expr:isclassof(v)
end

local function is_decl_size(v)
    return type(v) == "table" and Decl.Size:isclassof(v)
end

local function is_decl_id(v)
    return type(v) == "table" and Decl.Id:isclassof(v)
end

local function is_decl_node(v)
    return type(v) == "table" and Decl.Node:isclassof(v)
end

local function is_decl_scroll(v)
    return type(v) == "table" and Decl.Scroll:isclassof(v)
end

local function is_decl_scroll_control(v)
    return type(v) == "table" and Decl.ScrollControl:isclassof(v)
end

local function is_decl_child(v)
    return type(v) == "table" and Decl.Child:isclassof(v)
end

local function is_decl_widget_call(v)
    return type(v) == "table" and Decl.WidgetCall:isclassof(v)
end

local function is_decl_widget_def(v)
    return type(v) == "table" and Decl.WidgetDef:isclassof(v)
end

local function is_decl_theme_def(v)
    return type(v) == "table" and Decl.ThemeDef:isclassof(v)
end

local function is_decl_style_patch(v)
    return type(v) == "table" and Decl.StylePatch:isclassof(v)
end

local function is_decl_theme_scope(v)
    return type(v) == "table" and Decl.ThemeScope:isclassof(v)
end

local function is_scope(v)
    return type(v) == "table" and rawget(v, "__terraui_scope") == true
end

local function zero()
    return Decl.NumLit(0)
end

local function zero_padding()
    local z = zero()
    return Decl.Padding(z, z, z, z)
end

local function no_vis(props)
    return Decl.Visibility(
        props.visible_when and M.as_expr(props.visible_when) or nil,
        props.enabled_when and M.as_expr(props.enabled_when) or nil)
end

local function no_input(props, defaults)
    defaults = defaults or {}
    return Decl.Input(
        props.hover ~= nil and props.hover or (defaults.hover or false),
        props.press ~= nil and props.press or (defaults.press or false),
        props.focus ~= nil and props.focus or (defaults.focus or false),
        props.wheel ~= nil and props.wheel or (defaults.wheel or false),
        props.cursor ~= nil and props.cursor or defaults.cursor,
        props.action ~= nil and props.action or defaults.action)
end

local function normalize_id(id)
    if id == nil then return Decl.Auto end
    if is_scope(id) then return id._id end
    if is_decl_id(id) then return id end
    if type(id) == "string" then return Decl.Stable(id) end
    error("invalid id")
end

function M.as_expr(v)
    local tv = type(v)
    if v == nil then return nil end
    if is_decl_expr(v) then return v end
    if tv == "number" then return Decl.NumLit(v) end
    if tv == "string" then return Decl.StringLit(v) end
    if tv == "boolean" then return Decl.BoolLit(v) end
    error("cannot convert value to Decl.Expr: " .. tv)
end

local function normalize_size(v, default)
    if v == nil then return default end
    if is_decl_size(v) then return v end
    if type(v) == "number" then return Decl.Fixed(Decl.NumLit(v)) end
    error("invalid size")
end

local function normalize_padding(v)
    if v == nil then return zero_padding() end
    if type(v) == "number" or is_decl_expr(v) then
        local e = M.as_expr(v)
        return Decl.Padding(e, e, e, e)
    end
    if type(v) == "table" and Decl.Padding:isclassof(v) then
        return v
    end
    if type(v) == "table" then
        local l = M.as_expr(v.left or v[1] or 0)
        local t = M.as_expr(v.top or v[2] or v[1] or 0)
        local r = M.as_expr(v.right or v[3] or v[1] or 0)
        local b = M.as_expr(v.bottom or v[4] or v[2] or v[1] or 0)
        return Decl.Padding(l, t, r, b)
    end
    error("invalid padding")
end

local function normalize_decor(props)
    return Decl.Decor(
        props.background and M.as_expr(props.background) or nil,
        props.border,
        props.radius,
        props.opacity and M.as_expr(props.opacity) or nil)
end

local function normalize_clip(props)
    if props.scroll_x ~= nil or props.scroll_y ~= nil then
        error("authored scroll_x/scroll_y are no longer part of the structural DSL")
    end
    if props.clip and Decl.Clip:isclassof(props.clip) then return props.clip end
    if type(props.clip) == "table" then
        local c = props.clip
        return Decl.Clip(
            c.horizontal or false,
            c.vertical or false)
    end
    return nil
end

local function normalize_scroll(props)
    if props.scroll and is_decl_scroll(props.scroll) then return props.scroll end

    if type(props.scroll) == "table" then
        local s = props.scroll
        return Decl.Scroll(
            s.horizontal or false,
            s.vertical or false)
    end

    if props.__terraui_scroll_region then
        return Decl.Scroll(
            props.horizontal or false,
            props.vertical or false)
    end

    return nil
end

local function normalize_target_id(target)
    if target == nil then error("scroll target required") end
    if is_scope(target) then return target:key() end
    if type(target) == "string" then return Decl.Stable(target) end
    if is_decl_id(target) then return target end
    if type(target) == "table" and target.kind == "FloatById" then return target.id end
    error("invalid scroll target")
end

local function normalize_scroll_control(props)
    if props.scroll_control and is_decl_scroll_control(props.scroll_control) then
        return props.scroll_control
    end
    return nil
end

local function normalize_floating(props)
    if props.floating and Decl.Floating:isclassof(props.floating) then
        return props.floating
    end
    if props.target or props.float_target then
        return Decl.Floating(
            props.target or props.float_target,
            props.element_point or Decl.AttachLeftTop,
            props.parent_point or Decl.AttachLeftTop,
            M.as_expr(props.offset_x or 0),
            M.as_expr(props.offset_y or 0),
            M.as_expr(props.expand_w or 0),
            M.as_expr(props.expand_h or 0),
            M.as_expr(props.z_index or 0),
            props.pointer_capture or Decl.Passthrough)
    end
    return nil
end

local function normalize_theme_scope(props)
    if props.theme_scope and is_decl_theme_scope(props.theme_scope) then
        return props.theme_scope
    end
    if props.theme ~= nil or props.theme_overrides ~= nil then
        local overrides = List()
        local names = {}
        for name, _ in pairs(props.theme_overrides or {}) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            overrides:insert(Decl.ThemeOverride(name, M.as_expr((props.theme_overrides or {})[name])))
        end
        local base_theme = props.theme
        if type(base_theme) ~= "string" and base_theme ~= nil then
            error("theme name must be a string")
        end
        return Decl.ThemeScope(base_theme, overrides)
    end
    return nil
end

local function normalize_style_patch(spec)
    if spec == nil then return nil end
    if is_decl_style_patch(spec) then return spec end
    assert(type(spec) == "table", "style patch must be a table")
    return Decl.StylePatch(
        spec.background and M.as_expr(spec.background) or nil,
        spec.border,
        spec.radius,
        spec.opacity and M.as_expr(spec.opacity) or nil,
        spec.text_color and M.as_expr(spec.text_color) or nil,
        spec.font_id and M.as_expr(spec.font_id) or nil,
        spec.font_size and M.as_expr(spec.font_size) or nil,
        spec.letter_spacing and M.as_expr(spec.letter_spacing) or nil,
        spec.line_height and M.as_expr(spec.line_height) or nil,
        spec.wrap,
        spec.text_align,
        spec.image_tint and M.as_expr(spec.image_tint) or nil)
end

local function text_style(props)
    return Decl.TextStyle(
        M.as_expr(props.color or props.text_color or Decl.ColorLit(1,1,1,1)),
        M.as_expr(props.font_id or "default"),
        M.as_expr(props.font_size or 14),
        M.as_expr(props.letter_spacing or 0),
        M.as_expr(props.line_height or 1.2),
        props.wrap or Decl.WrapNone,
        props.text_align or Decl.TextAlignLeft)
end

local function flatten_children(out, child)
    if child == nil then
        return
    elseif is_decl_child(child) then
        out:insert(child)
    elseif is_decl_node(child) then
        out:insert(Decl.NodeChild(child))
    elseif is_decl_widget_call(child) then
        out:insert(Decl.WidgetChild(child))
    elseif type(child) == "table" and child.__terraui_fragment then
        for _, c in ipairs(child.children) do flatten_children(out, c) end
    elseif type(child) == "table" and not child.kind then
        for _, c in ipairs(child) do flatten_children(out, c) end
    else
        error("invalid child entry")
    end
end

local function normalize_children(children)
    local out = List()
    if children == nil then return out end
    flatten_children(out, children)
    return out
end

local function is_named_slot_map(v)
    if type(v) ~= "table" or v.kind ~= nil or v.__terraui_fragment then return false end
    local saw_named = false
    for k, _ in pairs(v) do
        if type(k) ~= "number" then
            saw_named = true
            break
        end
    end
    return saw_named
end

local function has_path_sep(name)
    return type(name) == "string" and name:find("/", 1, true) ~= nil
end

local function normalized_local_id_name(v, label)
    label = label or "local id"
    if type(v) == "string" then
        assert(v ~= "", label .. " must be non-empty")
        assert(not has_path_sep(v), label .. " must not contain '/'")
        return v
    elseif is_decl_id(v) and v.kind == "Stable" then
        assert(v.name ~= "", label .. " must be non-empty")
        assert(not has_path_sep(v.name), label .. " must not contain '/'")
        return v.name
    end
    error(label .. " must be a string or stable id")
end

local function normalize_anchor_id(id)
    if type(id) == "string" then
        return Decl.Stable(normalized_local_id_name(id, "anchor"))
    elseif is_decl_id(id) then
        if id.kind == "Stable" then
            return Decl.Stable(normalized_local_id_name(id, "anchor"))
        elseif id.kind == "Indexed" then
            return Decl.Indexed(normalized_local_id_name(id.name, "anchor"), id.index)
        end
    end
    error("invalid anchor")
end

local function compose_scoped_id(base_id, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = normalized_local_id_name(select(i, ...))
    end
    local suffix = table.concat(parts, "/")
    assert(suffix ~= "", "scope composition requires at least one local segment")
    local id = normalize_id(base_id)
    if id.kind == "Stable" then
        return Decl.Stable(id.name .. "/" .. suffix)
    elseif id.kind == "Indexed" then
        return Decl.Indexed(id.name .. "/" .. suffix, id.index)
    end
    error("scope composition requires a stable or indexed base id")
end

local function widget_fields(def)
    if def == nil then return nil end
    local props = {}
    local slots = {}
    local parts = {}
    for _, p in ipairs(def.props) do props[p.name] = p end
    for _, s in ipairs(def.slots) do slots[s.name] = true end
    for _, p in ipairs(def.parts) do parts[p.name] = true end
    return props, slots, parts
end

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

local function static_expr_type(expr)
    if expr == nil then return nil end
    local k = expr.kind
    if k == "BoolLit" then return Decl.TBool
    elseif k == "NumLit" then return Decl.TNumber
    elseif k == "StringLit" then return Decl.TString
    elseif k == "ColorLit" then return Decl.TColor
    elseif k == "Vec2Lit" then return Decl.TVec2
    elseif k == "Unary" then
        local rhs = static_expr_type(expr.rhs)
        if expr.op == "not" and rhs == Decl.TBool then return Decl.TBool end
        if expr.op == "-" and rhs == Decl.TNumber then return Decl.TNumber end
        return nil
    elseif k == "Binary" then
        local lhs = static_expr_type(expr.lhs)
        local rhs = static_expr_type(expr.rhs)
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
        local y = static_expr_type(expr.yes)
        local n = static_expr_type(expr.no)
        if y ~= nil and n ~= nil and (y == n or is_type_compatible(y, n) or is_type_compatible(n, y)) then
            return y
        end
        return nil
    end
    return nil
end

local function validate_widget_props(def, props)
    if def == nil then return end
    local prop_defs = widget_fields(def)
    for k, v in pairs(props) do
        if k ~= "key" and k ~= "slots" and k ~= "styles" and prop_defs[k] == nil then
            error("unknown widget prop in DSL for " .. def.name .. ": " .. tostring(k))
        end
        if k ~= "key" and k ~= "slots" and k ~= "styles" and prop_defs[k] ~= nil then
            local expr = M.as_expr(v)
            local got = static_expr_type(expr)
            local expected = prop_defs[k].ty
            if got ~= nil and not is_type_compatible(expected, got) then
                error("widget prop type mismatch in DSL for " .. def.name .. ": " .. k .. " expected " .. type_name(expected) .. ", got " .. type_name(got))
            end
        end
    end
    for name, p in pairs(prop_defs) do
        if props[name] == nil and p.default == nil then
            error("missing required widget prop in DSL for " .. def.name .. ": " .. name)
        end
    end
end

local function validate_widget_styles(def, styles)
    if def == nil or styles == nil then return end
    local _, _, part_defs = widget_fields(def)
    for name, patch in pairs(styles) do
        if part_defs[name] == nil then
            error("unknown widget part in DSL for " .. def.name .. ": " .. tostring(name))
        end
        normalize_style_patch(patch)
    end
end

local function normalize_slot_args(props, children, def)
    local slot_args = List()
    local slot_sources = {}
    local slot_map = props.slots or {}

    for slot_name, slot_children in pairs(slot_map) do
        if slot_sources[slot_name] ~= nil then
            error("duplicate widget slot source in DSL: " .. slot_name)
        end
        slot_sources[slot_name] = slot_children
    end

    local child_payload = children
    if is_named_slot_map(children) then
        child_payload = nil
        for slot_name, slot_children in pairs(children) do
            if slot_sources[slot_name] ~= nil then
                error("duplicate widget slot source in DSL: " .. slot_name)
            end
            slot_sources[slot_name] = slot_children
        end
    end

    if child_payload ~= nil then
        if slot_sources.children ~= nil then
            error("duplicate widget slot source in DSL: children")
        end
        slot_sources.children = child_payload
    end

    if def ~= nil then
        local _, slot_defs = widget_fields(def)
        for slot_name, _ in pairs(slot_sources) do
            if slot_name ~= "children" and slot_defs[slot_name] == nil then
                error("unknown widget slot in DSL for " .. def.name .. ": " .. tostring(slot_name))
            end
        end
    end

    local slot_names = {}
    for slot_name, _ in pairs(slot_sources) do slot_names[#slot_names + 1] = slot_name end
    table.sort(slot_names)
    for _, slot_name in ipairs(slot_names) do
        slot_args:insert(Decl.SlotArg(slot_name, normalize_children(slot_sources[slot_name])))
    end

    return slot_args
end

local function make_node(axis, props, leaf, children, defaults)
    props = props or {}
    defaults = defaults or {}
    if props.anchor ~= nil and props.key ~= nil then
        error("node cannot specify both key and anchor")
    end

    local local_anchor = props.anchor

    local id_mode = "auto"
    local node_id = Decl.Auto
    if local_anchor ~= nil then
        id_mode = "anchor"
        node_id = normalize_anchor_id(local_anchor)
    elseif props.key ~= nil then
        id_mode = "key"
        node_id = normalize_id(props.key)
    end

    local node = Decl.Node(
        node_id,
        props.part,
        normalize_theme_scope(props),
        no_vis(props),
        Decl.Layout(
            axis,
            normalize_size(props.width, defaults.width),
            normalize_size(props.height, defaults.height),
            normalize_padding(props.padding),
            M.as_expr(props.gap or 0),
            props.align_x or Decl.AlignLeft,
            props.align_y or Decl.AlignTop),
        normalize_decor(props),
        normalize_clip(props),
        normalize_scroll(props),
        normalize_scroll_control(props),
        normalize_floating(props),
        no_input(props, defaults.input),
        props.aspect_ratio and M.as_expr(props.aspect_ratio) or nil,
        leaf,
        normalize_children(children))
    rawset(node, "_terraui_id_mode", id_mode)
    return node
end

function M.dsl()
    local ui = {}
    local widget_registry = {}

    local Scope = {}
    Scope.__index = Scope

    local function make_scope(id)
        local sid = normalize_id(id)
        if sid.kind ~= "Stable" and sid.kind ~= "Indexed" then
            error("ui.scope requires a stable or indexed id")
        end
        return setmetatable({
            __terraui_scope = true,
            _id = sid,
        }, Scope)
    end

    function Scope:key()
        return self._id
    end

    function Scope:child(...)
        return make_scope(compose_scoped_id(self, ...))
    end

    function Scope:anchor(...)
        return Decl.FloatById(compose_scoped_id(self, ...))
    end

    ui.types = {
        bool = Decl.TBool,
        number = Decl.TNumber,
        string = Decl.TString,
        color = Decl.TColor,
        image = Decl.TImage,
        vec2 = Decl.TVec2,
        any = Decl.TAny,
    }

    ui.axis = { row = Decl.Row, column = Decl.Column, stack = Decl.Stack }
    ui.align_x = { left = Decl.AlignLeft, center = Decl.AlignCenterX, right = Decl.AlignRight }
    ui.align_y = { top = Decl.AlignTop, center = Decl.AlignCenterY, bottom = Decl.AlignBottom }
    ui.wrap = { words = Decl.WrapWords, newlines = Decl.WrapNewlines, none = Decl.WrapNone }
    ui.text_align = { left = Decl.TextAlignLeft, center = Decl.TextAlignCenter, right = Decl.TextAlignRight }
    ui.image_fit = { stretch = Decl.ImageStretch, contain = Decl.ImageContain, cover = Decl.ImageCover }
    ui.pointer_capture = { capture = Decl.Capture, passthrough = Decl.Passthrough }
    ui.attach = {
        left_top = Decl.AttachLeftTop,
        top_center = Decl.AttachTopCenter,
        right_top = Decl.AttachRightTop,
        left_center = Decl.AttachLeftCenter,
        center = Decl.AttachCenter,
        right_center = Decl.AttachRightCenter,
        left_bottom = Decl.AttachLeftBottom,
        bottom_center = Decl.AttachBottomCenter,
        right_bottom = Decl.AttachRightBottom,
    }
    ui.float = {
        parent = Decl.FloatParent,
        by_id = function(id) return Decl.FloatById(normalize_id(id)) end,
    }

    ui.scroll = {
        axis = {
            x = Decl.ScrollAxisX,
            y = Decl.ScrollAxisY,
        },
        metric = function(target, kind)
            return Decl.ScrollMetric(normalize_target_id(target), kind)
        end,
        offset_x = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollOffsetX) end,
        offset_y = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollOffsetY) end,
        viewport_w = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollViewportW) end,
        viewport_h = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollViewportH) end,
        content_w = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollContentW) end,
        content_h = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollContentH) end,
        max_x = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollMaxX) end,
        max_y = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollMaxY) end,
        need_x = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollNeedX) end,
        need_y = function(target) return Decl.ScrollMetric(normalize_target_id(target), Decl.ScrollNeedY) end,
        thumb = function(target, axis)
            return Decl.ScrollControl(normalize_target_id(target), axis, Decl.ScrollThumbKind)
        end,
        page_dec = function(target, axis)
            return Decl.ScrollControl(normalize_target_id(target), axis, Decl.ScrollPageDecKind)
        end,
        page_inc = function(target, axis)
            return Decl.ScrollControl(normalize_target_id(target), axis, Decl.ScrollPageIncKind)
        end,
    }

    ui.scope = function(id)
        return make_scope(id)
    end

    ui.as_expr = M.as_expr
    ui.num = function(v) return Decl.NumLit(v) end
    ui.str = function(v) return Decl.StringLit(v) end
    ui.bool = function(v) return Decl.BoolLit(v) end
    ui.rgba = function(r,g,b,a) return Decl.ColorLit(r,g,b,a) end
    ui.vec2 = function(x,y) return Decl.Vec2Lit(x,y) end
    ui.stable = function(name) return Decl.Stable(name) end
    ui.indexed = function(name, idx) return Decl.Indexed(name, M.as_expr(idx)) end
    ui.grow = function(min, max) return Decl.Grow(M.as_expr(min), M.as_expr(max)) end
    ui.fit = function(min, max) return Decl.Fit(M.as_expr(min), M.as_expr(max)) end
    ui.fixed = function(v) return Decl.Fixed(M.as_expr(v)) end
    ui.percent = function(v) return Decl.Percent(M.as_expr(v)) end
    ui.pad = normalize_padding
    ui.border = function(t)
        return Decl.Border(
            M.as_expr(t.left or 0),
            M.as_expr(t.top or 0),
            M.as_expr(t.right or 0),
            M.as_expr(t.bottom or 0),
            M.as_expr(t.between_children or 0),
            M.as_expr(t.color or Decl.ColorLit(1,1,1,1)))
    end
    ui.radius = function(tl, tr, br, bl)
        if tr == nil then tr, br, bl = tl, tl, tl end
        return Decl.CornerRadius(M.as_expr(tl), M.as_expr(tr), M.as_expr(br), M.as_expr(bl))
    end
    local token_ns = {}
    setmetatable(token_ns, {
        __call = function(_, name)
            return Decl.TokenRef(name)
        end,
    })
    token_ns.color = function(name) return Decl.TokenRef(name) end
    token_ns.number = function(name) return Decl.TokenRef(name) end
    token_ns.string = function(name) return Decl.TokenRef(name) end
    token_ns.bool = function(name) return Decl.TokenRef(name) end
    token_ns.image = function(name) return Decl.TokenRef(name) end
    token_ns.vec2 = function(name) return Decl.TokenRef(name) end

    ui.token = token_ns
    ui.theme = function(name) return Decl.TokenRef(name) end
    ui.env = function(name) return Decl.EnvRef(name) end
    ui.param_ref = function(name) return Decl.ParamRef(name) end
    ui.state_ref = function(name) return Decl.StateRef(name) end
    ui.prop_ref = function(name) return Decl.WidgetPropRef(name) end
    ui.call = function(fn, ...)
        local args = List()
        for i = 1, select("#", ...) do args:insert(M.as_expr(select(i, ...))) end
        return Decl.Call(fn, args)
    end
    ui.select = function(c, y, n) return Decl.Select(M.as_expr(c), M.as_expr(y), M.as_expr(n)) end

    local function expr_bin(op, a, b)
        return Decl.Binary(op, M.as_expr(a), M.as_expr(b))
    end

    local function scroll_need_expr(axis_metric_content, axis_metric_viewport)
        return expr_bin(">", axis_metric_content, axis_metric_viewport)
    end

    local function scroll_bar_extent_expr(need_expr, extent)
        return ui.select(need_expr, extent, 0)
    end

    local function scroll_thumb_len_expr(content_metric, viewport_metric, track_metric, min_thumb)
        local proportional = ui.call("min", track_metric, ui.call("max", min_thumb, ui.call("*", track_metric, ui.call("/", viewport_metric, content_metric))))
        return ui.select(expr_bin(">", content_metric, viewport_metric), proportional, track_metric)
    end

    local function scroll_thumb_pos_expr(offset_metric, max_metric, track_metric, thumb_len_metric)
        return ui.select(
            expr_bin(">", max_metric, 0),
            ui.call("*", ui.call("-", track_metric, thumb_len_metric), ui.call("/", offset_metric, max_metric)),
            0)
    end

    ui.fragment = function(children)
        return { __terraui_fragment = true, children = children or {} }
    end
    ui.when = function(cond, child)
        if cond then return child end
        return ui.fragment {}
    end
    ui.maybe = function(child)
        if child == nil then return ui.fragment {} end
        return child
    end
    ui.each = function(xs, fn)
        local out = {}
        for i, x in ipairs(xs) do
            out[#out + 1] = fn(x, i)
        end
        return ui.fragment(out)
    end

    ui.param = function(name)
        return function(spec)
            spec = spec or {}
            return Decl.Param(name, spec.type, spec.default and M.as_expr(spec.default) or nil)
        end
    end

    ui.theme_token = function(name, ty, value)
        return Decl.ThemeToken(name, ty, M.as_expr(value))
    end

    ui.theme_def = function(name)
        return function(spec)
            spec = spec or {}
            local tokens = List()
            for _, t in ipairs(spec.tokens or {}) do tokens:insert(t) end
            return Decl.ThemeDef(name, spec.parent, tokens)
        end
    end

    ui.widget_prop = function(name)
        return function(spec)
            spec = spec or {}
            return Decl.WidgetProp(name, spec.type, spec.default and M.as_expr(spec.default) or nil)
        end
    end

    ui.widget_slot = function(name)
        return Decl.WidgetSlot(name)
    end

    ui.widget_part = function(name)
        return Decl.WidgetPart(name)
    end

    ui.style = function(spec)
        return normalize_style_patch(spec or {})
    end

    ui.part = function(name, child)
        assert(is_decl_node(child), "ui.part expects a Decl.Node")
        child.part = name
        return child
    end

    ui.with_theme = function(name, overrides)
        local out = List()
        local names = {}
        for k, _ in pairs(overrides or {}) do names[#names + 1] = k end
        table.sort(names)
        for _, k in ipairs(names) do
            out:insert(Decl.ThemeOverride(k, M.as_expr(overrides[k])))
        end
        local scope = Decl.ThemeScope(name, out)
        return function(children)
            local items = {}
            if children == nil then
                return ui.fragment {}
            elseif is_decl_node(children) or is_decl_widget_call(children) or is_decl_child(children) then
                items = { children }
            elseif type(children) == "table" and children.__terraui_fragment then
                items = children.children or {}
            elseif type(children) == "table" then
                items = children
            else
                error("ui.with_theme expects child or child list")
            end
            for _, child in ipairs(items) do
                if is_decl_node(child) then
                    child.theme_scope = scope
                elseif is_decl_widget_call(child) then
                    rawset(child, "_terraui_theme_scope", scope)
                end
            end
            return ui.fragment(items)
        end
    end

    ui.state = function(name)
        return function(spec)
            spec = spec or {}
            return Decl.StateSlot(name, spec.type, spec.initial and M.as_expr(spec.initial) or nil)
        end
    end

    ui.widget = function(name)
        return function(spec)
            spec = spec or {}
            local props = List()
            for _, p in ipairs(spec.props or {}) do props:insert(p) end
            local state = List()
            for _, s in ipairs(spec.state or {}) do state:insert(s) end
            local slots = List()
            for _, s in ipairs(spec.slots or {}) do slots:insert(s) end
            local parts = List()
            for _, p in ipairs(spec.parts or {}) do
                assert(type(p) == "table" and Decl.WidgetPart:isclassof(p), "widget.parts entries must be Decl.WidgetPart")
                parts:insert(p)
            end
            assert(spec.root and is_decl_node(spec.root), "widget.root must be a Decl.Node")

            local def = Decl.WidgetDef(name, props, state, slots, parts, spec.root)
            if widget_registry[name] ~= nil and widget_registry[name] ~= def then
                error("duplicate widget name in DSL environment: " .. name)
            end
            widget_registry[name] = def
            return def
        end
    end

    ui.slot = function(name)
        return Decl.SlotRef(name)
    end

    ui.use = function(widget)
        local def, name
        if is_decl_widget_def(widget) then
            def = widget
            name = widget.name
            widget_registry[name] = widget
        else
            name = widget
            def = widget_registry[name]
        end
        assert(type(name) == "string", "ui.use expects widget name or Decl.WidgetDef")
        return function(props)
            props = props or {}
            validate_widget_props(def, props)
            validate_widget_styles(def, props.styles)
            return function(children)
                local slot_args = normalize_slot_args(props, children, def)

                local prop_args = List()
                local prop_names = {}
                for k, _ in pairs(props) do
                    if k ~= "key" and k ~= "slots" and k ~= "styles" then prop_names[#prop_names + 1] = k end
                end
                table.sort(prop_names)
                for _, k in ipairs(prop_names) do
                    prop_args:insert(Decl.PropArg(k, M.as_expr(props[k])))
                end

                local style_args = List()
                local style_names = {}
                for k, _ in pairs(props.styles or {}) do style_names[#style_names + 1] = k end
                table.sort(style_names)
                for _, k in ipairs(style_names) do
                    style_args:insert(Decl.PartStyleArg(k, normalize_style_patch(props.styles[k])))
                end
                return Decl.WidgetCall(props.key and normalize_id(props.key) or nil, name, prop_args, style_args, slot_args)
            end
        end
    end

    ui.component = function(name)
        return function(spec)
            spec = spec or {}
            local params = List()
            for _, p in ipairs(spec.params or {}) do params:insert(p) end
            local state = List()
            for _, s in ipairs(spec.state or {}) do state:insert(s) end
            local themes = List()
            for _, t in ipairs(spec.themes or {}) do
                assert(is_decl_theme_def(t), "component.themes entries must be Decl.ThemeDef")
                themes:insert(t)
            end
            local widgets = List()
            for _, w in ipairs(spec.widgets or {}) do
                assert(is_decl_widget_def(w), "component.widgets entries must be Decl.WidgetDef")
                widgets:insert(w)
            end
            assert(spec.root and is_decl_node(spec.root), "component.root must be a Decl.Node")
            return Decl.Component(name, params, state, themes, widgets, spec.root)
        end
    end

    ui.row = function(props)
        return function(children)
            return make_node(Decl.Row, props, nil, children, {
                width = Decl.Grow(nil, nil),
                height = Decl.Grow(nil, nil),
            })
        end
    end

    ui.column = function(props)
        return function(children)
            return make_node(Decl.Column, props, nil, children, {
                width = Decl.Grow(nil, nil),
                height = Decl.Grow(nil, nil),
            })
        end
    end

    ui.stack = function(props)
        return function(children)
            return make_node(Decl.Stack, props, nil, children, {
                width = Decl.Grow(nil, nil),
                height = Decl.Grow(nil, nil),
            })
        end
    end

    ui.scroll_region = function(props)
        props = props or {}
        props.__terraui_scroll_region = true
        return function(children)
            return make_node(Decl.Column, props, nil, children, {
                width = Decl.Grow(nil, nil),
                height = Decl.Grow(nil, nil),
            })
        end
    end

    ui.scroll_area = function(props)
        props = props or {}
        local horizontal = props.horizontal == true
        local vertical = props.vertical ~= false
        local bar_size = props.bar_size or 12
        local min_thumb_size = props.min_thumb_size or 24
        assert(props.key ~= nil, "scroll_area.key required")

        return function(children)
            local scope = ui.scope(props.key)
            local viewport_target = "viewport"
            local viewport_pad = normalize_padding(props.viewport_padding)
            local vbar_padding = Decl.Padding(Decl.NumLit(0), viewport_pad.top, Decl.NumLit(0), viewport_pad.bottom)
            local hbar_padding = Decl.Padding(viewport_pad.left, Decl.NumLit(0), viewport_pad.right, Decl.NumLit(0))
            local need_y = vertical and ui.scroll.need_y(viewport_target) or false
            local need_x = horizontal and ui.scroll.need_x(viewport_target) or false
            local vbar_w = vertical and bar_size or 0
            local hbar_h = horizontal and bar_size or 0

            local function vbar()
                local track_h = ui.scroll.viewport_h(viewport_target)
                local content_h = ui.scroll.content_h(viewport_target)
                local viewport_h = ui.scroll.viewport_h(viewport_target)
                local max_y = ui.scroll.max_y(viewport_target)
                local thumb_h = scroll_thumb_len_expr(content_h, viewport_h, track_h, min_thumb_size)
                local top_h = scroll_thumb_pos_expr(ui.scroll.offset_y(viewport_target), max_y, track_h, thumb_h)
                return ui.column {
                    -- Overlay: float over the parent's right edge so the
                    -- viewport always gets the full width.  This breaks the
                    -- vbar-visibility ↔ viewport-width ↔ wrap-height cycle
                    -- that previously required 3× layout iteration.
                    target = ui.float.parent,
                    element_point = ui.attach.right_top,
                    parent_point = ui.attach.right_top,
                    z_index = 1,
                    width = ui.fixed(vbar_w),
                    height = ui.grow(),
                    gap = 0,
                    padding = vbar_padding,
                    background = props.scrollbar_background or ui.rgba(0.12, 0.13, 0.15, 1),
                    border = props.scrollbar_border,
                    visible_when = need_y,
                } {
                    ui.spacer {
                        width = ui.fixed(vbar_w),
                        height = ui.fixed(top_h),
                        hover = true,
                        press = true,
                        cursor = props.track_cursor or props.thumb_cursor or "pointer",
                        visible_when = need_y,
                        scroll_control = ui.scroll.page_dec(viewport_target, ui.scroll.axis.y),
                    },
                    ui.spacer {
                        width = ui.fixed(vbar_w),
                        height = ui.fixed(thumb_h),
                        background = props.thumb_background or ui.rgba(0.42, 0.46, 0.54, 1),
                        border = props.thumb_border,
                        radius = props.thumb_radius or ui.radius(4),
                        hover = true,
                        press = true,
                        cursor = props.thumb_cursor or "pointer",
                        visible_when = need_y,
                        scroll_control = ui.scroll.thumb(viewport_target, ui.scroll.axis.y),
                    },
                    ui.spacer {
                        width = ui.fixed(vbar_w),
                        height = ui.grow(),
                        hover = true,
                        press = true,
                        cursor = props.track_cursor or props.thumb_cursor or "pointer",
                        visible_when = need_y,
                        scroll_control = ui.scroll.page_inc(viewport_target, ui.scroll.axis.y),
                    },
                }
            end

            local function hbar()
                local track_w = ui.scroll.viewport_w(viewport_target)
                local content_w = ui.scroll.content_w(viewport_target)
                local viewport_w = ui.scroll.viewport_w(viewport_target)
                local max_x = ui.scroll.max_x(viewport_target)
                local thumb_w = scroll_thumb_len_expr(content_w, viewport_w, track_w, min_thumb_size)
                local left_w = scroll_thumb_pos_expr(ui.scroll.offset_x(viewport_target), max_x, track_w, thumb_w)
                return ui.row {
                    target = ui.float.parent,
                    element_point = ui.attach.left_bottom,
                    parent_point = ui.attach.left_bottom,
                    z_index = 1,
                    width = ui.grow(),
                    height = ui.fixed(hbar_h),
                    gap = 0,
                    padding = hbar_padding,
                    background = props.scrollbar_background or ui.rgba(0.12, 0.13, 0.15, 1),
                    border = props.scrollbar_border,
                    visible_when = need_x,
                } {
                    ui.spacer {
                        width = ui.fixed(left_w),
                        height = ui.fixed(hbar_h),
                        hover = true,
                        press = true,
                        cursor = props.track_cursor or props.thumb_cursor or "pointer",
                        visible_when = need_x,
                        scroll_control = ui.scroll.page_dec(viewport_target, ui.scroll.axis.x),
                    },
                    ui.spacer {
                        width = ui.fixed(thumb_w),
                        height = ui.fixed(hbar_h),
                        background = props.thumb_background or ui.rgba(0.42, 0.46, 0.54, 1),
                        border = props.thumb_border,
                        radius = props.thumb_radius or ui.radius(4),
                        hover = true,
                        press = true,
                        cursor = props.thumb_cursor or "pointer",
                        visible_when = need_x,
                        scroll_control = ui.scroll.thumb(viewport_target, ui.scroll.axis.x),
                    },
                    ui.spacer {
                        width = ui.grow(),
                        height = ui.fixed(hbar_h),
                        hover = true,
                        press = true,
                        cursor = props.track_cursor or props.thumb_cursor or "pointer",
                        visible_when = need_x,
                        scroll_control = ui.scroll.page_inc(viewport_target, ui.scroll.axis.x),
                    },
                }
            end

            local viewport_props = {
                anchor = "viewport",
                width = ui.grow(),
                height = ui.grow(),
                horizontal = horizontal,
                vertical = vertical,
                gap = props.viewport_gap or props.gap or 0,
                padding = props.viewport_padding,
                background = props.viewport_background,
                border = props.viewport_border,
                radius = props.viewport_radius,
                opacity = props.viewport_opacity,
            }

            local viewport = ui.scroll_region(viewport_props)(children)

            -- Bars are floats — they overlay the viewport and don't affect
            -- its width/height.  A zero-padding body wrapper ensures the
            -- float anchor matches the viewport's dimensions exactly (the
            -- outer container has user padding that would misalign the bars).
            local body_children = { viewport }
            if vertical then body_children[#body_children + 1] = vbar() end
            if horizontal then body_children[#body_children + 1] = hbar() end

            local body = ui.row {
                width = ui.grow(),
                height = ui.grow(),
                gap = 0,
            } (body_children)

            return ui.row {
                key = scope,
                width = props.width or ui.grow(),
                height = props.height or ui.grow(),
                gap = 0,
                padding = props.padding,
                background = props.background,
                border = props.border,
                radius = props.radius,
                opacity = props.opacity,
            } { body }
        end
    end

    ui.tooltip = function(props)
        props = props or {}
        return function(children)
            return make_node(Decl.Column, props, nil, children, {
                width = Decl.Fit(nil, nil),
                height = Decl.Fit(nil, nil),
            })
        end
    end

    ui.label = function(props)
        props = props or {}
        local leaf = Decl.Text(Decl.TextLeaf(
            M.as_expr(assert(props.text, "label.text required")),
            text_style(props)))
        return make_node(Decl.Row, props, leaf, nil, {
            width = Decl.Fit(nil, nil),
            height = Decl.Fit(nil, nil),
        })
    end

    ui.button = function(props)
        props = props or {}
        -- Buttons center their text by default (labels stay left-aligned).
        if props.text_align == nil then props.text_align = Decl.TextAlignCenter end
        local leaf = Decl.Text(Decl.TextLeaf(
            M.as_expr(assert(props.text, "button.text required")),
            text_style(props)))
        return make_node(Decl.Row, props, leaf, nil, {
            width = Decl.Fit(nil, nil),
            height = Decl.Fit(nil, nil),
            input = {
                hover = true,
                press = true,
                focus = props.focus or false,
                cursor = props.cursor or "pointer",
                action = props.action,
            },
        })
    end

    ui.image_view = function(props)
        props = props or {}
        local leaf = Decl.Image(Decl.ImageLeaf(
            M.as_expr(assert(props.image, "image_view.image required")),
            M.as_expr(props.tint or Decl.ColorLit(1,1,1,1)),
            props.fit or Decl.ImageContain))
        return make_node(Decl.Row, props, leaf, nil, {
            width = Decl.Fit(nil, nil),
            height = Decl.Fit(nil, nil),
        })
    end

    ui.spacer = function(props)
        props = props or {}
        return make_node(Decl.Row, props, nil, nil, {
            width = Decl.Fixed(Decl.NumLit(0)),
            height = Decl.Fixed(Decl.NumLit(0)),
        })
    end

    ui.custom = function(props)
        props = props or {}
        local leaf = Decl.Custom(Decl.CustomLeaf(
            assert(props.kind, "custom.kind required"),
            props.payload and M.as_expr(props.payload) or nil))
        return make_node(Decl.Row, props, leaf, nil, {
            width = Decl.Fit(nil, nil),
            height = Decl.Fit(nil, nil),
        })
    end

    return ui
end

return M
