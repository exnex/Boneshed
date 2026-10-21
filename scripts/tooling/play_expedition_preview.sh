#!/usr/bin/env bash
# Opens the isolated procedural expedition preview; the default scene is unchanged.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
exec "$GODOT_BIN" --path "$REPO_ROOT" res://scenes/expedition_preview.tscn "${@}"
