#!/usr/bin/env bash
# Directional melee lab: parse check, deterministic rule/scene/AI checks and the combat
# resources suite (stamina, weight, status), each replayed in a second process, four
# negative controls, rendered clips with contact sheets and MP4s, and a
# guard that the branch leaves production entry points and coordinator files untouched.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/melee-lab-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
timeout 120 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import > "$output/import.log" 2>&1
bash "$(dirname "$0")/check_melee_lab.sh"
echo 'parse check: all lab scripts parse'
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import filecmp, json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo, '--fixed-fps', '60']
def run(name, args, expected=0, seconds=600):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    assert 'SCRIPT ERROR' not in text and not any(l.startswith('ERROR:') for l in text.splitlines()), name
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
script = ['--script', 'res://scripts/qa/melee_lab_tests.gd', '--']
records = run('checks', base + script + [f'--evidence-dir={output}/checks'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == 90, summary
run('checks_replay', base + script + [f'--evidence-dir={output}/checks-replay'])
assert filecmp.cmp(output / 'checks' / 'results.json', output / 'checks-replay' / 'results.json', shallow=False)
print('cross-process replay: results.json identical', flush=True)
for mutation, labels in [('no-substeps', {'fast_blade_cannot_tunnel_through_guard'}),
                         ('omniscient', {'ai_guard_waits_for_reaction_delay', 'late_redirect_is_seen_only_after_delay'})]:
    records = run('negative_' + mutation, base + script + ['--negative=' + mutation, f'--evidence-dir={output}/negative-{mutation}'], expected=1)
    failures = {r['check'] for r in records if r.get('passed') is False}
    assert labels <= failures, (mutation, failures)
    print(f'negative {mutation}: caught by {sorted(labels)}', flush=True)
resources = ['--script', 'res://scripts/qa/melee_lab_resources_tests.gd', '--']
records = run('resources', base + resources + [f'--evidence-dir={output}/resources'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == 73, summary
run('resources_replay', base + resources + [f'--evidence-dir={output}/resources-replay'])
assert filecmp.cmp(output / 'resources' / 'results.json', output / 'resources-replay' / 'results.json', shallow=False)
print('resources cross-process replay: results.json identical', flush=True)
for mutation, labels in [('free-feints', {'feint_spam_is_bounded_by_stamina'}),
                         ('block-applies-status', {'blocked_attack_applies_no_status'})]:
    records = run('negative_' + mutation, base + resources + ['--negative=' + mutation, f'--evidence-dir={output}/negative-{mutation}'], expected=1)
    failures = {r['check'] for r in records if r.get('passed') is False}
    assert labels <= failures, (mutation, failures)
    print(f'negative {mutation}: caught by {sorted(labels)}', flush=True)
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine, '--path', repo,
            '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--fixed-fps', '60',
            '--script', 'res://scripts/qa/melee_lab_capture.gd', '--', f'--evidence-dir={output}/rendered']
records = run('rendered', rendered, seconds=1800)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['rendered'] == 23, summary
assert 'llvmpipe' in (output / 'rendered.log').read_text(), 'Software renderer not confirmed'
clips = json.loads((output / 'rendered' / 'clips.json').read_text())
for clip in clips:
    frames = sorted((output / 'rendered' / clip['clip']).glob('frame_*.png'))
    assert len(frames) == clip['frames'] >= 30, (clip['clip'], len(frames))
    pattern = str(output / 'rendered' / clip['clip'] / 'frame_*.png')
    step = max(1, len(frames) // 24)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', f'select=not(mod(n\\,{step})),scale=320:-1,tile=6x4:padding=2', '-frames:v', '1',
                    str(output / f"sheet_{clip['clip']}.jpg")], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '30', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', 'scale=960:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '28',
                    str(output / f"clip_{clip['clip']}.mp4")], check=True)
print('Melee lab checks, replay, negative controls and rendered clips passed.')
PY
# Isolation: production entry point, coordinator documents and publishing are untouched.
# Compares with BONESHED_BASE_REF (default origin/main; fetch it first so it is current).
cd "$REPO_ROOT"
base_ref="${BONESHED_BASE_REF:-origin/main}"
if git rev-parse --verify -q "$base_ref" >/dev/null; then
    changed="$(git diff --name-only "$base_ref"...HEAD; git status --porcelain | cut -c4-)"
    if grep -E '^(project\.godot|export_presets\.cfg|docs/ROADMAP\.md|docs/DECISIONS\.md|\.github/|scenes/(courtyard|first_expedition|salvage_courtyard)\.tscn|scripts/(combat|ai|characters|builds|expedition|worldgen)/|data/builds/)' <<<"$changed"; then
        echo 'Isolation violated: the lab branch changed a protected production/coordination file.' >&2
        exit 1
    fi
    echo "isolation: no protected production or coordination file changed versus $base_ref"
fi
echo "Evidence: $output"
