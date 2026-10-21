#!/usr/bin/env bash
# Visual showcase (isolated, experimental): parse check, the presentation/rig/contact
# suite replayed in a second process, three source mutations in a disposable copy (each
# must fail its named check), rendered evidence (before/after pairs, close-ups, clips
# with contact sheets and MP4s) in GL Compatibility, a few Forward+ shots when a Vulkan
# driver is present (lavapipe here), and a guard that protected production, lab and
# coordination files are unchanged versus BONESHED_BASE_REF (default origin/main).
# Set BONESHED_SKIP_RENDER=1 to run only the headless parts.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/visual-showcase-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
timeout 180 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import > "$output/import.log" 2>&1
status=0
for script in "$REPO_ROOT"/scripts/visual_showcase/*.gd "$REPO_ROOT"/scripts/qa/visual_showcase_*.gd; do
    rel="res://${script#"$REPO_ROOT"/}"
    out="$(timeout 30 "$GODOT_BIN" --headless --path "$REPO_ROOT" --check-only --script "$rel" < /dev/null 2>&1 || true)"
    if grep -q 'SCRIPT ERROR\|Parse Error' <<<"$out"; then
        echo "$out" | grep -A1 'SCRIPT ERROR' >&2
        status=1
    fi
done
test "$status" = 0 || exit 1
echo 'parse check: all showcase scripts parse'
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import filecmp, json, os, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo, '--fixed-fps', '60']
EXPECTED_CHECKS = 49
def run(name, args, expected=0, seconds=1200):
    with (output/(name+'.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    text = (output/(name+'.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    if expected == 0:
        assert 'SCRIPT ERROR' not in text and not any(l.startswith('ERROR:') for l in text.splitlines()), name
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(l) for l in text.splitlines() if l.startswith('{')]
tests = ['--script', 'res://scripts/qa/visual_showcase_tests.gd', '--']
records = run('checks', base + tests + [f'--evidence-dir={output}/checks'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == EXPECTED_CHECKS, summary
run('checks_replay', base + tests + [f'--evidence-dir={output}/checks-replay'])
assert filecmp.cmp(output/'checks'/'results.json', output/'checks-replay'/'results.json', shallow=False)
print('cross-process replay: results.json identical', flush=True)
# Mutations run in a disposable copy, never against the working tree.
with tempfile.TemporaryDirectory(prefix='boneshed-showcase-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(pathlib.Path(repo)/directory, isolated/directory)
    shutil.copy2(pathlib.Path(repo)/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated), '--fixed-fps', '60']
    run('mutation-import', [engine, '--headless', '--path', str(isolated), '--editor', '--import'], seconds=300)
    for name, path, original, replacement, labels in [
        ('weapon-offset', 'scripts/visual_showcase/pose_solver.gd', 'var weapon := Transform3D(_weapon_basis(dir), hand)',
         'var weapon := Transform3D(_weapon_basis(dir), hand + Vector3(0.0, 0.05, 0.0))',
         {'drawn_weapon_equals_rules_segment_every_tick', 'engine_weapon_tip_on_rules_tip'}),
        ('fist-off-grip', 'scripts/visual_showcase/pose_solver.gd', '\tvar grip_r := hand\n',
         '\tvar grip_r := hand + Vector3(0.0, -0.05, 0.0)\n', {'right_fist_on_grip_all_weapons_directions_guards', 'engine_grip_socket_on_rules_hand'}),
        ('presentation-touches-rules', 'scripts/visual_showcase/showcase_visual.gd', '\tlast_view = _view(state)\n',
         '\tstate.omega *= 0.97\n\tlast_view = _view(state)\n', {'combat_outcomes_identical_to_melee_lab'}),
    ]:
        source = isolated/path
        content = source.read_text()
        assert content.count(original) == 1, name
        source.write_text(content.replace(original, replacement))
        records = run('negative-'+name, isolated_base + tests + [f'--evidence-dir={output}/negative-{name}'], expected=1)
        failures = {r['check'] for r in records if r.get('passed') is False}
        assert labels <= failures, (name, failures)
        print(f'negative {name}: caught by {sorted(labels)}', flush=True)
        source.write_text(content)
if os.environ.get('BONESHED_SKIP_RENDER') == '1':
    print('rendered evidence skipped (BONESHED_SKIP_RENDER=1)')
    sys.exit(0)
xvfb = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp']
capture = ['--audio-driver', 'Dummy', '--fixed-fps', '60', '--script', 'res://scripts/qa/visual_showcase_capture.gd', '--']
records = run('rendered', xvfb + [engine, '--path', repo, '--rendering-method', 'gl_compatibility'] + capture + [f'--evidence-dir={output}/rendered'], seconds=3600)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0, summary
assert 'llvmpipe' in (output/'rendered.log').read_text(), 'Software renderer not confirmed'
for clip in sorted((output/'rendered').glob('clip_*')):
    frames = sorted(clip.glob('frame_*.png'))
    assert len(frames) >= 30, (clip.name, len(frames))
    pattern = str(clip/'frame_*.png')
    step = max(1, len(frames)//12)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', f'select=not(mod(n\\,{step})),scale=320:-1,tile=4x3:padding=2', '-frames:v', '1',
                    str(output/f'sheet_{clip.name}.jpg')], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '30', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', 'scale=960:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '28',
                    str(output/f'{clip.name}.mp4')], check=True)
print('rendered (GL Compatibility, llvmpipe): stills, pairs, contact sheets and MP4s written', flush=True)
probe = subprocess.run(['sh', '-c', 'ls /usr/share/vulkan/icd.d/ 2>/dev/null'], capture_output=True, text=True).stdout
if 'lvp' in probe or os.environ.get('BONESHED_FORWARD') == '1':
    records = run('rendered_forward', xvfb + [engine, '--path', repo, '--rendering-method', 'forward_plus'] + capture[:-1] +
                  ['--', '--set=hero', f'--evidence-dir={output}/rendered-forward'], seconds=3600)
    assert any(r.get('summary') and r['renderer'] == 'forward_plus' for r in records)
    print('rendered (Forward+, Vulkan): hero shots written', flush=True)
else:
    print('Forward+ shots skipped: no Vulkan driver found')
PY
# Isolation: production entry points, lab rules, shared data and coordination files are
# untouched. Compares with BONESHED_BASE_REF (default origin/main; fetch it first).
cd "$REPO_ROOT"
base_ref="${BONESHED_BASE_REF:-origin/main}"
if git rev-parse --verify -q "$base_ref" >/dev/null; then
    changed="$(git diff --name-only "$base_ref"...HEAD; git status --porcelain | cut -c4-)"
    if grep -E '^(project\.godot|export_presets\.cfg|docs/ROADMAP\.md|docs/DECISIONS\.md|\.github/|scenes/(courtyard|first_expedition|salvage_courtyard|melee_lab|directional_expedition|expedition_preview|animation_lab)\.tscn|scripts/(combat|ai|characters|builds|expedition|expedition_preview|worldgen|melee_lab|directional_expedition)/|data/(builds|melee_lab|directional_expedition)/)' <<<"$changed"; then
        echo 'Isolation violated: a protected production, lab or coordination file changed.' >&2
        exit 1
    fi
    echo "isolation: no protected production, lab or coordination file changed versus $base_ref"
fi
echo "Evidence: $output"
