# TerraUI Compiler Pattern Audit

Review of `lib/terraui_schema.t` and implementation files against
`docs/terra-compiler-pattern.md` and `docs/compiler-language-core.md`.

---

## 1. Phase Structure

```
Decl → Bound → Plan → Kernel
```

| Phase | DAW analog | Role |
|---|---|---|
| Decl | Editor | User-authored declarative UI tree |
| Bound | Authored+Resolved | Widget-elaborated, IDs resolved, params slotted |
| Plan | Classified+Scheduled | Flat indexed tables, side tables, bindings |
| Kernel | Kernel | Compiled Terra types + functions |

**Verdict: structurally sound.** Four phases, monotonically narrowing:

- Decl: 4 sum types (Expr 15v, Id 3v, Size 4v, Leaf 3v, Child 3v, FloatTarget 2v)
- Bound: 3 sum types (Value 14v, Size 4v, Leaf 3v, FloatTarget 2v)
- Plan: 2 sum types (Binding 10v, SizeRule 4v)
- Kernel: 0 sum types ✅

The narrowing is correct. No phase widens.

---

## 2. Memoize Boundaries

**Current state: zero `terralib.memoize` calls anywhere.** This is the
single biggest violation.

### Natural memoize boundaries

Only **Component-level** methods are real memoize boundaries:

| Method | Memoize key | Why |
|---|---|---|
| `Component:bind(renderer, text_backend_key)` | `(self, renderer, text_backend_key)` | Same Decl.Component + same options → same Bound.Component |
| `Component:plan()` | `(self)` | Bound.Component fully determines Plan.Component |
| `Component:compile(text_backend)` | `(self, text_backend_key)` | Plan.Component (unique) + text_backend determines Kernel.Component |

Sub-component methods (`Node:bind`, `Expr:bind`, `Node:plan`, etc.) are
**not** memoize boundaries. They depend on mutable traversal state
(BindCtx counters, PlanCtx index allocation, CompileCtx frame symbol).
Memoizing them on `(self, ctx)` would never hit because ctx differs each call.

### What's wrong with declaring 41 schema methods

The schema declares 41 methods. The compiler pattern says: "every
schema-declared method is a memoized public boundary." But 36 of these 41
are internal tree-traversal methods that cannot be meaningfully memoized.

**Fix: declare only 5 methods in the schema** (the real boundaries):

```
Decl.Component:bind(renderer: string, text_backend_key: string) -> Bound.Component
Bound.Component:plan() -> Plan.Component
Plan.Component:compile(text_backend_key: string) -> Kernel.Component
Kernel.Component:frame_type() -> TerraType
Kernel.Component:run_quote() -> TerraQuote
```

The remaining 36 methods stay as plain ASDL methods installed by the
implementation modules. They're helpers, not boundaries.

---

## 3. Hidden Semantic State

The compiler pattern is explicit: **"no hidden semantic state. Every semantic
dependency must appear in the explicit argument list."**

### 3.1 `rawset`/`rawget` monkey-patching on ASDL values

The DSL (`dsl.t`) monkey-patches extra fields onto ASDL nodes:

```lua
rawset(node, "_terraui_id_mode", id_mode)     -- dsl.t:540
rawset(child, "_terraui_theme_scope", scope)   -- dsl.t:806
```

The bind phase reads these:

```lua
rawget(child.value, "_terraui_theme_scope")    -- bind.t:881
rawget(self, "_terraui_id_mode")               -- bind.t:1047
```

These are hidden semantic inputs. They affect the bind output but aren't
part of the ASDL type definition. Memoize wouldn't see them.

**Fix: add these fields to the ASDL schema.**

- `_terraui_id_mode` → add `id_mode: string?` to `Decl.Node`
  (or an `IdMode` flags type)
- `_terraui_theme_scope` → add `theme_scope: ThemeScope?` to `Decl.WidgetCall`
  (this already exists on `Decl.Node` — the DSL is attaching it to
  WidgetCall children instead)

### 3.2 `_stable_id_labels` on Plan.Component

```lua
comp._stable_id_labels = stable_id_labels   -- plan.t:154
```

This is debug metadata monkey-patched after construction. It's not
semantic (doesn't affect compilation), but it still violates the no-hidden-state
rule.

**Fix: either add `stable_id_labels` to `Plan.Component`'s fields, or
keep it in a separate debug side-table keyed by the Component.**

### 3.3 `__terraui_fragment` and `__terraui_scope`

These are DSL-internal markers on plain Lua tables (not ASDL values).
They never reach the ASDL tree, so they're not a schema violation —
they're DSL implementation details. **OK as-is.**

---

## 4. Opaque Mutable Context Parameters

Every method takes `ctx: BindCtx`, `ctx: PlanCtx`, or `ctx: CompileCtx`.
These are Lua tables registered as opaque `extern` types.

### BindCtx (15+ mutable fields)

```lua
_param_slots, _param_types, _state_slots, _state_types,
_widget_defs, _theme_defs, _theme_stack, _part_style_stack,
_bound_widget_state, _next_param, _next_state, _next_node_id,
_next_widget_id, _path_stack, _named_scopes, _widget_frames,
_override_ids, _renderer, _text_backend
```

BindCtx is a stack machine that expands widgets, resolves themes, allocates
IDs. Every `bind()` call mutates it. This is inherent to widget elaboration —
you can't avoid stateful context when expanding recursive widget definitions.

**But the ctx should not leak into the schema method signature.** The public
boundary is `Component:bind(renderer, text_backend_key)`, which internally
creates a BindCtx and runs the traversal. Sub-component methods that need
ctx are implementation details, not schema boundaries.

### PlanCtx (node table + side tables + counters)

Same pattern. Tree flattening requires index allocation. The public boundary
is `Component:plan()`.

### CompileCtx (plan + types + frame symbol)

Slightly better — it's mostly read-only after construction. But it's still
an opaque ctx.

**Fix: The 3 public Component-level methods take explicit primitive params.
Internal methods can still use ctx — they're not schema methods.**

---

## 5. Extern Types

Current externs:

```
extern TerraType = terralib.types.istype
extern TerraQuote = terralib.isquote
extern BindCtx = is_bind_ctx      -- function(v) return type(v) == "table" end
extern PlanCtx = is_plan_ctx      -- same
extern CompileCtx = is_compile_ctx -- same
```

The Ctx externs accept any table. This is an empty check — it validates nothing.

**Fix: Remove BindCtx, PlanCtx, CompileCtx from externs.** They don't
appear in the ASDL type tree (no field has type BindCtx). They only appear
in method signatures. With only 5 schema methods and explicit params, these
externs are unnecessary.

---

## 6. Kernel Compile Products

Current Kernel types:

```
RuntimeTypes = (params_t, state_t, frame_t, input_t, node_t,
                clip_state_t, scroll_state_t, hit_t)
Kernels = (init_fn, layout_fn, input_fn, hit_test_fn, run_fn)
Component = (key, types, rects, borders, texts, images, scissors, customs, kernels)
```

The compiler pattern says compile products should be `{ fn, state_t }`.
Currently:

- `Kernels` holds 5 TerraQuotes (init, layout, input, hit_test, run).
  These are quotes pointing to Terra functions.
- `RuntimeTypes` holds 8 TerraTypes. These are the state layout.
- 6 stream records hold cmd types + emit quotes.

**Issues:**

1. `frame_t` is the real `state_t` — the single struct that owns all runtime
   state. The other types in RuntimeTypes (params_t, state_t, input_t, etc.)
   are sub-structs embedded in frame_t. They're derivable from frame_t.

2. `run_fn` is the real `fn` — it calls layout→hit_test→input→layout→hit_test→emit
   in sequence. The sub-functions are derivable.

3. The 6 stream records (RectStream, BorderStream, etc.) hold cmd types and
   emit quotes. But their `emit_fn` fields are currently `stub_q` (a noop).
   They're not actually used — the real emit happens inside run_fn.

**Fix: simplify Kernel to the essentials:**

```
phase Kernel
    record Component
        key: Bound.SpecializationKey
        frame_t: TerraType
        run_fn: TerraQuote
        init_fn: TerraQuote
    unique
    end

    methods
        Component:frame_type() -> TerraType
        Component:run_quote() -> TerraQuote
    end
end
```

The streams and sub-functions are implementation details of compile.t.
The consumer (presenter/backend) only needs frame_t (to allocate state)
and run_fn (to execute a frame). Keep init_fn for state initialization.

RuntimeTypes can be dropped — params_t and state_t are sub-structs of
frame_t, accessible via `terralib.offsetof` if needed. The sub-function
quotes (layout_fn, hit_test_fn, etc.) are inlined into run_fn.

---

## 7. Method Inventory: Schema vs Implementation

### Declared in schema (41 methods)

| Phase | Count | Methods |
|---|---|---|
| Decl→Bound | 22 | Component/Param/StateSlot/Node/Visibility/Layout/Size/Padding/Decor/Border/CornerRadius/Clip/Scroll/ScrollControl/Floating/Input/Leaf/TextLeaf/TextStyle/ImageLeaf/CustomLeaf/Expr :bind |
| Bound→Plan | 8 | Component/Node/Size/Clip/Scroll/ScrollControl/Leaf :plan + Value:plan_binding |
| Plan→Kernel | 9 | Component:compile + Node:compile_layout/compile_hit + SizeRule:compile_axis + Paint:compile_emit + InputSpec:compile_input + ClipSpec:compile_apply/compile_emit_begin/compile_emit_end |
| Kernel | 2 | Component:frame_type + Component:run_quote |

### Actually implemented but NOT declared (>25 methods)

- `Plan.Binding:compile_number/bool/color/string/vec2` (5 parent + ~20 variant overrides)
- `Plan.TextSpec:compile_measure_width/measure_height_for_width/compile_emit` (3)
- `Plan.ImageSpec:compile_emit` (1)
- `Plan.CustomSpec:compile_emit` (1)
- `Plan.FloatSpec:compile_place` (1)
- `Plan.ScrollSpec:compile_apply/compile_input` (2)
- `Plan.ScrollControlSpec:compile_input` (1)
- `CompileCtx` helper methods (15+ methods on the ctx, not the ASDL types)

### Recommended: 5 schema-declared methods

```
Decl.Component:bind(renderer: string, text_backend_key: string) -> Bound.Component
Bound.Component:plan() -> Plan.Component
Plan.Component:compile(text_backend_key: string) -> Kernel.Component
Kernel.Component:frame_type() -> TerraType
Kernel.Component:run_quote() -> TerraQuote
```

Everything else: plain ASDL methods installed by implementation modules.

---

## 8. Structural Issues in ASDL Types

### 8.1 Decl.Child sum type mixes levels of abstraction

```
Child = NodeChild { value: Node }
      | WidgetChild { value: WidgetCall }
      | SlotRef { name: string }
```

WidgetChild and SlotRef are elaboration-time concepts. After bind, they
don't exist — Bound has only `Node*` children. This is correct narrowing.
But `WidgetCall` carries widget expansion details (props, styles, slots)
that are really DSL machinery.

**Verdict: OK.** Decl is the user-facing phase. Widgets and slots are
real user concepts. They narrow correctly in Bound.

### 8.2 Plan.Node has 26 fields

```
index, parent, first_child, child_count, subtree_end,
axis, width, height, padding_left/top/right/bottom, gap,
align_x, align_y, guard_slot, paint_slot, input_slot,
clip_slot?, scroll_slot?, scroll_control_slot?, text_slot?,
image_slot?, custom_slot?, float_slot?, aspect_ratio?
```

This is a lot of fields. 9 optional slots are essentially a tagged-union-
as-optionals pattern. But for a flat indexed table used by code generation,
this is the natural representation — each slot is an index into a side
table. The compiler iterates `plan.nodes` and accesses slots directly.

**Verdict: OK for compilation, but could benefit from splitting the
slot indices into a separate record.** Not blocking.

### 8.3 Plan.Binding.Expr wraps arbitrary ops

```
Expr { op: string, args: Binding* }
```

`op` is a string dispatched at compile time. The possible ops are fixed
(+, -, *, /, max, min, >, <, >=, <=, ==, !=, not, and, or, select).
Using a string means the compiler must have a big switch. An enum would
be more type-safe.

**Verdict: minor issue. The string dispatch happens at compile time (Lua),
not runtime. The generated Terra code has no string dispatch. OK for now.**

### 8.4 Decl.Node.id_mode missing from schema

As noted in §3.1: `_terraui_id_mode` is monkey-patched but should be
a schema field.

**Fix: `id_mode: IdMode?` where `IdMode = AutoMode | KeyMode | AnchorMode`
or simply `id_mode: string?`.**

Actually — looking at usage, `id_mode` is either `"auto"`, `"key"`, or
`"anchor"`. This could be a flags type. But `string?` is simpler and
sufficient since it's only consumed by bind.t.

---

## 9. Summary of Required Changes

### Must fix (pattern violations)

1. **Add memoize at Component boundaries.** The 3 phase-transition methods
   (bind, plan, compile) must be memoized.

2. **Reduce schema methods to 5.** Only Component-level boundaries + 2 Kernel
   accessors.

3. **Explicit params on public methods.** No opaque ctx in schema signatures.

4. **Eliminate rawset/rawget on ASDL values.** Add missing fields to schema:
   - `id_mode: string?` on `Decl.Node`
   - `theme_scope: ThemeScope?` on `Decl.WidgetCall`

5. **Remove BindCtx/PlanCtx/CompileCtx externs.** They're not in the type tree.

### Should fix (cleanup)

6. **Simplify Kernel types.** Drop RuntimeTypes, streams, sub-function
   records. Keep only `{ key, frame_t, run_fn, init_fn }`.

7. **Add `doc` to all types and methods.**

8. **Add `fallback` to the 3 phase-transition methods.**

9. **Move `_stable_id_labels` into the schema or a side table.**

### Nice to have (future)

10. Replace `Plan.Binding.Expr.op: string` with an enum.

11. Split Plan.Node's 9 optional slot fields into a sub-record.

---

## 10. Recommended New Schema Shape

```
schema TerraUI
    doc "Compiler-backed UI framework. Decl → Bound → Plan → Kernel."

    extern TerraType = terralib.types.istype
    extern TerraQuote = terralib.isquote

    phase Decl
        doc "User-authored declarative UI tree."

        -- [all current Decl types, plus:]
        -- Node gets: id_mode: string?
        -- WidgetCall gets: theme_scope: ThemeScope?

        methods
            doc "Decl → Bound: widget elaboration, ID resolution, theme cascading."
            Component:bind(renderer: string, text_backend_key: string) -> Bound.Component
                doc "Elaborate widgets, resolve IDs, slot params/state."
                status = "real"
                impl = ...
                fallback = ...
        end
    end

    phase Bound
        doc "Elaborated UI tree. Widgets expanded, IDs resolved, params slotted."
        -- [all current Bound types unchanged]

        methods
            doc "Bound → Plan: flatten tree to indexed tables."
            Component:plan() -> Plan.Component
                doc "Flatten bound tree to indexed node table with side tables."
                status = "real"
                impl = ...
                fallback = ...
        end
    end

    phase Plan
        doc "Flat indexed node table with side tables. Ready for compilation."
        -- [all current Plan types unchanged]

        methods
            doc "Plan → Kernel: generate Terra types and functions."
            Component:compile(text_backend_key: string) -> Kernel.Component
                doc "Compile plan to Terra runtime types and execution functions."
                status = "real"
                impl = ...
                fallback = ...
        end
    end

    phase Kernel
        doc "Compiled output. Terra types and functions ready for execution."

        record Component
            key: Bound.SpecializationKey
            frame_t: TerraType
            init_fn: TerraQuote
            run_fn: TerraQuote
        unique
        end

        methods
            doc "Kernel accessors."
            Component:frame_type() -> TerraType
                doc "Return the frame struct type for allocation."
                status = "real"
                impl = function(self) return self.frame_t end
            Component:run_quote() -> TerraQuote
                doc "Return the run function quote for execution."
                status = "real"
                impl = function(self) return self.run_fn end
        end
    end
end
```
