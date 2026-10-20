#!/usr/bin/env bash
# Parse-checks every melee lab and lab QA script (a parse error otherwise stalls the
# engine's debugger in --script mode).
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
status=0
for script in "$REPO_ROOT"/scripts/melee_lab/*.gd "$REPO_ROOT"/scripts/qa/melee_lab_*.gd; do
    rel="res://${script#"$REPO_ROOT"/}"
    out="$(timeout 30 "$GODOT_BIN" --headless --path "$REPO_ROOT" --check-only --script "$rel" < /dev/null 2>&1 || true)"
    if grep -q 'SCRIPT ERROR\|Parse Error' <<<"$out"; then
        echo "$out" | grep -A1 'SCRIPT ERROR' >&2
        status=1
    fi
done
exit $status
