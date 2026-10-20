#!/usr/bin/env bash
# Opens the isolated directional melee lab (experimental). The default game entry point
# (First Expedition, F5 / play.sh) is unchanged.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
exec "$GODOT_BIN" --path "$REPO_ROOT" res://scenes/melee_lab.tscn "${@}"
