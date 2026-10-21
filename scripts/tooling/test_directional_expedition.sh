#!/usr/bin/env bash
# Directional expedition (preview world + melee lab combat): parse check, scene boot,
# integration fixtures replayed in a second process, input-driven playthroughs on four
# addresses/seeds (one headless + rendered with trace equality, one replayed in a second
# process), rendered clips with contact sheets and MP4s, and four source/data mutations
# in disposable copies, each of which must fail its specific check. Does not run or
# replace the melee lab, expedition preview or production suites.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/directional-expedition-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
timeout 120 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import > "$output/import.log" 2>&1
status=0
for script in "$REPO_ROOT"/scripts/directional_expedition/*.gd "$REPO_ROOT"/scripts/qa/directional_expedition_*.gd; do
    rel="res://${script#"$REPO_ROOT"/}"
    out="$(timeout 30 "$GODOT_BIN" --headless --path "$REPO_ROOT" --check-only --script "$rel" < /dev/null 2>&1 || true)"
    if grep -q 'SCRIPT ERROR\|Parse Error' <<<"$out"; then
        echo "$out" | grep -A1 'SCRIPT ERROR' >&2
        status=1
    fi
done
test "$status" = 0 || exit 1
echo 'parse check: all integration scripts parse'
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import filecmp, json, os, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
timeout = int(os.environ.get('BONESHED_GRAPHICAL_TIMEOUT', '2400'))
EXPECTED_TESTS = 94
def run(name, args, expected=0, seconds=900):
    with (output/(name+'.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    text = (output/(name+'.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    assert expected != 0 or ('SCRIPT ERROR' not in text and not any(l.startswith('ERROR:') for l in text.splitlines())), name
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
def summary(path):
    return json.loads(path.read_text())
run('boot', base + ['res://scenes/directional_expedition.tscn', '--quit-after', '5'])
tests = ['--fixed-fps', '60', '--script', 'res://scripts/qa/directional_expedition_tests.gd', '--']
records = run('tests', base + tests + [f'--evidence-dir={output}/tests'])
result = next(r for r in records if r.get('summary'))
assert result['failed'] == 0 and result['passed'] == EXPECTED_TESTS, result
run('tests-replay', base + tests + [f'--evidence-dir={output}/tests-replay'])
assert filecmp.cmp(output/'tests'/'results.json', output/'tests-replay'/'results.json', shallow=False)
print('cross-process replay: integration results identical', flush=True)
play = ['--fixed-fps', '60', '--script', 'res://scripts/qa/directional_expedition_playthrough.gd', '--']
for mode, command in [('headless', base), ('rendered', rendered)]:
    run('playthrough-'+mode, command + play + [f'--evidence-dir={output}/playthrough-{mode}'], seconds=timeout)
    result = summary(output/('playthrough-'+mode)/'summary.json')
    assert result['failed'] == 0 and result['passed'] >= 27 and len(result['duels']) >= 2, result
assert len(list((output/'playthrough-rendered').glob('*.png'))) >= 10
# Rendering, captures and clip frames must not change the simulation or the input trace.
assert json.loads((output/'playthrough-headless/trace.json').read_text()) == json.loads((output/'playthrough-rendered/trace.json').read_text())
print('trace equality headless vs rendered: passed', flush=True)
run('playthrough-replay', base + play + [f'--evidence-dir={output}/playthrough-replay'], seconds=timeout)
assert filecmp.cmp(output/'playthrough-headless'/'trace.json', output/'playthrough-replay'/'trace.json', shallow=False)
assert filecmp.cmp(output/'playthrough-headless'/'contacts.json', output/'playthrough-replay'/'contacts.json', shallow=False)
print('cross-process replay: playthrough trace and contacts identical', flush=True)
for words, seed in [('smoldering,pallid,necropolis', 7), ('frozen,gilded,citadel', 1002), ('drowned,hollow,cathedral', 424242)]:
    name = 'playthrough-' + words.split(',')[0] + '-' + str(seed)
    run(name, base + play + [f'--evidence-dir={output}/{name}', '--words='+words, '--seed='+str(seed)], seconds=timeout)
    assert summary(output/name/'summary.json')['failed'] == 0
for clip in sorted((output/'playthrough-rendered').glob('clip_*')):
    frames = sorted(clip.glob('frame_*.png'))
    assert len(frames) >= 60, (clip.name, len(frames))
    pattern = str(clip/'frame_*.png')
    step = max(1, len(frames) // 24)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '1', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', f'select=not(mod(n\\,{step})),scale=320:-1,tile=6x4:padding=2', '-frames:v', '1',
                    str(output/f'sheet_{clip.name}.jpg')], check=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '30', '-pattern_type', 'glob', '-i', pattern,
                    '-vf', 'scale=960:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '28',
                    str(output/f'{clip.name}.mp4')], check=True)
print('rendered clips: contact sheets and MP4s written', flush=True)
# Mutations run in disposable source copies, never against the working tree.
with tempfile.TemporaryDirectory(prefix='boneshed-directional-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(pathlib.Path(repo)/directory, isolated/directory)
    shutil.copy2(pathlib.Path(repo)/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated)]
    run('mutation-import', isolated_base + ['--editor', '--import'])
    for name, path, original, replacement, labels in [
        ('no-contact', 'scripts/directional_expedition/directional_expedition.gd',
         'var report := Solver.resolve(att.state, att.prev_xform, att.xform(), def.state, def.prev_xform, def.xform())',
         'var report := {"result": Solver.NONE}', {'cut_right_to_left_vs_guard_left_is_block', 'lethal_contact_releases_soul'}),
        ('double-charge', 'scripts/melee_lab/duelist_state.gd', '\t_begin_windup(chosen)\n\treturn true',
         '\t_charge_attack()\n\t_begin_windup(chosen)\n\treturn true', {'lmb_press_charges_attack_once'}),
        ('omniscient', 'scripts/melee_lab/lab_opponent.gd', 'reaction_delay = tuning.get("ai_reaction_delay", 0.22)',
         'reaction_delay = 0.0', {'soul_sees_windup_only_after_reaction_delay'}),
        ('block-status', 'data/melee_lab/combat_resources.json', '"block": 0.0,', '"block": 1.0,',
         {'guarded_poison_attack_applies_no_status'}),
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
print('Directional expedition: fixtures, replay, five playthroughs, trace equality, clips and mutations passed.')
PY
echo "Evidence: $output"
