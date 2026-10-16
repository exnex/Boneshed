#!/usr/bin/env bash
# Publish only the audited export to a separate Pages source branch.
# This does not merge source code, enable Pages, or change repository visibility.
set -euo pipefail
source "$(dirname "$0")/env.sh"
build_dir="$(cd "${1:?Usage: publish_web_preview.sh BUILD_DIRECTORY}" && pwd)"
branch="${2:-preview/browser-courtyard}"
git check-ref-format "refs/heads/$branch"
python3 "$REPO_ROOT/scripts/tooling/package_web.py" "$build_dir" Web
git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)"
parent="$(git -C "$REPO_ROOT" ls-remote origin "refs/heads/$branch" | cut -f1)"
parent_args=()
if test -n "$parent"; then
    git -C "$REPO_ROOT" fetch origin "$branch"
    # Refuse to replace a branch that contains anything beyond an exported site.
    git -C "$REPO_ROOT" ls-tree -r --name-only "$parent" | python3 -c '
import sys
allowed={".nojekyll","index.html","index.js","index.wasm","index.pck","index.png","index.audio.worklet.js","index.audio.position.worklet.js","index.icon.png","index.apple-touch-icon.png"}
names=set(sys.stdin.read().splitlines())
assert names and names<=allowed, "Existing branch is not an isolated web export"
'
    parent_args=(-p "$parent")
fi
temp_index="$(mktemp /tmp/boneshed-pages-index.XXXXXX)"
trap 'rm -f "$temp_index"' EXIT
export GIT_INDEX_FILE="$temp_index"
git -C "$REPO_ROOT" read-tree --empty
git -C "$build_dir" --git-dir="$git_dir" --work-tree="$build_dir" add --all -- .
tree="$(git -C "$REPO_ROOT" write-tree)"
if test -n "$parent" && test "$tree" = "$(git -C "$REPO_ROOT" rev-parse "$parent^{tree}")"; then
    echo "Export already current on $branch at $parent."
    exit 0
fi
commit="$(git -C "$REPO_ROOT" commit-tree "$tree" "${parent_args[@]}" -m 'Publish audited Boneshed browser preview')"
git -C "$REPO_ROOT" push origin "$commit:refs/heads/$branch"
echo "Export uploaded to $branch at $commit. Select this branch / (root) in GitHub Settings > Pages to publish."
