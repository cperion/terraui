#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

terra tests/schema_smoke.t
terra tests/schema_validation.t
terra tests/schema_defaults_constraints.t
terra tests/terraui_schema_smoke.t
