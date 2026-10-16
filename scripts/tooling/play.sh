#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
exec "$GODOT_BIN" --path "$REPO_ROOT" "${@}"
