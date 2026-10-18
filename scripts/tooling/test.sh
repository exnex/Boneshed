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
def run(name, args, expected=0, required=None, seconds=60, expected_error=None):
    # timeout and subprocess preserve the engine's outcome; logs cannot mask failures.
    with (output/f'{name}.log').open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/f'{name}.log').read_text()
    records = []
    for line in text.splitlines():
        if line.startswith('{'):
            records.append(json.loads(line))
    assert result.returncode == expected, f'{name}: exit {result.returncode}, see {output/name}.log'
    assert 'SCRIPT ERROR:' not in text, f'{name}: script errors in log'
    errors = [line for line in text.splitlines() if line.startswith('ERROR:')]
    assert (len(errors) == 1 and expected_error in errors[0]) if expected_error else not errors, f'{name}: unexpected engine errors in log'
    if required:
        required(records)
    results.append({'run': name, 'exit': result.returncode, 'expected_exit': expected})
    print(f'{name}: expected exit {expected} confirmed', flush=True)

base = [engine, '--headless', '--path', repo]
def positive(records):
    summary = next(r for r in records if r.get('summary'))
    assert summary['passed'] >= 60 and summary['failed'] == 0
run('import', base + ['--editor', '--import'])
def integration_checks(records):
    summary = next(r for r in records if r.get('summary'))
    assert summary['passed'] == 532 and summary['failed'] == 0
run('combat_builds', base + ['--script', 'res://scripts/qa/combat_build_tests.gd'], required=integration_checks)
run('adapter_mutations', ['python3', str(pathlib.Path(repo)/'scripts/qa/adapter_mutations.py'), engine, repo, str(output/'adapter-mutations')], seconds=180)
def invalid_startup(records):
    assert any(r.get('check') == 'invalid_startup_creates_no_fighters_or_world' and r['passed'] for r in records)
run('invalid_build_startup', base + ['--script', 'res://scripts/qa/combat_build_tests.gd', '--', '--invalid-startup'],
    expected=1, required=invalid_startup, expected_error='Courtyard build initialization failed:')
run('invalid_state_startup', base + ['--script', 'res://scripts/qa/combat_build_tests.gd', '--', '--invalid-state-startup'],
    expected=1, required=invalid_startup, expected_error='Courtyard build initialization failed:')
def combat_checks(records):
    summary = next(r for r in records if r.get('summary'))
    assert summary['passed'] == 118 and summary['failed'] == 0
run('combat', base + ['--script', 'res://scripts/qa/combat_tests.gd'], required=combat_checks)
for control, check in [('guard', 'guard_mitigates_damage'), ('deflect', 'timed_deflection'), ('phase', 'windup_cannot_damage'),
                       ('toggle', 'rapid_toggle_cannot_refresh_deflect'), ('rear', 'guard_arc_dot_-1.0'),
                       ('poise', 'heavy_commitment_true_0.2')]:
    def negative(records, label=check):
        assert any(r.get('check') == label and r['passed'] is False for r in records)
        assert any(r.get('summary') and r['failed'] > 0 for r in records)
    run(f'negative_{control}', base + ['--script', 'res://scripts/qa/combat_tests.gd', '--', f'--negative={control}'], expected=1, required=negative)
def encounter_checks(records):
    checks = [r for r in records if r.get('scenario') == 'iteration2_regression']
    assert len(checks) == 8 and all(r['passed'] for r in checks)
probe = base + ['--fixed-fps', '60', '--script', 'res://scripts/qa/adversarial_probe.gd', '--', '--only=iteration2_regressions']
run('encounters', probe + [f'--evidence-dir={output}/encounters'], required=encounter_checks)
def defense_negative(records):
    assert any(r.get('check') == 'attack_only_loses_1.85_period_2' and r['passed'] is False for r in records)
run('negative_defense', probe + ['--negative=defense', f'--evidence-dir={output}/negative-defense'], expected=1, required=defense_negative)
timing_args = ['--fixed-fps', '60', '--script', 'res://scripts/qa/attack_timing_test.gd', '--']
run('timing_headless', base + timing_args + [f'--evidence-dir={output}/timing-headless'], required=positive)
def visual_negative(records):
    assert any(r.get('check') == 'basic_first_contact_matches_extended_blade' and r['passed'] is False for r in records)
run('negative_visual', base + timing_args + ['--negative=visual', f'--evidence-dir={output}/negative-visual'], expected=1, required=visual_negative)
run('graphical', ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
    '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy',
    '--fixed-fps', '60', 'res://scenes/courtyard.tscn', '--', '--qa', f'--evidence-dir={output}'], seconds=int(os.environ.get("BONESHED_GRAPHICAL_TIMEOUT", "180")))
records = json.loads((output/'graphical.json').read_text())
summary = next(r for r in records if r.get('summary'))
assert summary['passed'] == 111 and summary['failed'] == 0
assert len(list(output.glob('*.png'))) == 5
assert 'llvmpipe' in (output/'graphical.log').read_text(), 'Software renderer not confirmed'
run('timing_rendered', ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
    '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy'] + timing_args +
    [f'--evidence-dir={output}/timing-rendered'], required=positive, seconds=120)
assert len(list((output/'timing-rendered').glob('*/frame_*.png'))) >= 36
(output/'runs.json').write_text(json.dumps(results, indent=2)+'\n')
print(f'All checks passed; evidence: {output}')
PY
