#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

out="/tmp/terraui_demo_smoke"
rm -f "$out"
terra examples/build_sdl_gl_demo.t "$out" >/tmp/terraui_demo_build.log
"$out" 2 hidden
rm -f "$out"

echo "aot demo smoke test passed"
