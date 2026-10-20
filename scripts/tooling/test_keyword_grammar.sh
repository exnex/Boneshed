#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/keyword-grammar-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-4}"
python3 - "$GODOT_BIN" "$REPO_ROOT" "$output" <<'PY'
import json, pathlib, shutil, subprocess, sys, tempfile
engine, repo, output = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', str(repo)]
rendered = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24 -nolisten tcp', engine,
            '--path', str(repo), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
def run(name, command, expected=0):
    log = output/(name+'.log')
    with log.open('w') as stream:
        result = subprocess.run(['timeout', '240', *command], stdout=stream, stderr=subprocess.STDOUT)
    text = log.read_text()
    assert result.returncode == expected and 'ERROR:' not in text, (name, result.returncode, log)
    print(name + ': passed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
for mode, command in [('headless', base), ('rendered', rendered)]:
    run(mode, command + ['--fixed-fps', '60', '--script', 'res://scripts/qa/keyword_grammar_tests.gd', '--',
                         '--evidence-dir='+str(output/mode)])
    summary = json.loads((output/mode/'summary.json').read_text())
    assert summary['failed'] == 0 and summary['passed'] >= 88, summary
assert (output/'headless/examples.json').read_bytes() == (output/'rendered/examples.json').read_bytes()
assert len(list((output/'rendered').glob('*.png'))) == 3
# Removing the role filter must fail the UI regression even though generation still works.
with tempfile.TemporaryDirectory(prefix='boneshed-grammar-') as temporary:
    isolated = pathlib.Path(temporary)
    for directory in ('scripts', 'scenes', 'data'):
        shutil.copytree(repo/directory, isolated/directory)
    shutil.copy2(repo/'project.godot', isolated/'project.godot')
    isolated_base = [engine, '--headless', '--path', str(isolated)]
    run('mutation-import', isolated_base + ['--editor', '--import'])
    source = isolated/'scripts/expedition/expedition_select.gd'
    text = source.read_text()
    original = 'var ids := library.keywords_for_slot(slot, legacy)'
    assert text.count(original) == 1
    source.write_text(text.replace(original, 'var ids: Array = library.keywords.keys()\n\t\tids.sort()'))
    records = run('negative-unfiltered-selector', isolated_base + ['--fixed-fps', '60', '--script',
        'res://scripts/qa/keyword_grammar_tests.gd', '--', '--evidence-dir='+str(output/'negative')], expected=1)
    assert any(r.get('check') == 'selector_filters_each_role' and r['passed'] is False for r in records)
print('Grammar, vocabulary, old-address compatibility, identity, seeded replay and desktop selection passed.')
PY
