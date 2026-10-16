#!/usr/bin/env bash
# Adversarial combat probe: measurements, not pass/fail design assertions.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
run_dir="${1:-$REPO_ROOT/artifacts/probe-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$run_dir"
run_dir="$(cd "$run_dir" && pwd)"
test -z "$(ls -A "$run_dir")" || { echo 'Use a new empty evidence directory.' >&2; exit 1; }
export LIBGL_ALWAYS_SOFTWARE=1
# Measurements run headless; only camera scenarios are rendered (llvmpipe is slow).
timeout 900 "$GODOT_BIN" --headless --path "$REPO_ROOT" --fixed-fps 60 \
    --script res://scripts/qa/adversarial_probe.gd -- "--evidence-dir=$run_dir" > "$run_dir/probe.log" 2>&1
mkdir -p "$run_dir/rendered"
timeout 300 xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$GODOT_BIN" --path "$REPO_ROOT" \
    --rendering-method gl_compatibility --audio-driver Dummy --fixed-fps 60 \
    --script res://scripts/qa/adversarial_probe.gd -- "--evidence-dir=$run_dir/rendered" --only=camera_checks > "$run_dir/rendered/probe.log" 2>&1
for log in "$run_dir/probe.log" "$run_dir/rendered/probe.log"; do
    ! grep -q 'ERROR' "$log" || { echo "Engine errors; see $log" >&2; exit 1; }
done
test -f "$run_dir/probe.json" && test -f "$run_dir/rendered/probe.json"
echo "Probe complete; evidence: $run_dir"
