#!/usr/bin/env bash
# Adaptive Combat Lab 2 (isolated, experimental): parse check, the import/pipeline/
# rules/input suite replayed in a second process (results.json and an AI duel log must
# be byte-identical), six source mutations in a disposable copy (each must fail its
# named checks), the Lab 1 heavy-miss diagnostic run against BONESHED_BASE_REF in a
# disposable worktree, optionally the Research Lab's own bundle check
# (BONESHED_LAB_REPO=<ai-game-dev-lab checkout>), rendered evidence (same-input
# comparison clips → MP4s, a side-by-side grid video, contact sheets, key-pose stills,
# gameplay/HUD/camera/graft clips) in GL Compatibility, and a guard that production,
# other labs and coordination files are unchanged versus BONESHED_BASE_REF
# (default origin/main). Set BONESHED_SKIP_RENDER=1 to run only the headless parts.
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
EXPECTED_CHECKS = int(os.environ.get('BONESHED_EXPECTED_CHECKS', '0')) or None
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
assert summary['failed'] == 0 and summary['passed'] >= 50 and (EXPECTED_CHECKS is None or summary['passed'] == EXPECTED_CHECKS), summary
print(f"checks: {summary['passed']}/{summary['passed'] + summary['failed']} passed", flush=True)
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
        ('name-changes-strength', 'scripts/adaptive_lab/affordance_solver.gd',
         '\tvar an := analyse(obj)\n',
         '\tif str(obj.get("label", "")).to_lower().contains("spear"):\n\t\tbody = body.duplicate()\n\t\tbody.two_hand_inertia = 9.0\n\tvar an := analyse(obj)\n',
         {'names_descriptions_assembly_and_filenames_never_change_capabilities', 'solver_analysis_motion_rules_and_ai_never_read_names_or_provenance'}),
        ('contact-off-object', 'scripts/adaptive_lab/motion_library.gd',
         '\treturn [xf * (p - h), xf * (p + h), float(feature.radius)]\n',
         '\treturn [xf * (p - h) + Vector3(0.0, 0.05, 0.0), xf * (p + h) + Vector3(0.0, 0.05, 0.0), float(feature.radius)]\n',
         {'drawn_object_feature_equals_the_rules_contact_capsule_at_every_frame'}),
        ('fist-off-grip', 'scripts/adaptive_lab/adaptive_pose.gd',
         '\tvar wrist := grip - knuckles * GRIP\n',
         '\tvar wrist := grip + Vector3(0.0, 0.05, 0.0) - knuckles * GRIP\n',
         {'drawn_fists_hold_the_rules_grip_points'}),
        ('heft-ignored', 'scripts/adaptive_lab/affordance_solver.gd',
         '"heft": snappedf(clampf(maxf(swing_load, push_load), 0.0, 1.0), 0.0001)}',
         '"heft": 0.0}',
         {'heft_shapes_tempo_overshoot_and_recovery'}),
        ('grips-resampled-from-rod', 'scripts/adaptive_lab/lab_analysis.gd',
         '\t\tvar lo := a + axis * HAND_HALF_WIDTH\n',
         '\t\tvar lo := (p.a as Vector3) + axis * HAND_HALF_WIDTH\n',
         {'holds_use_only_the_lab_declared_grip_intervals'}),
        ('bang-bang-footwork', 'scripts/adaptive_lab/adaptive_fighter.gd',
         '\treturn clampf(wanted, -max_out, max_in)\n',
         '\treturn -max_out if wanted < 0.0 else max_in\n',
         {'every_heavy_connects_from_close_range_out_to_its_reach'}),
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
# Lab 1 heavy-miss diagnostic: the same probe against the base ref's own code.
base_ref = os.environ.get('BONESHED_BASE_REF', 'origin/main')
if subprocess.run(['git', '-C', repo, 'rev-parse', '--verify', '-q', base_ref], stdout=subprocess.DEVNULL).returncode == 0:
    with tempfile.TemporaryDirectory(prefix='boneshed-lab1-') as temporary:
        tree = pathlib.Path(temporary)/'tree'
        subprocess.run(['git', '-C', repo, 'worktree', 'add', '-q', '--detach', str(tree), base_ref], check=True)
        try:
            shutil.copy2(pathlib.Path(repo)/'scripts/qa/adaptive_lab_heavy_diagnostic_lab1.gd', tree/'scripts/qa/')
            run('lab1-import', [engine, '--headless', '--path', str(tree), '--editor', '--import'], seconds=300)
            records = run('lab1-heavy-diagnostic', [engine, '--headless', '--path', str(tree), '--script', 'res://scripts/qa/adaptive_lab_heavy_diagnostic_lab1.gd'])
            (output/'lab1_heavy_diagnostic.jsonl').write_text(''.join(json.dumps(r, sort_keys=True)+'\n' for r in records))
            summary = next(r for r in records if r.get('summary'))
            print(f"lab1 heavy diagnostic ({base_ref}): {summary['whiffs']}/{summary['cases']} heavies whiffed", flush=True)
        finally:
            subprocess.run(['git', '-C', repo, 'worktree', 'remove', '--force', str(tree)], check=False)
# Optional: the Research Lab's own verifier over the vendored bytes.
lab_repo = os.environ.get('BONESHED_LAB_REPO')
if lab_repo:
    content = pathlib.Path(lab_repo)/'03-programming/boneshed-content'
    with (output/'lab_python_check.log').open('w') as log:
        result = subprocess.run(['python3', str(content/'object_export.py'), 'check', '--input', str(pathlib.Path(repo)/'data/adaptive_lab/lab_export_v1')],
                                stdout=log, stderr=subprocess.STDOUT)
    assert result.returncode == 0, 'Lab check failed on the vendored bundle'
    assert subprocess.run(['diff', '-r', str(content/'results/export-v1'), str(pathlib.Path(repo)/'data/adaptive_lab/lab_export_v1')]).returncode == 0
    print('research lab check: vendored bundle accepted (6) / rejected (9) and byte-identical to the Lab', flush=True)
if os.environ.get('BONESHED_SKIP_RENDER') == '1':
    print('rendered evidence skipped (BONESHED_SKIP_RENDER=1)')
    sys.exit(0)
xvfb = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp']
capture = ['--audio-driver', 'Dummy', '--fixed-fps', '60', '--script', 'res://scripts/qa/adaptive_lab_capture.gd', '--']
records = run('rendered', xvfb + [engine, '--path', repo, '--rendering-method', 'gl_compatibility'] + capture + [f'--evidence-dir={output}/rendered'], seconds=7200)
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and 'llvmpipe' in summary['adapter'], summary
rendered = output/'rendered'
for clip in sorted(rendered.glob('clip_*')):
    frames = sorted(clip.glob('frame_*.png'))
    assert len(frames) >= 60, (clip.name, len(frames))
    pattern = str(clip/'frame_*.png')
    step = max(1, len(frames)//24)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', f'select=not(mod(n\\,{step})),scale=320:-1,tile=6x4:padding=2', '-frames:v', '1',
                    str(output/f'sheet_{clip.name}.jpg')], check=True)
    rate = 30 if clip.name == 'clip_graft_regeneration' else 60
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(rate), '-pattern_type', 'glob', '-i', pattern,
                    '-vf', 'scale=960:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '26',
                    str(output/f'{clip.name}.mp4')], check=True)
# Same inputs, side by side: a 3×2 grid of the comparison clips, each labelled.
compare = sorted(rendered.glob('clip_compare_*'))
if len(compare) >= 3:
    inputs, filters = [], []
    for i, clip in enumerate(compare[:6]):
        inputs += ['-framerate', '60', '-pattern_type', 'glob', '-i', str(clip/'frame_*.png')]
        label = clip.name.replace('clip_compare_', '')
        filters.append(f"[{i}:v]crop=880:560:200:110,scale=640:-2,drawtext=text='{label}':x=12:y=10:fontsize=26:fontcolor=white:box=1:boxcolor=black@0.5[v{i}]")
    n = len(filters)
    layout = '|'.join(f'{(i%3)*640}_{(i//3)*408}' for i in range(n))
    graph = ';'.join(filters) + ';' + ''.join(f'[v{i}]' for i in range(n)) + f'xstack=inputs={n}:layout={layout}:fill=black[out]'
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', *inputs, '-filter_complex', graph, '-map', '[out]', '-shortest',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '27', str(output/'compare_side_by_side.mp4')], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(output/'compare_side_by_side.mp4'), '-vf', 'select=not(mod(n\\,24)),scale=640:-2,tile=3x4:padding=2',
                    '-frames:v', '1', str(output/'compare_side_by_side_sheet.jpg')], check=True)
# Contact sheets of the key-pose stills, one per object.
stills = rendered/'stills'
for obj in sorted({p.name.split('_')[0] for p in stills.glob('*.png')}):
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', str(stills/f'{obj}_*.png'),
                    '-vf', 'crop=880:600:200:60,scale=300:-1,tile=5x3:padding=2', '-frames:v', '1', str(output/f'poses_{obj}.jpg')], check=True)
print('rendered (GL Compatibility, llvmpipe): comparison grid, MP4s, contact sheets and pose sheets written', flush=True)
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
