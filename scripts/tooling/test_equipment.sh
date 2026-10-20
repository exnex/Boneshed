#!/usr/bin/env bash
# Rendered equipment placement: real victory -> salvage -> equip -> next duel, then
# close-ups checked against the resolved builds (Marrow left, sword right).
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/equipment-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new evidence directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
def run(name, args, seconds=200):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == 0 and 'ERROR:' not in text, (name, result.returncode)
    print(f'{name}: expected exit 0 confirmed', flush=True)
    return text
run('import', [engine, '--headless', '--path', repo, '--editor', '--import'])
text = run('capture', ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine, '--path', repo,
    '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy',
    '--script', 'res://scripts/qa/equipment_capture.gd', '--', '--evidence-dir=' + str(output / 'rendered')])
assert 'llvmpipe' in text, 'Software renderer not confirmed'
assert len(list((output / 'rendered').glob('*.png'))) == 6
shots = {s['shot']: s['fighters'] for s in json.loads((output / 'rendered/placement.json').read_text())}
for name, fighter in shots['2_after_equip_front'].items():
    assert fighter['equipped'] == {'arm_l': 'item.marrow_arm', 'hand_r': 'item.notched_sword'}, (name, fighter)
    assert fighter['marrow_root_x'] < 0 < fighter['sword_hand_x'] and not fighter['off_arm_visible'], (name, fighter)
assert not shots['1_before_salvage_front']['Pilgrim']['marrow_visible']
assert all(not f['disagreements'] for s in shots.values() for f in s.values())
print('Rendered equipment placement agrees with resolved builds for both fighters.')
PY
