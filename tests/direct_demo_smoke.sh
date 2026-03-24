#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

terra examples/run_sdl_gl_demo.t 2 hidden >/tmp/terraui_direct_demo_run.log

echo "direct demo smoke test passed"
