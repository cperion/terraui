-- lib/plan.t
-- Bound -> Plan phase transition
--
-- Installs :plan() / :plan_binding() methods on Bound ASDL types.
-- Provides PlanCtx and plan_component() convenience.

local TerraUI = require("lib/terraui_schema")
local List = require("terralist")
local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound
local Plan = TerraUI.types.Plan

---------------------------------------------------------------------------
-- PlanCtx
---------------------------------------------------------------------------

local PlanCtx = {}
PlanCtx.__index = PlanCtx

function PlanCtx.new()
    return setmetatable({
        _node_table    = {},     -- [index] = Plan.Node (0-indexed)
        _guards        = List(),
        _paints        = List(),
        _inputs        = List(),
        _clips         = List(),
        _texts         = List(),
        _images        = List(),
        _customs       = List(),
        _floats        = List(),
        _next_node     = 0,
        _stable_id_map = {},     -- "base:salt" -> node index
    }, PlanCtx)
end

function PlanCtx:reserve_node()
    local index = self._next_node
    self._next_node = self._next_node + 1
    return index
end

function PlanCtx:set_node(index, node)
    self._node_table[index] = node
end

function PlanCtx:next_node_index()
    return self._next_node
end

-- Side-table allocators return 0-indexed slots
function PlanCtx:add_guard(guard)
    local slot = #self._guards
    self._guards:insert(guard)
    return slot
end

function PlanCtx:add_paint(paint)
    local slot = #self._paints
    self._paints:insert(paint)
    return slot
end

function PlanCtx:add_input(input)
    local slot = #self._inputs
    self._inputs:insert(input)
    return slot
end

function PlanCtx:add_clip(clip)
    local slot = #self._clips
    self._clips:insert(clip)
    return slot
end

function PlanCtx:add_text(text)
    local slot = #self._texts
    self._texts:insert(text)
    return slot
end

function PlanCtx:add_image(image)
    local slot = #self._images
    self._images:insert(image)
    return slot
end

function PlanCtx:add_custom(custom)
    local slot = #self._customs
    self._customs:insert(custom)
    return slot
end

function PlanCtx:add_float(float_spec)
    local slot = #self._floats
    self._floats:insert(float_spec)
    return slot
end

function PlanCtx:bind_stable_id(resolved_id, node_index)
    local key = resolved_id.base .. ":" .. tostring(resolved_id.salt)
    if self._stable_id_map[key] ~= nil then
        error("duplicate stable id during planning: " .. key)
    end
    self._stable_id_map[key] = node_index
end

function PlanCtx:lookup_node_by_stable_id(resolved_id)
    local key = resolved_id.base .. ":" .. tostring(resolved_id.salt)
    local index = self._stable_id_map[key]
    if index == nil then
        error("unknown stable id during planning: " .. key)
    end
    return index
end

function PlanCtx:finish_component(key, root_index)
    local nodes = List()
    for i = 0, self._next_node - 1 do
        assert(self._node_table[i],
            "plan: missing node at index " .. i)
        nodes:insert(self._node_table[i])
    end
    return Plan.Component(
        key, nodes,
        self._guards, self._paints, self._inputs,
        self._clips, self._texts, self._images,
        self._customs, self._floats,
        root_index)
end

---------------------------------------------------------------------------
-- Value:plan_binding   (Bound.Value -> Plan.Binding)
---------------------------------------------------------------------------

function Bound.Value:plan_binding(ctx)
    error("plan_binding not implemented for Bound.Value." ..
          tostring(self.kind))
end

function Bound.ConstBool:plan_binding(ctx)
    return Plan.ConstBool(self.v)
end

function Bound.ConstNumber:plan_binding(ctx)
    return Plan.ConstNumber(self.v)
end

function Bound.ConstString:plan_binding(ctx)
    return Plan.ConstString(self.v)
end

function Bound.ConstColor:plan_binding(ctx)
    return Plan.ConstColor(self.r, self.g, self.b, self.a)
end

function Bound.ConstVec2:plan_binding(ctx)
    return Plan.ConstVec2(self.x, self.y)
end

function Bound.ParamSlot:plan_binding(ctx)
    return Plan.Param(self.slot)
end

function Bound.StateSlotRef:plan_binding(ctx)
    return Plan.State(self.slot)
end

function Bound.EnvSlot:plan_binding(ctx)
    return Plan.Env(self.name)
end

function Bound.Unary:plan_binding(ctx)
    return Plan.Expr(self.op, List{ self.rhs:plan_binding(ctx) })
end

function Bound.Binary:plan_binding(ctx)
    return Plan.Expr(self.op, List{
        self.lhs:plan_binding(ctx),
        self.rhs:plan_binding(ctx) })
end

function Bound.Select:plan_binding(ctx)
    return Plan.Expr("select", List{
        self.cond:plan_binding(ctx),
        self.yes:plan_binding(ctx),
        self.no:plan_binding(ctx) })
end

function Bound.Intrinsic:plan_binding(ctx)
    return Plan.Expr(self.fn,
        self.args:map(function(a) return a:plan_binding(ctx) end))
end

---------------------------------------------------------------------------
-- Size:plan   (Bound.Size -> Plan.SizeRule)
---------------------------------------------------------------------------

function Bound.Size:plan(ctx)
    error("plan not implemented for Bound.Size." .. tostring(self.kind))
end

function Bound.Fit:plan(ctx)
    return Plan.Fit(
        self.min and self.min:plan_binding(ctx) or nil,
        self.max and self.max:plan_binding(ctx) or nil)
end

function Bound.Grow:plan(ctx)
    return Plan.Grow(
        self.min and self.min:plan_binding(ctx) or nil,
        self.max and self.max:plan_binding(ctx) or nil)
end

function Bound.Fixed:plan(ctx)
    return Plan.Fixed(self.value:plan_binding(ctx))
end

function Bound.Percent:plan(ctx)
    return Plan.Percent(self.value:plan_binding(ctx))
end

---------------------------------------------------------------------------
-- Leaf:plan   (Bound.Leaf -> Plan.LeafSlots)
---------------------------------------------------------------------------

function Bound.Leaf:plan(ctx, node_index)
    error("plan not implemented for Bound.Leaf." .. tostring(self.kind))
end

function Bound.Text:plan(ctx, node_index)
    local tl = self.value   -- Bound.TextLeaf
    local spec = Plan.TextSpec(
        node_index,
        tl.content:plan_binding(ctx),
        tl.style.color:plan_binding(ctx),
        tl.style.font_id:plan_binding(ctx),
        tl.style.font_size:plan_binding(ctx),
        tl.style.letter_spacing:plan_binding(ctx),
        tl.style.line_height:plan_binding(ctx),
        tl.style.wrap,
        tl.style.align)
    local slot = ctx:add_text(spec)
    return Plan.LeafSlots(slot, nil, nil)
end

function Bound.Image:plan(ctx, node_index)
    local il = self.value   -- Bound.ImageLeaf
    local spec = Plan.ImageSpec(
        node_index,
        il.image_id:plan_binding(ctx),
        il.tint:plan_binding(ctx),
        il.fit)
    local slot = ctx:add_image(spec)
    return Plan.LeafSlots(nil, slot, nil)
end

function Bound.Custom:plan(ctx, node_index)
    local cl = self.value   -- Bound.CustomLeaf
    local spec = Plan.CustomSpec(
        node_index,
        cl.kind,
        cl.payload and cl.payload:plan_binding(ctx) or nil)
    local slot = ctx:add_custom(spec)
    return Plan.LeafSlots(nil, nil, slot)
end

---------------------------------------------------------------------------
-- Clip:plan
---------------------------------------------------------------------------

function Bound.Clip:plan(ctx, node_index)
    local spec = Plan.ClipSpec(
        node_index,
        self.horizontal,
        self.vertical,
        self.child_offset_x and
            self.child_offset_x:plan_binding(ctx) or nil,
        self.child_offset_y and
            self.child_offset_y:plan_binding(ctx) or nil)
    return ctx:add_clip(spec)
end

---------------------------------------------------------------------------
-- Helpers for decor and floating
---------------------------------------------------------------------------

local function plan_decor(decor, ctx)
    local background = decor.background and
        decor.background:plan_binding(ctx) or nil
    local border = nil
    if decor.border then
        border = Plan.Border(
            decor.border.left:plan_binding(ctx),
            decor.border.top:plan_binding(ctx),
            decor.border.right:plan_binding(ctx),
            decor.border.bottom:plan_binding(ctx),
            decor.border.between_children:plan_binding(ctx),
            decor.border.color:plan_binding(ctx))
    end
    local radius = nil
    if decor.radius then
        radius = Plan.CornerRadius(
            decor.radius.top_left:plan_binding(ctx),
            decor.radius.top_right:plan_binding(ctx),
            decor.radius.bottom_right:plan_binding(ctx),
            decor.radius.bottom_left:plan_binding(ctx))
    end
    local opacity = decor.opacity and
        decor.opacity:plan_binding(ctx) or nil
    return Plan.Paint(background, border, radius, opacity)
end

local function plan_floating(floating, ctx, node_index, parent_index)
    local attach_parent_slot
    if floating.target.kind == "FloatParent" then
        attach_parent_slot = parent_index
    elseif floating.target.kind == "FloatByStableId" then
        attach_parent_slot =
            ctx:lookup_node_by_stable_id(floating.target.id)
    else
        error("unknown FloatTarget kind: " ..
              tostring(floating.target.kind))
    end
    local spec = Plan.FloatSpec(
        node_index,
        attach_parent_slot,
        floating.element_point,
        floating.parent_point,
        floating.offset_x:plan_binding(ctx),
        floating.offset_y:plan_binding(ctx),
        floating.expand_w:plan_binding(ctx),
        floating.expand_h:plan_binding(ctx),
        floating.z_index:plan_binding(ctx),
        floating.pointer_capture)
    return ctx:add_float(spec)
end

---------------------------------------------------------------------------
-- Node:plan
---------------------------------------------------------------------------

function Bound.Node:plan(ctx, parent_index)
    local index = ctx:reserve_node()

    -- Register stable id
    ctx:bind_stable_id(self.stable_id, index)

    -- Guard
    local guard = Plan.Guard(
        self.visibility.visible_when and
            self.visibility.visible_when:plan_binding(ctx) or nil,
        self.visibility.enabled_when and
            self.visibility.enabled_when:plan_binding(ctx) or nil)
    local guard_slot = ctx:add_guard(guard)

    -- Paint
    local paint_slot = ctx:add_paint(plan_decor(self.decor, ctx))

    -- Input
    local input_spec = Plan.InputSpec(
        self.input.hover, self.input.press,
        self.input.focus, self.input.wheel,
        self.input.cursor, self.input.action)
    local input_slot = ctx:add_input(input_spec)

    -- Optional clip
    local clip_slot = self.clip and
        self.clip:plan(ctx, index) or nil

    -- Optional leaf
    local text_slot, image_slot, custom_slot = nil, nil, nil
    if self.leaf then
        local ls = self.leaf:plan(ctx, index)
        text_slot   = ls.text_slot
        image_slot  = ls.image_slot
        custom_slot = ls.custom_slot
    end

    -- Optional float
    local float_slot = self.floating and
        plan_floating(self.floating, ctx, index, parent_index) or nil

    -- Layout bindings
    local layout = self.layout
    local width_rule  = layout.width:plan(ctx)
    local height_rule = layout.height:plan(ctx)
    local pad = layout.padding

    -- Children (preorder)
    local first_child = nil
    local child_count = #self.children
    for i, child in ipairs(self.children) do
        local ci = child:plan(ctx, index)
        if i == 1 then first_child = ci end
    end

    local subtree_end = ctx:next_node_index()

    -- Aspect ratio
    local aspect_ratio = self.aspect_ratio and
        self.aspect_ratio:plan_binding(ctx) or nil

    -- Build Plan.Node (23 fields)
    local node = Plan.Node(
        index,
        parent_index >= 0 and parent_index or nil,
        first_child,
        child_count,
        subtree_end,
        layout.axis,
        width_rule,
        height_rule,
        pad.left:plan_binding(ctx),
        pad.top:plan_binding(ctx),
        pad.right:plan_binding(ctx),
        pad.bottom:plan_binding(ctx),
        layout.gap:plan_binding(ctx),
        layout.align_x,
        layout.align_y,
        guard_slot,
        paint_slot,
        input_slot,
        clip_slot,
        text_slot,
        image_slot,
        custom_slot,
        float_slot,
        aspect_ratio)

    ctx:set_node(index, node)
    return index
end

---------------------------------------------------------------------------
-- Component:plan
---------------------------------------------------------------------------

function Bound.Component:plan(ctx)
    local root_index = self.root:plan(ctx, -1)
    return ctx:finish_component(self.key, root_index)
end

---------------------------------------------------------------------------
-- Public module
---------------------------------------------------------------------------

local M = {}

M.PlanCtx = PlanCtx

function M.plan_component(bound_component)
    local ctx = PlanCtx.new()
    return bound_component:plan(ctx)
end

return M
