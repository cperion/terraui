#!/bin/bash
# Build the Love2D demo UI.
# Can be run from any directory.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAUI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

terra "$TERRAUI_ROOT/tools/build_component.t" \
    "$SCRIPT_DIR/ui_def.t" \
    --prefix demo_ui \
    -o "$SCRIPT_DIR"

echo ""
echo "Run with:  love $SCRIPT_DIR"
