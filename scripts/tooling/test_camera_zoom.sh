#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/camera-zoom-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
def run(name, args, expected=0, seconds=60):
    with (output / (name + '.log')).open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *map(str, args)], stdout=log, stderr=subprocess.STDOUT)
    text = (output / (name + '.log')).read_text()
    assert result.returncode == expected and 'ERROR:' not in text, (name, result.returncode)
    print(f'{name}: expected exit {expected} confirmed', flush=True)
args = ['--fixed-fps', '60', '--script', 'res://scripts/qa/camera_zoom_test.gd', '--']
base = [engine, '--headless', '--path', repo]
run('import', base + ['--editor', '--import'])
run('headless', base + args + ['--evidence-dir=' + str(output / 'headless')])
checks = json.loads((output / 'headless/checks.json').read_text())
assert checks[-1]['passed'] == 89 and checks[-1]['failed'] == 0
# Mutate isolated source copies: production wiring, not a reimplementation of zoom.
source = (repo / 'scripts/characters/player.gd').read_text()
mutations = [
    ('snap', 'spring.spring_length = lerpf(spring.spring_length, preferred_camera_distance, 1.0 - exp(-camera_zoom_speed * delta))',
     'spring.spring_length = preferred_camera_distance', 'first_tick_interpolates'),
    ('reset', '# Keep preferred zoom and its interpolation through all session encounters.',
     'preferred_camera_distance = camera_distance', 'encounter_reset_preserves_zoom_and_smoothing'),
    ('collision', 'spring.collision_mask = AttackModules.ENVIRONMENT_LAYER',
     'spring.collision_mask = 0', 'rear_wall_blocks_camera'),
]
with tempfile.TemporaryDirectory(prefix='boneshed-zoom-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(repo / directory, isolated / directory)
    shutil.copy2(repo / 'project.godot', isolated / 'project.godot')
    isolated_base = [engine, '--headless', '--path', isolated]
    run('mutation_import', isolated_base + ['--editor', '--import'])
    for name, original, replacement, label in mutations:
        assert source.count(original) == 1, name
        (isolated / 'scripts/characters/player.gd').write_text(source.replace(original, replacement))
        evidence = output / ('negative-' + name)
        run('negative_' + name, isolated_base + args + ['--evidence-dir=' + str(evidence)], expected=1)
        checks = json.loads((evidence / 'checks.json').read_text())
        assert any(c.get('check') == label and c['passed'] is False for c in checks), (name, label)
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', repo, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
run('rendered', rendered + args + ['--evidence-dir=' + str(output / 'rendered')],
    seconds=int(os.environ.get('BONESHED_GRAPHICAL_TIMEOUT', '900')))
checks = json.loads((output / 'rendered/checks.json').read_text())
assert checks[-1]['passed'] == 98 and checks[-1]['failed'] == 0 and checks[-1]['rendered']
assert len(list((output / 'rendered').glob('*.png'))) == 9
print('Zoom input, smoothing, collision, persistence, combat and rendered checks passed.')
PY
