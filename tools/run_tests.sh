#!/usr/bin/env bash
# Runs the headless test suite. Usage: tools/run_tests.sh [--only=<name>]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- "$@"
