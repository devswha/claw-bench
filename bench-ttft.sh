#!/usr/bin/env bash
# Benchmark: Time to first token (TTFT)
set -euo pipefail
source "$(dirname "$0")/env.sh"

command -v bc &>/dev/null || { echo "bc required: sudo apt install bc"; exit 1; }

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

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
    shift
    local times=()
    local timed_out=0

    for i in $(seq 1 5); do
        local start end elapsed status
        start=$(date +%s%N)
        set +e
        "$@" >/dev/null 2>&1
        status=$?
        if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
            "$@" >/dev/null 2>&1
            status=$?
        fi
        set -e
        if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
            echo "ERROR: $label benchmark command failed (exit $status)" >&2
            return "$status"
        fi
        end=$(date +%s%N)
        elapsed=$(echo "scale=3; ($end - $start) / 1000000000" | bc)
        times+=("$elapsed")
        if [ "$status" -eq 124 ]; then
            timed_out=$((timed_out + 1))
        fi
    done

    local sum=0
    for t in "${times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    local avg=$(echo "scale=3; $sum / ${#times[@]}" | bc)
    local min=$(printf '%s\n' "${times[@]}" | sort -n | head -1)
    local max=$(printf '%s\n' "${times[@]}" | sort -n | tail -1)

    printf "%-12s avg: %6ss  min: %6ss  max: %6ss  (5 runs" "$label" "$avg" "$min" "$max"
    if [ "$timed_out" -gt 0 ]; then
        printf ", %s timeout" "$timed_out"
        if [ "$timed_out" -gt 1 ]; then
            printf "s"
        fi
    fi
    printf ")\n"
}

echo "Prompt: 'say hi' (--max-turns 1)"
echo ""
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    measure_ttft "Claw" timeout "${API_CALL_TIMEOUT:-45}" "$CLAW_BIN" -p "say hi" --max-turns 1
    measure_ttft "Claude" timeout "${API_CALL_TIMEOUT:-45}" "$CLAUDE_BIN" -p "say hi" --max-turns 1
)

if [ "$has_codex" = true ]; then
    measure_ttft "Codex" timeout "${API_CALL_TIMEOUT:-45}" "$CODEX_BIN" -a never exec -s workspace-write -m "${CODEX_MODEL:-gpt-5.3-codex}" -o /dev/null "say hi"
fi
