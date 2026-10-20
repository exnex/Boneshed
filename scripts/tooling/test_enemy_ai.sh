#!/usr/bin/env bash
# Survival AI: scripted-style duels with fairness/variety/determinism checks, two
# negative controls, a cross-process replay comparison, and rendered decision clips
# with contact sheets for visual review.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/enemy-ai-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import filecmp, json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
def run(name, args, expected=0, seconds=300):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    assert 'SCRIPT ERROR' not in text and not any(l.startswith('ERROR:') for l in text.splitlines()), name
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
script = ['--fixed-fps', '60', '--script', 'res://scripts/qa/enemy_ai_tests.gd', '--']
records = run('checks', base + script + [f'--evidence-dir={output}/checks'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == 28, summary
# A second process must produce byte-identical traces and results.
run('checks_replay', base + script + [f'--evidence-dir={output}/checks-replay'])
names = sorted(p.name for p in (output / 'checks').glob('*.json'))
match, mismatch, errors = filecmp.cmpfiles(output / 'checks', output / 'checks-replay', names, shallow=False)
assert len(names) >= 12 and not mismatch and not errors, (mismatch, errors)
print(f'cross-process replay: {len(match)} trace/result files identical', flush=True)
for mutation, labels in [('omniscient', {'answers_wait_for_reaction_delay', 'enemy_unchanged_until_windup_is_visible', 'feints_can_bait_committed_dodges'}),
                         ('spam', {'no_answer_repeats_more_than_three_times', 'flurry_answers_vary_without_guard_toggling'})]:
    records = run('negative_' + mutation, base + script + ['--negative=' + mutation, f'--evidence-dir={output}/negative-{mutation}'], expected=1)
    failures = {r['check'] for r in records if r.get('passed') is False}
    assert labels <= failures, (mutation, failures)
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine, '--path', repo,
            '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--fixed-fps', '60',
            '--script', 'res://scripts/qa/enemy_ai_capture.gd', '--', f'--evidence-dir={output}/rendered']
records = run('rendered', rendered, seconds=1800)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['rendered'], summary
assert 'llvmpipe' in (output / 'rendered.log').read_text(), 'Software renderer not confirmed'
clips = json.loads((output / 'rendered' / 'clips.json').read_text())
assert len(clips) == 8, len(clips)
for clip in clips:
    frames = sorted((output / 'rendered' / clip['clip']).glob('frame_*.png'))
    assert len(frames) == clip['frames'] >= 20, (clip['clip'], len(frames))
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i',
                    str(output / 'rendered' / clip['clip'] / 'frame_*.png'), '-vf', 'select=not(mod(n\\,2)),scale=320:-1,tile=6x4:padding=2',
                    '-frames:v', '1', str(output / f"sheet_{clip['clip']}.png")], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '30', '-pattern_type', 'glob', '-i',
                    str(output / 'rendered' / clip['clip'] / 'frame_*.png'), '-vf', 'scale=640:-2', '-c:v', 'libx264',
                    '-pix_fmt', 'yuv420p', '-crf', '30', str(output / f"clip_{clip['clip']}.mp4")], check=True)
print('Enemy AI checks, cross-process replay, negative controls and rendered clips passed.')
PY
