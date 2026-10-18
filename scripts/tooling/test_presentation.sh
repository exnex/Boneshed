#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/presentation-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
def run(name, args, expected=0, seconds=120):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected and 'ERROR:' not in text, (name, result.returncode)
    print(f'{name}: expected exit {expected} confirmed', flush=True)
run('import', base + ['--editor', '--import'])
args = ['--fixed-fps', '60', '--script', 'res://scripts/qa/presentation_test.gd', '--']
for name, mutation, expected in [('headless', '', 0), ('negative_pose', 'pose', 1), ('negative_reaction', 'reaction', 1)]:
    run(name, base + args + ['--evidence-dir=' + str(output / name)] + (['--negative=' + mutation] if mutation else []), expected)
    checks = json.loads((output / name / 'checks.json').read_text())
    if mutation:
        label = 'heavy_prepares_above_head' if mutation == 'pose' else 'deflection_has_visible_recoil_and_contact'
        assert any(c.get('check') == label and c['passed'] is False for c in checks)
    else:
        assert checks[-1]['failed'] == 0 and checks[-1]['passed'] >= 300
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
run('rendered', rendered + args + ['--evidence-dir=' + str(output / 'rendered')], seconds=300)
checks = json.loads((output / 'rendered/checks.json').read_text())
assert checks[-1]['failed'] == 0 and checks[-1]['rendered']
print('Presentation, rules isolation, reaction mutations and live camera/input checks passed.')
PY
