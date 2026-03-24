# TerraUI

Compiler-backed immediate-mode UI design + early schema tooling for Terra.

## Current status

This repository currently contains:

- the split TerraUI architecture/design docs in `docs/design/`
- the validated ASDL schema DSL in `lib/schema.t`
- the TerraUI schema in `lib/terraui_schema.t`
- the working compiler pipeline in:
  - `lib/bind.t`
  - `lib/plan.t`
  - `lib/compile.t`
  - `lib/dsl.t`
  - `lib/terraui.t`
- a reusable SDL3 + OpenGL + SDL_ttf backend/session module for AOT demos in:
  - `lib/sdl_gl_backend.t`
- first-class `Decl`-level widget authoring with bind-time elaboration:
  - `ui.widget(...)`
  - `ui.widget_prop(...)`
  - `ui.widget_slot(...)`
  - `ui.use(...)`
  - `ui.slot(...)`
  - `ui.scope(...)`
  - `scope:child(...)`
  - `scope:anchor(...)`
  - public `key = ...` and `anchor = ...` authoring
- CPU-side presenter and backend replay helpers in:
  - `lib/presenter.t`
  - `lib/opengl_backend.t`
  - `lib/direct_c_backend.t`
  - `lib/sdl_gl_backend.t`
- an ahead-of-time SDL+OpenGL demo builder in `examples/build_sdl_gl_demo.t`
- tests in `tests/`

The repository now includes a runnable AOT demo path: Terra is used as the compiler, and the produced executable runs SDL3 + OpenGL directly.

Text wrapping is modeled at the TerraUI level and measured through a pluggable compile-time `text_backend` service. The default backend is approximate; the SDL demo installs an SDL_ttf-backed text backend, and the runtime frame carries an explicit `text_backend_state` pointer so measurement can use owned backend/session state instead of global caches.

## Repository layout

- `lib/schema.t` — Terra language extension for schema/ASDL authoring
- `lib/terraui_schema.t` — TerraUI schema written in the DSL
- `tools/emit_terraui_asdl.t` — emit/check generated raw ASDL
- `tools/run_tests.sh` — run the current test suite
- `generated/terraui-runtime.asdl` — checked-in emitted raw ASDL snapshot
- `tests/` — schema DSL and TerraUI schema tests
- `docs/design/` — architecture and design set
- `starter-conv.txt` — original design conversation source material
- `terra-compiler-pattern.md` — reference pattern used for the implementation/design

## Quick start

### Run tests

```bash
make test
```

### Run the SDL+OpenGL demo directly in the Terra process

If your Terra build can link/run SDL + OpenGL in-process, this is now the primary demo path:

```bash
make demo-direct
```

Direct-path smoke run:

```bash
make demo-direct-smoke
```

You can also invoke it manually and pass the same runtime args as the built executable:

```bash
terra examples/run_sdl_gl_demo.t
terra examples/run_sdl_gl_demo.t 120
terra examples/run_sdl_gl_demo.t 2 hidden
```

To override the font used while capturing the demo entrypoint from `examples/build_sdl_gl_demo.t`:

```bash
terra examples/run_sdl_gl_demo.t --font /path/to/font.ttf
terra examples/run_sdl_gl_demo.t --font /path/to/font.ttf 2 hidden
```

### Build the SDL+OpenGL AOT demo

AOT is still available when you want a standalone executable:

```bash
make demo
./examples/sdl_gl_demo
```

To smoke-run it headlessly enough for CI/local verification:

```bash
make demo-smoke
```

You can also build to a custom output path:

```bash
terra examples/build_sdl_gl_demo.t /tmp/terraui_demo
/tmp/terraui_demo
```

Pass a frame count and optional `hidden` flag to auto-exit:

```bash
./examples/sdl_gl_demo 120
./examples/sdl_gl_demo 2 hidden
```

### Widget example

```lua
local terraui = require("lib/terraui")
local ui = terraui.dsl()

local Card = ui.widget("Card") {
    state = {
        ui.state("gap") { type = ui.types.number, initial = 8 },
    },
    slots = {
        ui.widget_slot("header"),
        ui.widget_slot("children"),
    },
    root = ui.column { key = ui.stable("root"), gap = ui.state_ref("gap") } {
        ui.slot("header"),
        ui.slot("children"),
    },
}

local inspector = ui.scope("inspector")

local decl = ui.component("demo") {
    widgets = { Card },
    root = ui.column {} {
        ui.use("Card") { key = inspector } {
            header = {
                ui.label { text = "Inspector" },
            },
            children = {
                ui.label { anchor = "body_label", text = "Body" },
            },
        },
    },
}
```

Widget definitions live in `Decl`, but bind elaborates them back into canonical nodes and state slots before planning and compilation.

For identity and targeting, the DSL now centers on:
- `key = ...` for instance identity
- `anchor = ...` for local target names inside the nearest keyed scope
- `local card = ui.scope("card")`
- `card:child("nested_instance")`
- `card:anchor("body")`


A focused non-SDL example also lives at:

```bash
terra examples/widget_composition_example.t
```

### Emit the raw ASDL generated from the DSL

```bash
make asdl
```

### Write emitted ASDL to a file

```bash
make asdl OUT=/tmp/terraui.asdl
```

### Refresh the checked-in ASDL snapshot

```bash
make snapshot
```

### Check the emitted schema against the checked-in snapshot

```bash
make check
```

### Check an arbitrary ASDL file against the current emitted schema

```bash
make check FILE=/tmp/terraui.asdl
```

You can also compile with a custom text backend:

```lua
local kernel = terraui.compile(decl, {
    text_backend = my_text_backend,
})
```

A text backend is a Lua table with:
- `key`
- `measure_width(ctx, text_spec)`
- `measure_height_for_width(ctx, text_spec, max_width_q)`

If the backend needs runtime-owned resources, generated kernels can access them through `frame.text_backend_state`.

You can still invoke the Terra tools directly if you prefer:

```bash
./tools/run_tests.sh
terra tools/emit_terraui_asdl.t
terra tools/emit_terraui_asdl.t /tmp/terraui.asdl
terra tools/emit_terraui_asdl.t --check generated/terraui-runtime.asdl
terra tools/emit_terraui_asdl.t --check /tmp/terraui.asdl
```

## Design docs

Start with:

- `ARCHITECTURE.md`
- `docs/design/00-overview.md`
- `docs/design/11-schema-dsl.md`
- `docs/design/12-backend-contracts.md`

## Notes

The DSL currently supports:

- `extern`
- `phase`
- `record`
- `enum`
- `flags`
- `methods`
- `unique`
- field defaults via `=`
- field constraints via `where ...`

Example:

```lua
import "lib/schema"

local schema Demo
    phase Decl
        record Config
            a: number = 1
            b: number = 2 where 0 <= b <= 10
        end
    end
end
```
