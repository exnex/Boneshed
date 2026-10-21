#!/usr/bin/env bash
# Benchmarks the visual showcase (low/medium/high presets) against the melee lab in GL
# Compatibility and, when a Vulkan driver is present, Forward+. On the cloud machine
# both renderers are CPU software rasterisers (llvmpipe / lavapipe): the numbers rank
# relative cost and count draw calls, nodes and memory; they are NOT desktop GPU
# frame times. Run the same script on a desktop for representative numbers.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
output="${1:-$REPO_ROOT/artifacts/visual-showcase-bench-$(date -u +%Y%m%dT%H%M%SZ)}"
test ! -e "$output" || { echo 'Use a new output directory.' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
frames="${BONESHED_BENCH_FRAMES:-240}"
xvfb=(xvfb-run -a -s "-screen 0 1280x720x24 -nolisten tcp")
if [ -n "${DISPLAY:-}" ] && [ "${BONESHED_BENCH_XVFB:-1}" = 0 ]; then xvfb=(); fi
timeout 180 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import > "$output/import.log" 2>&1
renderers=(gl_compatibility)
if ls /usr/share/vulkan/icd.d/ 2>/dev/null | grep -q . || [ "${BONESHED_FORWARD:-0}" = 1 ]; then renderers+=(forward_plus); fi
for renderer in "${renderers[@]}"; do
    # Warm the texture cache once so startup numbers separate generation from loading.
    timeout 1800 "${xvfb[@]}" "$GODOT_BIN" --path "$REPO_ROOT" --rendering-method "$renderer" --audio-driver Dummy \
        --script res://scripts/qa/visual_showcase_bench.gd -- --evidence-dir="$output" --frames="$frames" \
        > "$output/bench_$renderer.log" 2>&1
    grep '^{' "$output/bench_$renderer.log" || true
done
echo "Results: $output"
