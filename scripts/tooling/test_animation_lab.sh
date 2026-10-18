#!/usr/bin/env bash
# Animation lab: fetch the pinned trial asset, run deterministic checks plus a negative
# control, and render every sequence with Movie Maker. Independent of combat tests.
# ffmpeg (optional, system tool) turns frames into MP4 clips and contact sheets.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
bash "$(dirname "$0")/fetch_animation_trial.sh" >/dev/null
mkdir -p "$REPO_ROOT/artifacts"
touch "$REPO_ROOT/artifacts/.gdignore"
run_dir="${1:-$REPO_ROOT/artifacts/animation-lab-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$run_dir"
run_dir="$(cd "$run_dir" && pwd)"
test -z "$(ls -A "$run_dir")" || { echo 'Use a new empty evidence directory.' >&2; exit 1; }
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$run_dir" "${BONESHED_LAB_SEQUENCES:-overview timing move_attack four_arm closeup}" <<'PY'
import json, pathlib, shutil, subprocess, sys
engine, repo, output, sequences = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]), sys.argv[4].split()
base = [engine, '--headless', '--path', repo]
results = []
def run(name, args, expected=0, seconds=300):
    with (output/f'{name}.log').open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/f'{name}.log').read_text()
    assert result.returncode == expected, f'{name}: exit {result.returncode}, see {output}/{name}.log'
    assert 'SCRIPT ERROR:' not in text and 'ERROR:' not in text, f'{name}: engine errors in log'
    results.append({'run': name, 'exit': result.returncode, 'expected_exit': expected})
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
records = run('animation_lab_tests', base + ['--script', 'res://scripts/qa/animation_lab_tests.gd', '--', f'--evidence-dir={output}'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] >= 70, summary
negative = run('negative_warp', base + ['--script', 'res://scripts/qa/animation_lab_tests.gd', '--', '--negative=warp'], expected=1)
failed = [r['check'] for r in negative if r.get('passed') is False]
# A clip 0.1 s out of step with the rules must break alignment and the telegraph check.
assert sorted(failed) == ['blade_not_in_front_before_rule_window', 'contact_marker_on_first_live_tick'], f'negative control failed the wrong checks: {failed}'
ffmpeg = shutil.which('ffmpeg')
for name in sequences:
    frames = output/'frames'/name
    frames.mkdir(parents=True)
    run(f'render_{name}', ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine, '--path', repo,
        '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--write-movie', str(frames/'frame.png'),
        '--fixed-fps', '30', 'res://scenes/animation_lab.tscn', '--', f'--sequence={name}'], seconds=900)
    assert 'llvmpipe' in (output/f'render_{name}.log').read_text(), 'Software renderer not confirmed'
    count = len(list(frames.glob('frame*.png')))
    assert count >= 60, f'{name}: only {count} frames'
    if ffmpeg:
        subprocess.run([ffmpeg, '-loglevel', 'error', '-y', '-framerate', '30', '-i', str(frames/'frame%08d.png'),
            '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '26', '-preset', 'slow', '-movflags', '+faststart', str(output/f'{name}.mp4')], check=True)
        step = max(1, count // 16)
        subprocess.run([ffmpeg, '-loglevel', 'error', '-y', '-i', str(frames/'frame%08d.png'), '-vf',
            f"select='not(mod(n\\,{step}))',scale=480:-1,tile=4x4", '-frames:v', '1', '-update', '1', str(output/f'{name}_sheet.png')], check=True)
print('ffmpeg: ' + ('clips and contact sheets written' if ffmpeg else 'not found; PNG frames only'))
(output/'runs.json').write_text(json.dumps(results, indent=2) + '\n')
print(f'{summary["passed"]} checks passed; negative control confirmed; evidence: {output}')
PY
