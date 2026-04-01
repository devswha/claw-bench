#!/usr/bin/env bash
# Benchmark: Thread/process footprint
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Thread Footprint Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

count_threads() {
    local label="$1"
    local bin="$2"
    shift 2

    # Start process in background
    "$bin" "$@" >/dev/null 2>&1 &
    local pid=$!

    # Wait briefly for process to initialize
    sleep 0.5

    local threads=0
    if kill -0 "$pid" 2>/dev/null; then
        threads=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
    fi

    # Clean up
    wait "$pid" 2>/dev/null || true

    echo "$threads"
}

printf "%-12s %-10s %-10s %s\n" "" "Claw" "Claude" "Ratio"
printf "%-12s %-10s %-10s %s\n" "" "----" "------" "-----"

# Idle scenario: --version starts and exits quickly, so we use a longer-running command
# For thread count we need the process alive, use -p with API
echo "--- Thread Count (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    # Start processes and measure threads while alive
    "$CLAW_BIN" -p 'Write a short paragraph about benchmarking' --max-turns 1 >/dev/null 2>&1 &
    claw_pid=$!
    sleep 1

    claw_threads=0
    if kill -0 "$claw_pid" 2>/dev/null; then
        claw_threads=$(ls "/proc/$claw_pid/task" 2>/dev/null | wc -l)
        claw_lwp=$(ps --no-headers -o nlwp -p "$claw_pid" 2>/dev/null | tr -d ' ')
    fi
    wait "$claw_pid" 2>/dev/null || true

    "$CLAUDE_BIN" -p 'Write a short paragraph about benchmarking' --max-turns 1 >/dev/null 2>&1 &
    claude_pid=$!
    sleep 2

    claude_threads=0
    if kill -0 "$claude_pid" 2>/dev/null; then
        claude_threads=$(ls "/proc/$claude_pid/task" 2>/dev/null | wc -l)
        claude_lwp=$(ps --no-headers -o nlwp -p "$claude_pid" 2>/dev/null | tr -d ' ')
    fi
    wait "$claude_pid" 2>/dev/null || true

    if [ "$claw_threads" -gt 0 ] 2>/dev/null; then
        ratio=$(echo "scale=1; $claude_threads / $claw_threads" | bc)
    else
        ratio="N/A"
    fi

    printf "%-12s %-10s %-10s %s\n" "Threads" "$claw_threads" "$claude_threads" "${ratio}x"
    printf "%-12s %-10s %-10s\n" "LWP" "${claw_lwp:-N/A}" "${claude_lwp:-N/A}"
)
