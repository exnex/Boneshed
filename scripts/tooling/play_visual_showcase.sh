#!/usr/bin/env bash
# Opens the isolated visual showcase (experimental). The default game entry point
# (First Expedition, F5 / play.sh), the melee lab and the web exports are unchanged.
#   bash scripts/tooling/play_visual_showcase.sh                 GL Compatibility (project default)
#   bash scripts/tooling/play_visual_showcase.sh --forward       Forward+ for this run only (desktop GPU, Vulkan)
#   ... -- --quality=high|medium|low                             quality preset (default: high on Forward+, medium otherwise)
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
renderer=(--rendering-method gl_compatibility)
if [ "${1:-}" = "--forward" ]; then
    renderer=(--rendering-method forward_plus)
    shift
fi
exec "$GODOT_BIN" --path "$REPO_ROOT" "${renderer[@]}" res://scenes/visual_showcase.tscn "${@}"
