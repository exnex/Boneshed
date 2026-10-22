#!/usr/bin/env bash
# Adaptive Combat Lab (isolated, experimental): parse check, the pipeline/rules/input
# suite replayed in a second process (results.json must be identical), four source
# mutations in a disposable copy (each must fail its named checks), rendered evidence
# (stills, frame sequences → MP4s and contact sheets) in GL Compatibility, and a guard
# that production, other labs and coordination files are unchanged versus
# BONESHED_BASE_REF (default origin/main).
# Set BONESHED_SKIP_RENDER=1 to run only the headless parts.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/adaptive-lab-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output" "$REPO_ROOT/artifacts"
touch "$REPO_ROOT/artifacts/.gdignore"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
timeout 180 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import > "$output/import.log" 2>&1
status=0
for script in "$REPO_ROOT"/scripts/adaptive_lab/*.gd "$REPO_ROOT"/scripts/qa/adaptive_lab_*.gd; do
    rel="res://${script#"$REPO_ROOT"/}"
    out="$(timeout 30 "$GODOT_BIN" --headless --path "$REPO_ROOT" --check-only --script "$rel" < /dev/null 2>&1 || true)"
    if grep -q 'SCRIPT ERROR\|Parse Error' <<<"$out"; then
        echo "$out" | grep -A1 'SCRIPT ERROR' >&2
        status=1
    fi
done
test "$status" = 0 || exit 1
echo 'parse check: all adaptive lab scripts parse'
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import filecmp, json, os, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo, '--fixed-fps', '60']
EXPECTED_CHECKS = 56
def run(name, args, expected=0, seconds=900):
    with (output/(name+'.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    text = (output/(name+'.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    if expected == 0:
        assert 'SCRIPT ERROR' not in text, name
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(l) for l in text.splitlines() if l.startswith('{')]
tests = ['--script', 'res://scripts/qa/adaptive_lab_tests.gd', '--']
records = run('checks', base + tests + [f'--evidence-dir={output}/checks'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] == EXPECTED_CHECKS, summary
print(f"checks: {summary['passed']}/{EXPECTED_CHECKS} passed", flush=True)
run('checks_replay', base + tests + [f'--evidence-dir={output}/checks-replay'])
assert filecmp.cmp(output/'checks'/'results.json', output/'checks-replay'/'results.json', shallow=False)
assert filecmp.cmp(output/'checks'/'duel_log.json', output/'checks-replay'/'duel_log.json', shallow=False)
print('cross-process replay: results.json and duel_log.json identical', flush=True)
# Mutations run in a disposable copy, never against the working tree.
with tempfile.TemporaryDirectory(prefix='boneshed-adaptive-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(pathlib.Path(repo)/directory, isolated/directory)
    shutil.copy2(pathlib.Path(repo)/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated), '--fixed-fps', '60']
    run('mutation-import', [engine, '--headless', '--path', str(isolated), '--editor', '--import'], seconds=300)
    for name, path, original, replacement, labels in [
        ('label-changes-strength', 'scripts/adaptive_lab/affordance_solver.gd',
         '\tvar an := Analysis.analyse(descriptor)\n',
         '\tif str(descriptor.get("label", "")).to_lower().contains("spear"):\n\t\tbody = body.duplicate()\n\t\tbody.one_hand_inertia = 9.0\n\tvar an := Analysis.analyse(descriptor)\n',
         {'label_swap_never_changes_capabilities_or_fingerprint', 'rules_solver_motion_and_ai_never_read_labels'}),
        ('contact-off-object', 'scripts/adaptive_lab/motion_library.gd',
         '\treturn [xf * (p - h), xf * (p + h), float(feature.radius)]\n',
         '\treturn [xf * (p - h) + Vector3(0.0, 0.05, 0.0), xf * (p + h) + Vector3(0.0, 0.05, 0.0), float(feature.radius)]\n',
         {'contact_feature_moves_rigidly_with_the_gripped_object', 'drawn_object_feature_equals_rules_contact_feature_at_every_frame'}),
        ('fist-off-grip', 'scripts/adaptive_lab/adaptive_pose.gd',
         '\tvar wrist := grip - knuckles * GRIP\n',
         '\tvar wrist := grip + Vector3(0.0, 0.05, 0.0) - knuckles * GRIP\n',
         {'hands_stay_on_generated_grips_through_every_motion', 'drawn_fists_hold_the_rules_grip_points'}),
        ('weight-ignored', 'scripts/adaptive_lab/affordance_solver.gd',
         '\tvar k := 0.85 + 0.75 * clampf(load, 0.0, 1.0)\n',
         '\tvar k := 1.0\n',
         {'heavier_ends_slow_windup_and_recovery', 'one_handed_grip_on_the_same_shovel_is_slower'}),
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
capture = ['--audio-driver', 'Dummy', '--fixed-fps', '60', '--script', 'res://scripts/qa/adaptive_lab_capture.gd', '--']
records = run('rendered', xvfb + [engine, '--path', repo, '--rendering-method', 'gl_compatibility'] + capture + [f'--evidence-dir={output}/rendered'], seconds=3600)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and 'llvmpipe' in summary['adapter'], summary
for clip in sorted((output/'rendered').glob('clip_*')):
    frames = sorted(clip.glob('frame_*.png'))
    assert len(frames) >= 60, (clip.name, len(frames))
    pattern = str(clip/'frame_*.png')
    step = max(1, len(frames)//12)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', f'select=not(mod(n\\,{step})),scale=320:-1,tile=4x3:padding=2', '-frames:v', '1',
                    str(output/f'sheet_{clip.name}.jpg')], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '60', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', 'scale=960:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '28',
                    str(output/f'{clip.name}.mp4')], check=True)
print('rendered (GL Compatibility, llvmpipe): stills, contact sheets and MP4s written', flush=True)
PY
# Isolation: production entry points, other labs, shared data and coordination files
# are untouched. Compares with BONESHED_BASE_REF (default origin/main; fetch it first).
cd "$REPO_ROOT"
base_ref="${BONESHED_BASE_REF:-origin/main}"
if git rev-parse --verify -q "$base_ref" >/dev/null; then
    changed="$(git diff --name-only "$base_ref"...HEAD; git status --porcelain | cut -c4-)"
    if grep -E '^(project\.godot|export_presets\.cfg|docs/ROADMAP\.md|docs/DECISIONS\.md|\.github/|scenes/(courtyard|first_expedition|salvage_courtyard|melee_lab|directional_expedition|expedition_preview|animation_lab|visual_showcase)\.tscn|scripts/(combat|ai|characters|builds|expedition|expedition_preview|worldgen|melee_lab|directional_expedition|visual_showcase|anatomy|animation_lab)/|data/(builds|melee_lab|directional_expedition|visual_showcase)/)' <<<"$changed"; then
        echo 'Isolation violated: a protected production, lab or coordination file changed.' >&2
        exit 1
    fi
    echo "isolation: no protected production, lab or coordination file changed versus $base_ref"
fi
echo "Evidence: $output"
