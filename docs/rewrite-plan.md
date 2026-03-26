# TerraUI Rewrite Plan: onto `lib/schema.t`

## Current State

TerraUI has the same architectural debt the DAW had before its rewrite:

1. **Schema declares signatures, methods installed externally.** `terraui_schema.t`
   declares 41 method signatures. But zero have `impl`, `fallback`, `status`, or
   `doc`. The bodies live in 3 separate files (`bind.t`, `plan.t`, `compile.t`)
   that directly assign to ASDL class tables: `function Decl.Expr:bind(ctx)`.

2. **Zero memoize boundaries.** None of the 41 declared methods use
   `terralib.memoize`. The compiler pattern requires every public phase-boundary
   method to be memoized. This means TerraUI currently gets no incremental
   recompilation: change one token in a 500-node tree and the entire
   bind→plan→compile chain re-executes.

3. **Opaque ctx parameters.** Every method takes `ctx: BindCtx`, `ctx: PlanCtx`,
   or `ctx: CompileCtx`. These are mutable Lua tables with 15+ fields that
   accumulate state across the traversal. The compiler pattern says: explicit
   semantic parameters only, no opaque mutable ctx.

4. **No fallbacks.** No typed degradation. A bad widget prop or missing theme
   token crashes the entire bind phase.

5. **No docs.** Zero `doc` annotations on types or methods.

6. **`lib/schema.t` was stale.** TerraUI shipped its own 835-line `lib/schema.t`
   vs. the DAW's 2317-line version. Already fixed (copied over), but the schema
   wasn't using any of the new capabilities.

## Pipeline

TerraUI has 4 phases:

```
Decl → Bound → Plan → Kernel
```

| Phase | Role | Method |
|---|---|---|
| Decl | Declarative UI tree (DSL output) | `:bind()` |
| Bound | IDs resolved, params/state slotted, widgets elaborated | `:plan()` |
| Plan | Flat node table, side tables, bindings | `:compile()` |
| Kernel | Terra types + compiled functions | `:frame_type()`, `:run_quote()` |

This is directly analogous to the DAW's 7 phases. Same pattern, smaller domain.

## What the Rewrite Does

### 1. Schema becomes the single source of truth

Every method gets `impl`, `fallback`, `status`, `doc` declared inline in
`terraui_schema.t`. Method bodies move to factory files under `src/`:

```
src/
  decl/           # Decl → Bound bind methods
    component.t
    expr.t
    node.t
    size.t
    leaf.t
    records.t     # Visibility, Layout, Padding, Decor, Border, etc.
  bound/          # Bound → Plan plan methods
    component.t
    node.t
    size.t
    leaf.t
    value.t
  plan/           # Plan → Kernel compile methods
    component.t
    node.t
    binding.t     # compile_number, compile_bool, compile_color, etc.
    size_rule.t
    paint.t
    input.t
    clip.t
    scroll.t
    text.t
    image.t
    custom.t
    float.t
  kernel/         # Kernel accessors
    component.t
```

### 2. Every method gets memoized

The schema DSL already wraps every declared method with `terralib.memoize`.
This is the single biggest win: structural sharing + incremental recompilation
for free. A param change that doesn't affect the layout tree reuses the cached
plan and compiled layout kernels.

### 3. Ctx parameters become explicit

Instead of `bind(ctx: BindCtx)`, methods that need bind-time context should
receive explicit semantic parameters:

- Bind phase: many methods are pure transforms (Expr, Size, Leaf, records).
  Only `Component:bind` and `Node:bind` need context for ID allocation and
  widget elaboration. Those should receive explicit params.
- Plan phase: similar — `Component:plan` orchestrates, leaf methods need a
  node index.
- Compile phase: `CompileCtx` carries the plan + runtime type references.
  This can become explicit plan + types params.

Note: the current `BindCtx` is heavily stateful (widget frame stack, theme
stack, path stack, named scope stack). This is inherent to the elaboration
model — widgets expand inline, themes cascade. The rewrite should keep a
context for the *orchestration* methods (Component:bind, Node:bind) but make
the *leaf* methods pure transforms that don't need ctx.

### 4. Typed fallbacks everywhere

Every method gets a fallback that returns a valid degraded value of its return
type. A broken widget definition or missing theme token degrades locally instead
of crashing the whole component.

### 5. Doc annotations

Every type and method gets a `doc` string.

## Implementation Order

### Phase 1: Schema enrichment
Add `impl`, `fallback`, `status = "real"`, and `doc` to all 41 methods in
`terraui_schema.t`. `impl` references factory files under `src/`.

### Phase 2: Extract method bodies
Move the 124 `function Type:method()` assignments from `bind.t`, `plan.t`,
`compile.t` into factory files under `src/`. Each factory returns a bare
function. The schema's `impl` wires them.

### Phase 3: Add fallbacks
Write typed fallback functions for each method.

### Phase 4: Clean up ctx
Identify which methods truly need ctx and which are pure transforms. Refactor
the pure ones to take explicit params. (This may be a follow-up rather than
part of the initial rewrite.)

### Phase 5: Delete old scaffolding
Remove direct method installation from `bind.t`, `plan.t`, `compile.t`. They
become thin convenience wrappers (or disappear entirely if the schema's public
API suffices).

### Phase 6: Verify
All existing tests pass. `make test` green. Schema loads. Memoize works.

## File Counts

Current:
- `lib/terraui_schema.t`: 891 lines (types + bare signatures)
- `lib/bind.t`: 1191 lines (44 method bodies + BindCtx)
- `lib/plan.t`: 520 lines (28 method bodies + PlanCtx)
- `lib/compile.t`: 2128 lines (52 method bodies + CompileCtx + Terra types)
- Total implementation: ~4730 lines across 3 files

After rewrite:
- `lib/terraui_schema.t`: ~1200 lines (types + enriched method declarations)
- `src/decl/`: ~600 lines (bind methods)
- `src/bound/`: ~400 lines (plan methods)
- `src/plan/`: ~1800 lines (compile methods + Terra types)
- `src/kernel/`: ~100 lines
- `lib/bind.t`: ~50 lines (convenience wrapper)
- `lib/plan.t`: ~50 lines (convenience wrapper)
- `lib/compile.t`: ~50 lines (convenience wrapper)

The total line count stays similar. The difference is structure: one source of
truth, ASDL-shaped implementation tree, memoized boundaries, typed fallbacks.

## Non-Goals

- **No new features.** This is a structural rewrite, not a feature release.
- **No ctx elimination yet.** The stateful BindCtx for widget elaboration stays
  for now. Phase 4 is a follow-up.
- **No DSL changes.** `lib/dsl.t` continues to produce `Decl` trees as before.
- **No backend changes.** `presenter.t`, `sdl_gl_backend.t`, `opengl_backend.t`,
  `direct_c_backend.t` are unaffected.
