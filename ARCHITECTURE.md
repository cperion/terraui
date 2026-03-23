# TerraUI Architecture Docs

This repository now uses a split architecture/design set rather than a single monolithic draft.

Current implementation files of note:
- `lib/schema.t`
- `lib/terraui_schema.t`
- `tools/emit_terraui_asdl.t`
- `tests/schema_smoke.t`
- `tests/schema_validation.t`
- `tests/schema_defaults_constraints.t`
- `tests/terraui_schema_smoke.t`

## Canonical docs

- `docs/design/00-overview.md`
- `docs/design/01-ir-and-pipeline.md`
- `docs/design/02-layout-input-and-rendering.md`
- `docs/design/03-runtime-backends-opengl.md`
- `docs/design/04-prototype-and-open-questions.md`
- `docs/design/05-full-asdl-spec.md`
- `docs/design/06-validation-rules.md`
- `docs/design/07-method-contracts.md`
- `docs/design/08-context-contracts.md`
- `docs/design/09-authoring-api.md`
- `docs/design/10-builder-api-reference.md`
- `docs/design/11-schema-dsl.md`
- `docs/design/12-backend-contracts.md`
- `docs/design/13-scroll-and-scroll-areas.md`
- `docs/design/terraui.asdl`

## Notes

These docs were extracted from the **latest design revisions** in `starter-conv.txt`, not from the earlier intermediate draft.

Important final-source changes reflected in the split docs:
- pipeline is `Decl -> Bound -> Plan -> Kernel`
- `Bound` replaces the earlier `Norm` terminology
- `Clip` now covers structural viewport clipping; `Scroll` is implemented as a separate first-class concept, and standard scrollbars/scroll areas live at the widget layer
- `aspect_ratio` is node-level
- `Plan.Node` carries subtree information for correct clip bracketing
- render commands keep split streams but require `seq` for global ordering
- text measurement stays in-kernel, shaping stays in the presenter/font backend

## Suggested reading order

1. `docs/design/00-overview.md`
2. `docs/design/01-ir-and-pipeline.md`
3. `docs/design/05-full-asdl-spec.md`
4. `docs/design/terraui.asdl`
5. `docs/design/06-validation-rules.md`
6. `docs/design/07-method-contracts.md`
7. `docs/design/08-context-contracts.md`
8. `docs/design/09-authoring-api.md`
9. `docs/design/10-builder-api-reference.md`
10. `docs/design/11-schema-dsl.md`
11. `docs/design/02-layout-input-and-rendering.md`
12. `docs/design/03-runtime-backends-opengl.md`
13. `docs/design/12-backend-contracts.md`
14. `docs/design/13-scroll-and-scroll-areas.md`
15. `docs/design/04-prototype-and-open-questions.md`
