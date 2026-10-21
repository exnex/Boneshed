#!/usr/bin/env bash
# Expedition preview: pipeline fixtures, built-geometry physics, validator negative
# controls, input-driven loop on three addresses (headless + rendered), trace
# equality and source mutations. Does not run or replace the other suites.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/expedition-preview-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', repo]
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
timeout = int(os.environ.get('BONESHED_GRAPHICAL_TIMEOUT', '1500'))
def run(name, args, expected=0, seconds=600):
    with (output/(name+'.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/(name+'.log')).read_text()
    assert result.returncode == expected, (name, result.returncode)
    assert expected != 0 or ('ERROR:' not in text and 'SCRIPT ERROR' not in text), name
    print(name + ': passed', flush=True)
    return text
def summary(path):
    return json.loads(path.read_text())
run('import', base + ['--editor', '--import'])
run('boot', base + ['res://scenes/expedition_preview.tscn', '--quit-after', '5'])
for mode, command in [('headless', base), ('rendered', rendered)]:
    run('tests-'+mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_preview_tests.gd', '--',
                                 '--evidence-dir='+str(output/('tests-'+mode))], seconds=timeout)
    result = summary(output/('tests-'+mode)/'summary.json')
    assert result['failed'] == 0 and result['passed'] >= 1000, result
    run('playthrough-'+mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_preview_playthrough.gd', '--',
                                       '--evidence-dir='+str(output/('playthrough-'+mode))], seconds=timeout)
    result = summary(output/('playthrough-'+mode)/'summary.json')
    assert result['failed'] == 0 and result['passed'] >= 15 and len(result['duels']) >= 2, result
assert len(list((output/'tests-rendered').glob('*.png'))) == 9
assert len(list((output/'playthrough-rendered').glob('*.png'))) == 9
# Rendering and capture awaits must not change the simulation or the input trace.
assert summary(output/'playthrough-headless'/'summary.json')['ticks'] == summary(output/'playthrough-rendered'/'summary.json')['ticks']
assert json.loads((output/'playthrough-headless/trace.json').read_text()) == json.loads((output/'playthrough-rendered/trace.json').read_text())
print('trace equality: passed', flush=True)
# The same loop on contrasting addresses and seeds.
for words, seed in [('smoldering,pallid,necropolis', 7), ('frozen,gilded,citadel', 1002)]:
    name = 'playthrough-' + words.split(',')[0]
    run(name, base + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_preview_playthrough.gd', '--',
                      '--evidence-dir='+str(output/name), '--words='+words, '--seed='+str(seed)], seconds=timeout)
    assert summary(output/name/'summary.json')['failed'] == 0
# Mutations run in disposable source copies, never against the working tree.
with tempfile.TemporaryDirectory(prefix='boneshed-preview-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(pathlib.Path(repo)/directory, isolated/directory)
    shutil.copy2(pathlib.Path(repo)/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated)]
    run('mutation-import', isolated_base + ['--editor', '--import'])
    for name, path, original, replacement, prefix in [
        ('seed', 'expedition_plan.gd', 'Blueprint.new().generate(words, seed_value)',
         'Blueprint.new().generate(words, 0)', 'seed_varies_regions_'),
        ('separation', 'dungeon_plan.gd', 'if room.rect.grow(1).intersects(other.rect) or (other.id',
         'if room.rect.intersects(other.rect) or (other.id', 'valid_'),
        ('collision', 'preview_builder.gd', 'body.collision_layer = Modules.ENVIRONMENT_LAYER\n',
         'body.collision_layer = 0\n', 'world_floor_under_every_cell_'),
    ]:
        source = isolated/'scripts/expedition_preview'/path
        content = source.read_text()
        assert content.count(original) == 1, name
        source.write_text(content.replace(original, replacement))
        text = run('negative-'+name, isolated_base + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_preview_tests.gd',
                                                     '--', '--evidence-dir='+str(output/('negative-'+name))], expected=1, seconds=timeout)
        records = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
        assert any(r.get('check', '').startswith(prefix) and r['passed'] is False for r in records), name
        source.write_text(content)
print('Expedition preview: fixtures, physics, validator controls, three playthroughs, trace equality and mutations passed.')
PY
