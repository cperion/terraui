#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

terra tests/schema_smoke.t
terra tests/schema_validation.t
terra tests/schema_defaults_constraints.t
terra tests/terraui_schema_smoke.t
terra tests/bind_test.t
terra tests/plan_test.t
terra tests/compile_test.t
terra tests/dsl_test.t
terra examples/widget_composition_example.t
terra tests/presenter_test.t
terra tests/opengl_backend_test.t
terra tests/direct_c_backend_test.t
./tests/direct_demo_smoke.sh
./tests/aot_demo_smoke.sh
