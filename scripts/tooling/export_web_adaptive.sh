#!/usr/bin/env bash
# Isolated Adaptive Combat Lab Web export; never edit production project files.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/web-adaptive-combat}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
test -z "$(ls -A "$output")" || { echo 'Use a new empty export directory.' >&2; exit 1; }
staging="$(mktemp -d /tmp/boneshed-adaptive-web.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
cp -a "$REPO_ROOT/project.godot" "$REPO_ROOT/export_presets.cfg" "$REPO_ROOT/scripts" "$REPO_ROOT/scenes" "$REPO_ROOT/data" "$staging/"
python3 - "$staging" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
project = root/'project.godot'
source = project.read_text()
old = 'run/main_scene="res://scenes/first_expedition.tscn"'
assert source.count(old) == 1, "Unexpected default scene"
project.write_text(source.replace(old, 'run/main_scene="res://scenes/adaptive_combat_lab.tscn"'))
presets = root/'export_presets.cfg'
source = presets.read_text()
old = 'include_filter="data/builds/*.json,data/worldgen/*.json,data/melee_lab/*.json"'
assert source.count(old) == 1, "Unexpected Web include filter"
presets.write_text(source.replace(old, old[:-1] + ',data/adaptive_lab/*.json"'))
PY
timeout 120 "$GODOT_BIN" --headless --path "$staging" --editor --import
timeout 180 "$GODOT_BIN" --headless --path "$staging" --export-release Web "$output/index.html"
touch "$output/.nojekyll"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$output" Web
