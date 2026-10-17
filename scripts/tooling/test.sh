#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
mkdir -p "$REPO_ROOT/artifacts"
touch "$REPO_ROOT/artifacts/.gdignore"
run_dir="${1:-$REPO_ROOT/artifacts/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$run_dir"
run_dir="$(cd "$run_dir" && pwd)"
test -z "$(ls -A "$run_dir")" || { echo 'Use a new empty evidence directory.' >&2; exit 1; }
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$run_dir" <<'PY'
import json, os, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
results = []
def run(name, args, expected=0, required=None, seconds=60):
    # timeout and subprocess preserve the engine's outcome; logs cannot mask failures.
    with (output/f'{name}.log').open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/f'{name}.log').read_text()
    records = []
    for line in text.splitlines():
        if line.startswith('{'):
            records.append(json.loads(line))
    assert result.returncode == expected, f'{name}: exit {result.returncode}, see {output/name}.log'
    assert 'SCRIPT ERROR:' not in text and 'ERROR:' not in text, f'{name}: engine errors in log'
    if required:
        required(records)
    results.append({'run': name, 'exit': result.returncode, 'expected_exit': expected})
    print(f'{name}: expected exit {expected} confirmed', flush=True)

base = [engine, '--headless', '--path', repo]
def positive(records):
    summary = next(r for r in records if r.get('summary'))
    assert summary['passed'] >= 30 and summary['failed'] == 0
run('import', base + ['--editor', '--import'])
run('combat', base + ['--script', 'res://scripts/qa/combat_tests.gd'], required=positive)
for control, check in [('guard', 'guard_mitigates_damage'), ('deflect', 'timed_deflection'), ('phase', 'windup_cannot_damage')]:
    def negative(records, label=check):
        assert any(r.get('check') == label and r['passed'] is False for r in records)
        assert any(r.get('summary') and r['failed'] > 0 for r in records)
    run(f'negative_{control}', base + ['--script', 'res://scripts/qa/combat_tests.gd', '--', f'--negative={control}'], expected=1, required=negative)
run('graphical', ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
    '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy',
    '--fixed-fps', '60', '--', '--qa', f'--evidence-dir={output}'], seconds=int(os.environ.get("BONESHED_GRAPHICAL_TIMEOUT", "180")))
records = json.loads((output/'graphical.json').read_text())
summary = next(r for r in records if r.get('summary'))
assert summary['passed'] >= 30 and summary['failed'] == 0
assert len(list(output.glob('*.png'))) == 5
assert 'llvmpipe' in (output/'graphical.log').read_text(), 'Software renderer not confirmed'
(output/'runs.json').write_text(json.dumps(results, indent=2)+'\n')
print(f'All checks passed; evidence: {output}')
PY
