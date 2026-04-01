#!/usr/bin/env bash
# Benchmark: Peak memory usage (RSS)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Peak Memory Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

measure_rss() {
    local label="$1"
    shift
    local rss
    rss=$(/usr/bin/time -v "$@" 2>&1 1>/dev/null | grep "Maximum resident" | awk '{print $NF}')
    printf "%-12s %s KB  (%s MB)\n" "$label" "$rss" "$(echo "scale=1; $rss/1024" | bc)"
}

echo "--- --version (minimal load) ---"
measure_rss "Claw" "$CLAW_BIN" --version
measure_rss "Claude" "$CLAUDE_BIN" --version

echo ""
echo "--- Single prompt (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    measure_rss "Claw" "$CLAW_BIN" -p 'say hi' --max-turns 1
    measure_rss "Claude" "$CLAUDE_BIN" -p 'say hi' --max-turns 1
)
