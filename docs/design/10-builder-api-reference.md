# TerraUI Builder API Reference

Status: implementation-aligned v0.5  
Purpose: define the concrete public DSL/builders for TerraUI v1.

## Canonical companion docs

- `docs/design/09-authoring-api.md`
- `docs/design/terraui.asdl`
- `docs/design/07-method-contracts.md`
- `lib/dsl.t`
- `lib/terraui.t`

This document describes the **currently shipped** builder surface.

## 1. Style summary

The DSL uses three main shapes:

### Component
```lua
ui.component("name") { ... }
```

### Leaves / single-node widgets
```lua
ui.label { ... }
ui.button { ... }
ui.image_view { ... }
```

### Containers
```lua
ui.row { ... } { ... }
ui.column { ... } { ... }
ui.scroll_region { ... } { ... }
```

Semantic rule:
- first brace = props/config record
- second brace = children list

## 2. DSL environment

Recommended setup:

```lua
local terraui = require("lib/terraui")
local ui = terraui.dsl()
```

The returned table currently exposes:
- constructors/combinators
- helper namespaces
- value helpers
- child fragment helpers

## 3. Exported bindings

## 3.1 Core constructors

```lua
ui.component
ui.param
ui.state
ui.widget
ui.widget_prop
ui.widget_slot
ui.use
ui.slot
ui.scope

ui.row
ui.column
ui.stack
ui.scroll_region
ui.tooltip

ui.label
ui.button
ui.image_view
ui.spacer
ui.custom
```

## 3.2 Child fragment helpers

```lua
ui.each
ui.when
ui.maybe
ui.fragment
```

## 3.3 Identity / value / expr helpers

```lua
ui.as_expr
ui.num
ui.str
ui.bool
ui.rgba
ui.vec2

ui.stable
ui.indexed

ui.fit
ui.grow
ui.fixed
ui.percent
ui.pad
ui.border
ui.radius

ui.call
ui.select
ui.theme
ui.env
ui.param_ref
ui.state_ref
ui.prop_ref
```

## 3.4 Namespaces

```lua
ui.types
ui.axis
ui.align_x
ui.align_y
ui.wrap
ui.text_align
ui.image_fit
ui.pointer_capture
ui.attach
ui.float
```

## 4. Helper namespaces

## 4.1 `ui.types`

```lua
ui.types.bool
ui.types.number
ui.types.string
ui.types.color
ui.types.image
ui.types.vec2
ui.types.any
```

## 4.2 `ui.axis`

```lua
ui.axis.row
ui.axis.column
```

## 4.3 `ui.align_x`

```lua
ui.align_x.left
ui.align_x.center
ui.align_x.right
```

## 4.4 `ui.align_y`

```lua
ui.align_y.top
ui.align_y.center
ui.align_y.bottom
```

## 4.5 `ui.wrap`

```lua
ui.wrap.words
ui.wrap.newlines
ui.wrap.none
```

## 4.6 `ui.text_align`

```lua
ui.text_align.left
ui.text_align.center
ui.text_align.right
```

## 4.7 `ui.image_fit`

```lua
ui.image_fit.stretch
ui.image_fit.contain
ui.image_fit.cover
```

## 4.8 `ui.pointer_capture`

```lua
ui.pointer_capture.capture
ui.pointer_capture.passthrough
```

## 4.9 `ui.attach`

```lua
ui.attach.left_top
ui.attach.top_center
ui.attach.right_top
ui.attach.left_center
ui.attach.center
ui.attach.right_center
ui.attach.left_bottom
ui.attach.bottom_center
ui.attach.right_bottom
```

## 4.10 `ui.float`

```lua
ui.float.parent
ui.float.by_id(id)
```

## 5. Component and declaration constructors

## 5.1 `ui.component(name) { spec }`

### Form
```lua
ui.component("name") {
    params = { ... },
    state = { ... },
    widgets = { ... },
    root = ...,
}
```

### Required fields in `spec`
- `root`

### Optional fields
- `params`
- `state`
- `widgets`

### Lowering
Returns `Decl.Component`.

## 5.2 `ui.param(name) { ... }`

### Form
```lua
ui.param("title") { type = ui.types.string, default = "Hello" }
```

### Required fields
- `type`

### Optional fields
- `default`

### Lowering
Returns `Decl.Param`.

## 5.3 `ui.state(name) { ... }`

### Form
```lua
ui.state("scroll_y") { type = ui.types.number, initial = 0 }
```

### Required fields
- `type`

### Optional fields
- `initial`

### Lowering
Returns `Decl.StateSlot`.

## 5.4 `ui.widget(name) { spec }`

### Form
```lua
ui.widget("Card") {
    props = { ... },
    state = { ... },
    slots = { ... },
    root = ...,
}
```

### Required fields
- `root`

### Optional fields
- `props`
- `state`
- `slots`

### Lowering
Returns `Decl.WidgetDef`.

### State note
`spec.state` reuses ordinary `ui.state(...)` declarations. During bind, each widget instance expands those declarations into namespaced component state slots.

## 5.5 `ui.widget_prop(name) { ... }`

### Form
```lua
ui.widget_prop("title") { type = ui.types.string, default = "Inspector" }
```

### Required fields
- `type`

### Optional fields
- `default`

### Lowering
Returns `Decl.WidgetProp`.

## 5.6 `ui.widget_slot(name)`

### Form
```lua
ui.widget_slot("children")
```

### Lowering
Returns `Decl.WidgetSlot`.

## 5.6a `ui.scope(id)`

### Form
```lua
local card = ui.scope("card1")
local preview = card:child("preview")
```

### Notes
- `id` must be stable or indexed
- scope handles are DSL-only values
- scope handles are accepted anywhere a public `id` is accepted
- `scope:child(name, ...)` returns another scope handle
- `scope:float(name, ...)` returns `Decl.FloatById` for a child under that scope

## 5.7 `ui.use(name) { props } { children }`

### Form
```lua
ui.use("Card") { id = ui.stable("card1"), title = "Inspector" } {
    ui.label { text = "Body" },
}
```

### Notes
- `ui.use(...)` accepts either a widget name or a `Decl.WidgetDef`
- when the widget definition is known at capture time, required/unknown props and slot names are validated immediately
- when a prop expression has a statically obvious type, type mismatches are also rejected immediately
- additional context-aware type mismatches are rejected during bind
- optional named slot arguments can be passed through `props.slots`
- the second brace may be either:
  - an ordered child list for the conventional `children` slot
  - a keyed named-slot table such as `{ left = { ... }, right = { ... } }`
- `props.id` is an optional widget-instance id override used during bind elaboration

### Lowering
Returns `Decl.WidgetCall`.

## 5.8 `ui.slot(name)`

### Form
```lua
ui.slot("children")
```

### Lowering
Returns `Decl.SlotRef(name)`.

## 6. Leaf constructors

Leaf constructors consume one props record and return one `Decl.Node`.

## 6.1 `ui.label { props }`

### Required props
- `text`

### Common optional props
- `id`
- `color`
- `font_id`
- `font_size`
- `letter_spacing`
- `line_height`
- `wrap`
- `text_align`
- `width`
- `height`
- `padding`
- `align_x`
- `align_y`
- `aspect_ratio`
- `visible_when`
- `enabled_when`
- `background`
- `border`
- `radius`
- `opacity`

### Defaults
- axis = `Row`
- width = `fit()`
- height = `fit()`
- color = white
- font_id = `"default"`
- font_size = `14`
- letter_spacing = `0`
- line_height = `1.2`
- wrap = `ui.wrap.none`
- text_align = `ui.text_align.left`

## 6.2 `ui.button { props }`

### Required props
- `text`

### Common optional props
- all common visual/layout props from `label`
- `action`
- `cursor`
- `focus`
- `hover`
- `press`

### Defaults
- width = `fit()`
- height = `fit()`
- `hover = true`
- `press = true`
- `cursor = "pointer"` unless overridden
- `focus = false` unless explicitly requested

### Lowering
Returns one node with:
- text leaf
- interaction defaults

## 6.3 `ui.image_view { props }`

### Required props
- `image`

### Optional props
- `id`
- `fit`
- `tint`
- `aspect_ratio`
- `width`
- `height`
- `padding`
- `background`
- `border`
- `radius`
- `opacity`
- `visible_when`
- `enabled_when`

### Defaults
- width = `fit()`
- height = `fit()`
- tint = white
- fit = `ui.image_fit.contain`

## 6.4 `ui.spacer { props }`

### Optional props
- `id`
- `width`
- `height`

### Defaults
- width = `fixed(0)`
- height = `fixed(0)`

### Lowering
Returns a structural node with no leaf.

## 6.5 `ui.custom { props }`

### Required props
- `kind`

### Optional props
- `payload`
- usual visual/layout props

### Defaults
- width = `fit()`
- height = `fit()`

### Lowering
Returns one node with `Decl.CustomLeaf`.

## 7. Container constructors

Containers are two-stage combinators:

```lua
ui.container { props } { children }
```

Stage 1 returns a continuation awaiting children.
Stage 2 accepts one child list table.

## 7.1 Common container props

Common supported props include:
- `id`
- `visible_when`
- `enabled_when`
- `width`
- `height`
- `padding`
- `gap`
- `align_x`
- `align_y`
- `background`
- `border`
- `radius`
- `opacity`
- `horizontal`
- `vertical`
- `scroll_x`
- `scroll_y`
- `target`
- `float_target`
- `element_point`
- `parent_point`
- `offset_x`
- `offset_y`
- `expand_w`
- `expand_h`
- `z_index`
- `pointer_capture`
- `hover`
- `press`
- `focus`
- `wheel`
- `cursor`
- `action`
- `aspect_ratio`

## 7.2 `ui.row { props } { children }`

### Lowering
Returns a node with:
- `layout.axis = Row`
- default width = `grow()`
- default height = `grow()`

## 7.3 `ui.column { props } { children }`

### Lowering
Returns a node with:
- `layout.axis = Column`
- default width = `grow()`
- default height = `grow()`

## 7.4 `ui.stack { props } { children }`

### Current status
Implemented as:
- alias of `ui.column`

It is authoring sugar only in the current implementation.

## 7.5 `ui.scroll_region { props } { children }`

### Current lowering
- axis = `Column`
- width/height default to `grow()`
- `wheel = true` by default
- `horizontal`, `vertical`, `scroll_x`, `scroll_y` lower into `Decl.Clip`

### Important note
The current implementation uses authored `scroll_x` / `scroll_y` expressions directly as clip child offsets.

## 7.6 `ui.tooltip { props } { children }`

### Current lowering
- axis = `Column`
- width/height default to `fit()`
- floating config is produced only if `target` or `float_target` is supplied

## 8. Child list contract

The second table in a container call is always a child list.

Allowed entries:
- `Decl.Node`
- `nil`
- fragments
- nested Lua arrays of valid child entries
- results of `each`, `when`, `maybe`

Not allowed:
- arbitrary scalars
- malformed tables pretending to be nodes

## 9. Child fragment helpers

## 9.1 `ui.each(xs, fn)`

### Form
```lua
ui.each(xs, function(x, i) ... end)
```

### Current semantics
Iterates immediately in Lua and returns a fragment of produced children.

## 9.2 `ui.when(cond, child)`

Returns:
- `child` when `cond` is truthy
- empty fragment otherwise

## 9.3 `ui.maybe(child)`

Returns:
- `child` when non-`nil`
- empty fragment otherwise

## 9.4 `ui.fragment { children }`

Explicit child grouping helper for flattening.

## 10. Value helpers

## 10.1 Identity helpers

```lua
ui.stable("root")
ui.indexed("asset_row", i)
```

## 10.2 Layout helpers

```lua
ui.grow(min?, max?)
ui.fit(min?, max?)
ui.fixed(value)
ui.percent(value)
ui.pad(x)
ui.pad(left, top, right, bottom)
```

## 10.3 Visual helpers

```lua
ui.rgba(r, g, b, a)
ui.vec2(x, y)
ui.border {
    left = ...,
    top = ...,
    right = ...,
    bottom = ...,
    between_children = ...,
    color = ...,
}
ui.radius(tl)
ui.radius(tl, tr, br, bl)
```

## 10.4 Expression helpers

```lua
ui.call(fn, ...)
ui.select(cond, yes, no)
ui.theme(name)
ui.env(name)
ui.param_ref(name)
ui.state_ref(name)
ui.prop_ref(name)
```

## 11. Public entrypoint helpers

`lib/terraui.t` currently exports:

```lua
terraui.schema
terraui.types
terraui.dsl
terraui.bind
terraui.plan
terraui.compile_plan
terraui.compile
```

## 12. Compile entry

### `terraui.compile(decl_component, opts)`

Runs the full pipeline:

```text
Decl -> Bound -> Plan -> Kernel
```

Returns `Kernel.Component`.

### `terraui.compile_plan(plan_component)`

Compiles a precomputed `Plan.Component`.

### Memoization note
The public compile path is memoized using Terra's memoization machinery and a deterministic key derived from `Plan.Component.key`.

## 13. Error contract

The current builders fail fast on:
- missing required props for several widgets
- malformed component root
- invalid child entries
- malformed ids / sizes / padding inputs
- invalid scope bases or local scope segments
- missing/unknown widget props when the widget definition is known at DSL capture time
- obvious widget prop type mismatches at DSL capture time
- unknown widget slots when the widget definition is known at DSL capture time
- context-aware widget prop type mismatches during bind

Still future work:
- strict unknown-prop validation for all built-in node constructors
- richer expression typing beyond the current obvious/bindable subset

## 14. Canonical minimal shipped surface

```lua
ui.component("name") { ... }
ui.param("name") { ... }
ui.state("name") { ... }

ui.row { ... } { ... }
ui.column { ... } { ... }
ui.stack { ... } { ... }
ui.scroll_region { ... } { ... }
ui.tooltip { ... } { ... }

ui.label { ... }
ui.button { ... }
ui.image_view { ... }
ui.spacer { ... }
ui.custom { ... }

ui.each(xs, fn)
ui.when(cond, child)
ui.maybe(child)
ui.fragment { ... }

ui.stable("id")
ui.indexed("id", i)
ui.scope("id")
ui.grow(...)
ui.fit(...)
ui.fixed(...)
ui.percent(...)
ui.pad(...)
ui.rgba(...)
ui.vec2(...)
ui.border { ... }
ui.radius(...)
ui.call(...)
ui.select(...)
ui.theme(...)
ui.env(...)
ui.param_ref(...)
ui.state_ref(...)
```

## 15. Design conclusion

The current builder/reference surface is now standardized around:

> leaves use one props record, containers use props record followed by a child-list record, and the entire surface lowers directly into `Decl.*`.
