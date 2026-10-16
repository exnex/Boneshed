#!/usr/bin/env bash
# Source from the other tooling scripts; keep state outside the checkout.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${BONESHED_TOOLS:-/workspace/tools}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$TOOLS_ROOT/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$TOOLS_ROOT/config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$TOOLS_ROOT/data}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
export PATH="$TOOLS_ROOT/xvfb/usr/bin:$PATH"
GODOT_BIN="${GODOT_BIN:-$TOOLS_ROOT/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
EXPECTED_GODOT="4.7.2.stable.official.ed1daf0bf"

check_godot() {
    test -x "$GODOT_BIN" || { echo "Run bash scripts/tooling/setup.sh first." >&2; return 1; }
    local actual
    actual="$("$GODOT_BIN" --version)"
    test "$actual" = "$EXPECTED_GODOT" || { echo "Expected $EXPECTED_GODOT, got $actual" >&2; return 1; }
}
