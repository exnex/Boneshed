#!/usr/bin/env bash
# Fetch the pinned CC0 animation trial asset outside the checkout and verify it.
# Evaluation only: see data/animation_lab/trial_asset.json and docs/ANIMATION_PIPELINE.md.
set -euo pipefail
source "$(dirname "$0")/env.sh"
python3 - "$REPO_ROOT/data/animation_lab/trial_asset.json" "$TOOLS_ROOT/animation-trial" <<'PY'
import hashlib, json, pathlib, subprocess, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
target = pathlib.Path(sys.argv[2]) / manifest['commit']
target.mkdir(parents=True, exist_ok=True)
for entry in manifest['files']:
    path = target / entry['name']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        staging = path.with_suffix('.tmp')
        subprocess.run(['curl', '-fL', '--retry', '2', '--max-time', '180', manifest['base_url'] + entry['name'], '-o', str(staging)], check=True)
        staging.replace(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == entry['sha256'], f"{entry['name']}: sha256 {digest} != pinned {entry['sha256']}"
    print(f"verified {path}")
print(target)
PY
