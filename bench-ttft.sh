#!/usr/bin/env bash
# Benchmark: Time to first token (TTFT)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Time to First Token (TTFT) Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

measure_ttft() {
    local label="$1"
    local bin="$2"
    local times=()

    for i in $(seq 1 5); do
        local start end elapsed
        start=$(date +%s%N)
        "$bin" -p "say hi" --max-turns 1 >/dev/null 2>&1
        end=$(date +%s%N)
        elapsed=$(echo "scale=3; ($end - $start) / 1000000000" | bc)
        times+=("$elapsed")
    done

    local sum=0
    for t in "${times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    local avg=$(echo "scale=3; $sum / ${#times[@]}" | bc)
    local min=$(printf '%s\n' "${times[@]}" | sort -n | head -1)
    local max=$(printf '%s\n' "${times[@]}" | sort -n | tail -1)

    printf "%-12s avg: %6ss  min: %6ss  max: %6ss  (5 runs)\n" "$label" "$avg" "$min" "$max"
}

echo "Prompt: 'say hi' (--max-turns 1)"
echo ""
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    measure_ttft "Claw" "$CLAW_BIN"
    measure_ttft "Claude" "$CLAUDE_BIN"
)
