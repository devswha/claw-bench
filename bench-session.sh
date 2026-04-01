#!/usr/bin/env bash
# Benchmark: Memory usage over a long session
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Long Session Memory Benchmark ==="
echo "Duration: ${SESSION_DURATION}s | Poll interval: ${SESSION_POLL_INTERVAL}s"
echo ""

if ! command -v pidstat &>/dev/null; then
    echo "pidstat not found. Install: sudo apt install sysstat"
    exit 1
fi

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

monitor_session() {
    local label="$1"
    local bin="$2"
    echo "--- $label ---"

    "$bin" -p "Write a detailed 2000 word essay about the history of computing" --max-turns 1 \
        >/dev/null 2>&1 &
    local pid=$!

    local samples=()
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt "$SESSION_DURATION" ]; do
        local rss
        rss=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
        rss=$(echo "$rss" | tr -d ' ')
        if [ -n "$rss" ] && [ "$rss" -gt 0 ]; then
            samples+=("$rss")
        fi
        sleep "$SESSION_POLL_INTERVAL"
        elapsed=$((elapsed + SESSION_POLL_INTERVAL))
    done

    wait "$pid" 2>/dev/null || true

    if [ ${#samples[@]} -eq 0 ]; then
        echo "  No samples collected (process exited too quickly)"
        return
    fi

    local max_rss=0
    local sum=0
    for s in "${samples[@]}"; do
        sum=$((sum + s))
        if [ "$s" -gt "$max_rss" ]; then
            max_rss=$s
        fi
    done
    local avg_rss=$((sum / ${#samples[@]}))

    printf "  Samples:  %d\n" "${#samples[@]}"
    printf "  Avg RSS:  %s KB  (%s MB)\n" "$avg_rss" "$(echo "scale=1; $avg_rss/1024" | bc)"
    printf "  Peak RSS: %s KB  (%s MB)\n" "$max_rss" "$(echo "scale=1; $max_rss/1024" | bc)"
    echo ""
}

(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    monitor_session "Claw" "$CLAW_BIN"
    monitor_session "Claude" "$CLAUDE_BIN"
)
