#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/expedition-$(date -u +%Y%m%dT%H%M%SZ)}"
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
def run(name, args, expected=0, seconds=120):
    with (output/(name+'.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/(name+'.log')).read_text()
    assert result.returncode == expected and 'ERROR:' not in text, (name, result.returncode)
    print(name + ': passed', flush=True)
run('import', base + ['--editor', '--import'])
run('boot', base + ['--quit-after', '5'])
for mode, command in [('headless', base), ('rendered', rendered)]:
    run(mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_tests.gd', '--',
                        '--evidence-dir='+str(output/mode)], seconds=300)
    result = json.loads((output/mode/'summary.json').read_text())
    assert result['failed'] == 0 and result['passed'] == (743 if mode == 'headless' else 751) and result['unique_layouts'] == 192, result
    run('camera-'+mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_camera_test.gd', '--',
                                  '--evidence-dir='+str(output/('camera-'+mode))], seconds=180)
    result = json.loads((output/('camera-'+mode)/'summary.json').read_text())
    assert result['failed'] == 0 and result['passed'] == (9 if mode == 'headless' else 12), result
    run('playthrough-'+mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_playthrough.gd', '--',
                                      '--evidence-dir='+str(output/('playthrough-'+mode))],
        seconds=int(os.environ.get('BONESHED_GRAPHICAL_TIMEOUT', '1200')))
    result = json.loads((output/('playthrough-'+mode)/'summary.json').read_text())
    assert result['failed'] == 0 and result['ticks'] < 10000, result
# Rendering/capture awaits must preserve the simulation and legal input trace.
assert json.loads((output/'playthrough-headless/trace.json').read_text()) == json.loads((output/'playthrough-rendered/trace.json').read_text())
assert len(list((output/'rendered').glob('*.png'))) == 8
# Mutations run in disposable source copies, never against the working tree.
with tempfile.TemporaryDirectory(prefix='boneshed-expedition-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(pathlib.Path(repo)/directory, isolated/directory)
    shutil.copy2(pathlib.Path(repo)/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated)]
    run('mutation-import', isolated_base + ['--editor', '--import'])
    for name, path, original, replacement, label in [
        ('seed', 'expedition_layout.gd', 'Stream.new(VERSION + "|" + blueprint.streams.structure)',
         'Stream.new("constant")', 'seed_changes_geometry_drowned'),
        ('collision', 'world_builder.gd', 'collision.collision_layer = Modules.ENVIRONMENT_LAYER',
         'collision.collision_layer = 0', 'solid_boundaries_drowned_1'),
    ]:
        source = isolated/'scripts/expedition'/path
        content = source.read_text()
        assert content.count(original) == 1
        source.write_text(content.replace(original, replacement))
        evidence = output/('negative-'+name)
        run('negative-'+name, isolated_base + ['--fixed-fps', '60', '--script', 'res://scripts/qa/expedition_tests.gd',
                                              '--', '--evidence-dir='+str(evidence)], expected=1, seconds=120)
        records = [json.loads(line) for line in (output/('negative-'+name+'.log')).read_text().splitlines() if line.startswith('{')]
        assert any(r.get('check') == label and r['passed'] is False for r in records)
        source.write_text(content)
print('Determinism, identity, collision, traversal, selection, pause, restart, and complete salvage/rematch passed.')
PY
