#!/usr/bin/env bash
# Opens the isolated directional expedition (preview world + melee lab combat).
# The default scene, the expedition preview and the melee lab are unchanged.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
exec "$GODOT_BIN" --path "$REPO_ROOT" res://scenes/directional_expedition.tscn "${@}"
