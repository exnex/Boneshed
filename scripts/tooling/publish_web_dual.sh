#!/usr/bin/env bash
# Publish audited production and separately launchable experimental lab web exports
# to an existing Pages asset branch. Never stage repository source or old site files.
set -euo pipefail
source "$(dirname "$0")/env.sh"
main_dir="$(cd "${1:?Usage: publish_web_dual.sh MAIN_EXPORT LAB_EXPORT [BRANCH]}" && pwd)"
lab_dir="$(cd "${2:?Missing experimental export directory}" && pwd)"
branch="${3:-gh-pages}"
git check-ref-format "refs/heads/$branch"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$main_dir" Web
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$lab_dir" Web
git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)"
parent="$(git -C "$REPO_ROOT" ls-remote origin "refs/heads/$branch" | cut -f1)"
parents=()
if [[ -n "$parent" ]]; then
    git -C "$REPO_ROOT" fetch origin "$branch"
    # Only permit replacing the known site export and its isolated lab subdirectory.
    git -C "$REPO_ROOT" ls-tree -r --name-only "$parent" | python3 -c '
import sys
assets={".nojekyll","index.html","index.js","index.wasm","index.pck","index.png","index.audio.worklet.js","index.audio.position.worklet.js","index.icon.png","index.apple-touch-icon.png"}
paths=set(sys.stdin.read().splitlines())
assert paths and all(p in assets or (p.startswith("melee-lab/") and p[len("melee-lab/"):] in assets) for p in paths), "Existing branch contains unrecognized site content"
'
    parents=(-p "$parent")
fi
staging="$(mktemp -d /tmp/boneshed-dual-pages.XXXXXX)"
temp_index="$(mktemp /tmp/boneshed-dual-index.XXXXXX)"
trap 'rm -rf "$staging"; rm -f "$temp_index"' EXIT
# Package auditor above guarantees only allowlisted export files in each root.
cp -a "$main_dir/." "$staging/"
mkdir -p "$staging/melee-lab"
cp -a "$lab_dir/." "$staging/melee-lab/"
export GIT_INDEX_FILE="$temp_index"
git -C "$REPO_ROOT" read-tree --empty
git --git-dir="$git_dir" --work-tree="$staging" add --all -- .
tree="$(git -C "$REPO_ROOT" write-tree)"
if [[ -n "$parent" && "$tree" = "$(git -C "$REPO_ROOT" rev-parse "$parent^{tree}")" ]]; then
    echo "Both audited exports already current on $branch."
    exit 0
fi
commit="$(git -C "$REPO_ROOT" commit-tree "$tree" "${parents[@]}" -m 'Publish Boneshed First Expedition and experimental directional melee lab')"
git -C "$REPO_ROOT" push origin "$commit:refs/heads/$branch"
echo "Published audited site to $branch at $commit (root + /melee-lab/)."
