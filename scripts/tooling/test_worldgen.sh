#!/usr/bin/env bash
# Headless checks for the keyword WorldBlueprint prototype. Independent of combat tests.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
mkdir -p "$REPO_ROOT/artifacts"
touch "$REPO_ROOT/artifacts/.gdignore"
run_dir="${1:-$REPO_ROOT/artifacts/worldgen-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$run_dir"
run_dir="$(cd "$run_dir" && pwd)"
test -z "$(ls -A "$run_dir")" || { echo 'Use a new empty evidence directory.' >&2; exit 1; }
python3 - "$GODOT_BIN" "$REPO_ROOT" "$run_dir" <<'PY'
import filecmp, json, pathlib, subprocess, sys
engine, repo, output = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
base = [engine, '--headless', '--path', str(repo)]
def run(name, args, expected=0, seconds=120):
    with (output/f'{name}.log').open('w') as log:
        result = subprocess.run(['timeout', str(seconds), *args], stdout=log, stderr=subprocess.STDOUT)
    text = (output/f'{name}.log').read_text()
    assert result.returncode == expected, f'{name}: exit {result.returncode}, see {output}/{name}.log'
    assert 'SCRIPT ERROR:' not in text and 'ERROR:' not in text, f'{name}: engine errors in log'
    print(f'{name}: expected exit {expected} confirmed', flush=True)
    return [json.loads(line) for line in text.splitlines() if line.startswith('{')]
run('import', base + ['--editor', '--import'])
records = run('worldgen_tests', base + ['--script', 'res://scripts/qa/worldgen_tests.gd'])
summary = next(r for r in records if r.get('summary'))
assert summary['failed'] == 0 and summary['passed'] >= 80, summary
# Regenerate the committed examples into the run directory; they must match byte for byte.
examples = output/'examples'
run('worldgen_demo', base + ['--script', 'res://scripts/qa/worldgen_demo.gd', '--', f'--out={examples}'])
committed = repo/'docs/worldgen/examples'
names = sorted(p.name for p in committed.iterdir())
assert names == sorted(p.name for p in examples.iterdir()), 'example file set differs'
_, mismatch, errors = filecmp.cmpfiles(committed, examples, names, shallow=False)
assert not mismatch and not errors, f'regenerated examples differ: {mismatch or errors}'
print(f'{summary["passed"]} checks passed; {len(names)} example files regenerate identically; evidence: {output}')
PY
