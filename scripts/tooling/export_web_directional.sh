#!/usr/bin/env bash
# Exports the experimental directional expedition as its own Web build, from a
# disposable copy whose start scene and data include filter are patched. The working
# tree's project.godot and export_presets.cfg (the production export) are never edited.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/web-directional-expedition}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
test -z "$(ls -A "$output")" || { echo 'Use a new empty export directory.' >&2; exit 1; }
staging="$(mktemp -d /tmp/boneshed-directional-web.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
cp -a "$REPO_ROOT/project.godot" "$REPO_ROOT/export_presets.cfg" "$REPO_ROOT/scripts" "$REPO_ROOT/scenes" "$REPO_ROOT/data" "$staging/"
python3 - "$staging" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
project = root/'project.godot'
text = project.read_text()
expected = 'run/main_scene="res://scenes/first_expedition.tscn"'
assert text.count(expected) == 1, 'Unexpected default scene: refusing to export the wrong build'
project.write_text(text.replace(expected, 'run/main_scene="res://scenes/directional_expedition.tscn"'))
presets = root/'export_presets.cfg'
text = presets.read_text()
expected = 'include_filter="data/builds/*.json,data/worldgen/*.json,data/melee_lab/*.json"'
assert text.count(expected) == 1, 'Unexpected Web include filter'
presets.write_text(text.replace(expected, expected[:-1] + ',data/expedition_preview/*.json,data/directional_expedition/*.json"'))
PY
timeout 120 "$GODOT_BIN" --headless --path "$staging" --editor --import
timeout 180 "$GODOT_BIN" --headless --path "$staging" --export-release Web "$output/index.html"
touch "$output/.nojekyll"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$output" Web
