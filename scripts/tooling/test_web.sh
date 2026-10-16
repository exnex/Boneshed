#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/web-test-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
python3 -c 'import playwright.sync_api' || { echo 'Browser tests need the Python Playwright package and Chromium (test tooling only).' >&2; exit 1; }
bash "$REPO_ROOT/scripts/tooling/export_web.sh" "$output/release" Web > "$output/export-release.log" 2>&1
bash "$REPO_ROOT/scripts/tooling/export_web.sh" "$output/qa" 'Web QA' > "$output/export-qa.log" 2>&1
timeout 600 python3 "$REPO_ROOT/scripts/qa/browser_test.py" "$output/release" "$output/qa" "$output/browser" > "$output/browser.log" 2>&1
cat "$output/browser.log"
echo "Browser evidence and ready-to-upload release.zip: $output"
