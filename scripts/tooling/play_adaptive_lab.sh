#!/usr/bin/env bash
# Opens the isolated Adaptive Combat Lab (experimental). The default game entry point
# (First Expedition), the other labs, the showcase and the web exports are unchanged.
#   bash scripts/tooling/play_adaptive_lab.sh                         GL Compatibility (project default)
#   bash scripts/tooling/play_adaptive_lab.sh --forward               Forward+ for this run only (desktop GPU, Vulkan)
#   ... -- --player=demo.ribbed_canopy --soul=demo.double_ended_pole --player-marrow
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
renderer=(--rendering-method gl_compatibility)
if [ "${1:-}" = "--forward" ]; then
    renderer=(--rendering-method forward_plus)
    shift
fi
exec "$GODOT_BIN" --path "$REPO_ROOT" "${renderer[@]}" res://scenes/adaptive_combat_lab.tscn "${@}"
