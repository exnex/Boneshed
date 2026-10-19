#!/usr/bin/env bash
# Key-pose combat presentation: pure/scene checks, two negative controls, and
# close-up rendered captures with contact sheets for visual review.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/combat-motion-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
def run(name, args, expected=0, seconds=180):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected and 'ERROR' not in text, (name, result.returncode)
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
script = ['--script', 'res://scripts/qa/combat_motion_tests.gd', '--']
records = run('checks', base + script)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == 63, summary
for mutation, prefix in [('contact', 'first_active_tick_at_contact_pose_'), ('hold', 'loaded_hold_is_visible_')]:
    records = run('negative_' + mutation, base + script + ['--negative=' + mutation], expected=1)
    failures = [r['check'] for r in records if r.get('passed') is False]
    assert failures and any(f.startswith(prefix) for f in failures), (mutation, failures)
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine, '--path', repo,
            '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--fixed-fps', '60',
            '--script', 'res://scripts/qa/combat_motion_capture.gd', '--']
for scene in ['courtyard', 'salvage_courtyard']:
    run('capture_' + scene, rendered + [f'--evidence-dir={output}/{scene}', f'--scene={scene}'], seconds=900)
    frames = sorted((output / scene / 'side' / 'light').glob('frame_*.png'))
    assert len(frames) >= 30, len(frames)
    for view in ['side', 'shoulder']:
        for clip in sorted(p for p in (output / scene / view).iterdir() if p.is_dir()):
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', str(clip / 'frame_*.png'),
                            '-vf', 'crop=900:600:190:60,scale=300:-1,tile=8x6:padding=2', '-frames:v', '1',
                            str(output / f'sheet_{scene}_{view}_{clip.name}.png')], check=True)
print('Combat motion checks, negative controls and rendered captures passed.')
PY
