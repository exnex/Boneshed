#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
preset="${2:-Web}"
test "$preset" = Web || test "$preset" = 'Web QA'
output="${1:-$REPO_ROOT/artifacts/web}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
test -z "$(ls -A "$output")" || { echo 'Use a new empty export directory.' >&2; exit 1; }
timeout 90 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import
timeout 120 "$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$preset" "$output/index.html"
# No repository files are copied to the deployment directory.
touch "$output/.nojekyll"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$output" "$preset"
