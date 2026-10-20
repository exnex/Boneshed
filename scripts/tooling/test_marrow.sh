#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/marrow-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, os, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
def run(name, args, expected=0, seconds=60):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected and 'ERROR:' not in text, (name, result.returncode)
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
records = run('rules_progression', base + ['--script', 'res://scripts/qa/marrow_tests.gd'])
assert any(r.get('summary') and r['passed'] == 211 and r['failed'] == 0 for r in records)
run('mutations', ['python3', str(pathlib.Path(repo) / 'scripts/qa/marrow_mutations.py'), engine, repo, str(output / 'mutations')], seconds=180)
args = ['--fixed-fps', '60', '--script', 'res://scripts/qa/marrow_playthrough.gd', '--']
run('input_headless', base + args + ['--evidence-dir=' + str(output / 'headless')])
run('negative_pose', base + args + ['--negative=marrow-visual', '--evidence-dir=' + str(output / 'negative-pose')], expected=1)
negative = json.loads((output / 'negative-pose/summary.json').read_text())
assert negative['failed'] > 0
# Equipment control: a bone drawn on the wrong side must fail the build/visual agreement check.
side = run('negative_equipment', base + args + ['--negative=equipment-side', '--evidence-dir=' + str(output / 'negative-equipment')], expected=1)
assert [r['check'] for r in side if r.get('passed') is False] == ['equipped_marrow_left_sword_right_matches_build'], side
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
run('input_rendered', rendered + args + ['--evidence-dir=' + str(output / 'rendered')], seconds=int(os.environ.get('BONESHED_GRAPHICAL_TIMEOUT', '900')))
for name in ('headless', 'rendered'):
    summary = json.loads((output / name / 'summary.json').read_text())
    assert summary['failed'] == 0 and summary['ticks'] < 10000
images = list((output / 'rendered').glob('*.png'))
assert len(images) == 8
assert len(list((output / 'rendered/enemy-lunge').glob('frame_*.png'))) >= 20
assert len(list((output / 'rendered/player-lunge').glob('frame_*.png'))) >= 20
# Pausing for screenshots must not change the simulated input/combat progression.
headless = json.loads((output / 'headless/trace.json').read_text())
rendered_trace = json.loads((output / 'rendered/trace.json').read_text())
assert headless == rendered_trace, 'rendered and headless input traces differ'
print('Shared lunge, progression, mutation, pose and equipment negative controls and rendered input trace checks passed.')
PY
