# TerraUI

Compiler-backed immediate-mode UI design + early schema tooling for Terra.

## Current status

This repository currently contains:

- the split TerraUI architecture/design docs in `docs/design/`
- a working Terra language extension for validated ASDL authoring in `lib/schema.t`
- the TerraUI schema written in that DSL in `lib/terraui_schema.t`
- an emitter/check tool for the generated raw ASDL in `tools/emit_terraui_asdl.t`
- smoke/validation tests in `tests/`

This is still an early design-and-infrastructure repository. The first implemented code is the **schema DSL**, not the UI runtime/compiler yet.

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
