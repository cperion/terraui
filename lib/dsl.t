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
    if props.clip and Decl.Clip:isclassof(props.clip) then return props.clip end
    if props.horizontal or props.vertical or props.scroll_x or props.scroll_y then
        return Decl.Clip(
            props.horizontal or false,
            props.vertical or false,
            props.scroll_x and M.as_expr(props.scroll_x) or nil,
            props.scroll_y and M.as_expr(props.scroll_y) or nil)
    end
    if type(props.clip) == "table" then
        local c = props.clip
        return Decl.Clip(
            c.horizontal or false,
            c.vertical or false,
            c.child_offset_x and M.as_expr(c.child_offset_x) or nil,
            c.child_offset_y and M.as_expr(c.child_offset_y) or nil)
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
    elseif is_decl_node(child) then
        out:insert(child)
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

local function make_node(axis, props, leaf, children, defaults)
    props = props or {}
    defaults = defaults or {}
    return Decl.Node(
        normalize_id(props.id),
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
        normalize_floating(props),
        no_input(props, defaults.input),
        props.aspect_ratio and M.as_expr(props.aspect_ratio) or nil,
        leaf,
        normalize_children(children))
end

function M.dsl()
    local ui = {}

    ui.types = {
        bool = Decl.TBool,
        number = Decl.TNumber,
        string = Decl.TString,
        color = Decl.TColor,
        image = Decl.TImage,
        vec2 = Decl.TVec2,
        any = Decl.TAny,
    }

    ui.axis = { row = Decl.Row, column = Decl.Column }
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
    ui.theme = function(name) return Decl.ThemeRef(name) end
    ui.env = function(name) return Decl.EnvRef(name) end
    ui.param_ref = function(name) return Decl.ParamRef(name) end
    ui.state_ref = function(name) return Decl.StateRef(name) end
    ui.call = function(fn, ...)
        local args = List()
        for i = 1, select("#", ...) do args:insert(M.as_expr(select(i, ...))) end
        return Decl.Call(fn, args)
    end
    ui.select = function(c, y, n) return Decl.Select(M.as_expr(c), M.as_expr(y), M.as_expr(n)) end

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

    ui.state = function(name)
        return function(spec)
            spec = spec or {}
            return Decl.StateSlot(name, spec.type, spec.initial and M.as_expr(spec.initial) or nil)
        end
    end

    ui.component = function(name)
        return function(spec)
            spec = spec or {}
            local params = List()
            for _, p in ipairs(spec.params or {}) do params:insert(p) end
            local state = List()
            for _, s in ipairs(spec.state or {}) do state:insert(s) end
            assert(spec.root and is_decl_node(spec.root), "component.root must be a Decl.Node")
            return Decl.Component(name, params, state, spec.root)
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

    ui.stack = ui.column

    ui.scroll_region = function(props)
        props = props or {}
        return function(children)
            return make_node(Decl.Column, props, nil, children, {
                width = Decl.Grow(nil, nil),
                height = Decl.Grow(nil, nil),
                input = { wheel = true },
            })
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
