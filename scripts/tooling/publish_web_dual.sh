#!/usr/bin/env bash
# Publish audited production and separately launchable experimental lab web exports
# to an existing Pages asset branch. Never stage repository source or old site files.
# An optional fourth directory is published at /directional-expedition/ (experimental).
set -euo pipefail
source "$(dirname "$0")/env.sh"
main_dir="$(cd "${1:?Usage: publish_web_dual.sh MAIN_EXPORT LAB_EXPORT [BRANCH] [DIRECTIONAL_EXPORT] [ADAPTIVE_EXPORT]}" && pwd)"
lab_dir="$(cd "${2:?Missing experimental export directory}" && pwd)"
branch="${3:-gh-pages}"
expedition_dir=""
if [[ -n "${4:-}" ]]; then
    expedition_dir="$(cd "$4" && pwd)"
fi
adaptive_dir=""
if [[ -n "${5:-}" ]]; then
    adaptive_dir="$(cd "$5" && pwd)"
fi
git check-ref-format "refs/heads/$branch"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$main_dir" Web
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$lab_dir" Web
if [[ -n "$expedition_dir" ]]; then
    python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$expedition_dir" Web
fi
if [[ -n "$adaptive_dir" ]]; then
    python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$adaptive_dir" Web
fi
git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)"
parent="$(git -C "$REPO_ROOT" ls-remote origin "refs/heads/$branch" | cut -f1)"
parents=()
if [[ -n "$parent" ]]; then
    git -C "$REPO_ROOT" fetch origin "$branch"
    # Only permit replacing the known site export and its isolated experimental subdirectories.
    git -C "$REPO_ROOT" ls-tree -r --name-only "$parent" | python3 -c '
import sys
assets={".nojekyll","index.html","index.js","index.wasm","index.pck","index.png","index.audio.worklet.js","index.audio.position.worklet.js","index.icon.png","index.apple-touch-icon.png"}
paths=set(sys.stdin.read().splitlines())
subdirectories=("melee-lab/","directional-expedition/","adaptive-combat/")
assert paths and all(p in assets or any(p.startswith(d) and p[len(d):] in assets for d in subdirectories) for p in paths), "Existing branch contains unrecognized site content"
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
if [[ -n "$expedition_dir" ]]; then
    mkdir -p "$staging/directional-expedition"
    cp -a "$expedition_dir/." "$staging/directional-expedition/"
fi
if [[ -n "$adaptive_dir" ]]; then
    mkdir -p "$staging/adaptive-combat"
    cp -a "$adaptive_dir/." "$staging/adaptive-combat/"
fi
export GIT_INDEX_FILE="$temp_index"
git -C "$REPO_ROOT" read-tree --empty
git --git-dir="$git_dir" --work-tree="$staging" add --all -- .
tree="$(git -C "$REPO_ROOT" write-tree)"
if [[ -n "$parent" && "$tree" = "$(git -C "$REPO_ROOT" rev-parse "$parent^{tree}")" ]]; then
    echo "All audited exports already current on $branch."
    exit 0
fi
commit="$(git -C "$REPO_ROOT" commit-tree "$tree" "${parents[@]}" -m 'Publish Boneshed root and separate experimental scenes')"
git -C "$REPO_ROOT" push origin "$commit:refs/heads/$branch"
echo "Published audited site to $branch at $commit (root, /melee-lab/, optional /directional-expedition/ and /adaptive-combat/)."
