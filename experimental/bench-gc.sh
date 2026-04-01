#!/usr/bin/env bash
# Benchmark: GC / memory allocation pressure (page faults + RSS growth)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/env.sh"

echo "=== Memory Allocation Pressure Benchmark ==="
echo ""

command -v perf &>/dev/null || { echo "perf not found. Install: sudo apt install linux-tools-$(uname -r)"; exit 1; }
command -v bc &>/dev/null || { echo "bc required: sudo apt install bc"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

POLL="${GC_POLL_INTERVAL:-0.1}"

extract_faults() {
    local output="$1"
    local event="$2"
    echo "$output" | grep "$event" | awk '{gsub(/,/,"",$1); print $1}'
}

run_perf_faults() {
    local timeout_secs="$1"
    shift
    local output

    set +e
    output=$(timeout -s INT "$timeout_secs" perf stat -e page-faults,minor-faults,major-faults "$@" 2>&1 1>/dev/null)
    local status=$?
    set -e

    if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
        return "$status"
    fi

    printf "%s\n" "$output"
}

measure_rss_growth() {
    local label="$1"
    local bin="$2"
    shift 2

    "$bin" "$@" >/dev/null 2>&1 &
    local pid=$!

    trap "kill $pid 2>/dev/null; wait $pid 2>/dev/null" INT TERM

    local first_rss=0
    local peak_rss=0
    local samples=0
    local start_ts
    start_ts=$(date +%s)

    while kill -0 "$pid" 2>/dev/null; do
        local rss
        rss=$(cat "/proc/$pid/status" 2>/dev/null | grep "^VmRSS:" | awk '{print $2}' || echo "0")
        if [ -n "$rss" ] && [ "$rss" -gt 0 ] 2>/dev/null; then
            if [ "$first_rss" -eq 0 ]; then
                first_rss=$rss
            fi
            if [ "$rss" -gt "$peak_rss" ]; then
                peak_rss=$rss
            fi
            samples=$((samples + 1))
        fi
        if [ "$(date +%s)" -ge $((start_ts + ${API_CALL_TIMEOUT:-45})) ]; then
            break
        fi
        sleep "$POLL"
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
    trap - INT TERM

    local growth=0
    if [ "$first_rss" -gt 0 ]; then
        growth=$((peak_rss - first_rss))
    fi

    echo "$peak_rss $growth $samples"
}

echo "--- Page Faults (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    set +e
    claw_perf=$(run_perf_faults "${API_CALL_TIMEOUT:-45}" "$CLAW_BIN" -p 'say hi' --max-turns 1)
    claw_perf_status=$?
    claude_perf=$(run_perf_faults "${API_CALL_TIMEOUT:-45}" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)
    claude_perf_status=$?
    set -e

    printf "%-16s %-12s %-12s %s\n" "" "Claw" "Claude" "Ratio"
    printf "%-16s %-12s %-12s %s\n" "" "----" "------" "-----"

    for event in page-faults minor-faults major-faults; do
        claw_val=$(extract_faults "$claw_perf" "$event")
        claude_val=$(extract_faults "$claude_perf" "$event")

        if [ -n "$claw_val" ] && [ "$claw_val" -gt 0 ] 2>/dev/null; then
            ratio=$(echo "scale=1; $claude_val / $claw_val" | bc)
            ratio="${ratio}x"
        else
            ratio="N/A"
        fi

        printf "%-16s %-12s %-12s %s\n" "$event" "${claw_val:-0}" "${claude_val:-0}" "$ratio"
    done
    if [ -z "$(extract_faults "$claw_perf" page-faults)" ] || [ -z "$(extract_faults "$claude_perf" page-faults)" ]; then
        echo "ERROR: failed to parse page-fault counters" >&2
        exit 1
    fi
    if [ "$claw_perf_status" -eq 124 ] || [ "$claude_perf_status" -eq 124 ]; then
        echo "Note: page-fault profiling was interrupted at ${API_CALL_TIMEOUT:-45}s to cap lingering helper activity."
    fi
    echo ""

    echo "--- RSS Growth (API call) ---"

    read -r claw_peak claw_growth claw_samples <<< "$(measure_rss_growth "Claw" "$CLAW_BIN" -p 'say hi' --max-turns 1)"
    read -r claude_peak claude_growth claude_samples <<< "$(measure_rss_growth "Claude" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)"

    printf "%-16s %-12s %-12s %s\n" "" "Claw" "Claude" "Ratio"
    printf "%-16s %-12s %-12s %s\n" "" "----" "------" "-----"

    if [ "$claw_peak" -gt 0 ] 2>/dev/null; then
        peak_ratio=$(echo "scale=1; $claude_peak / $claw_peak" | bc)
        peak_ratio="${peak_ratio}x"
    else
        peak_ratio="N/A"
    fi
    if [ "$claw_growth" -gt 0 ] 2>/dev/null; then
        growth_ratio=$(echo "scale=1; $claude_growth / $claw_growth" | bc)
        growth_ratio="${growth_ratio}x"
    else
        growth_ratio="N/A"
    fi

    printf "%-16s %-12s %-12s %s\n" "Peak RSS (KB)" "$claw_peak" "$claude_peak" "$peak_ratio"
    printf "%-16s %-12s %-12s %s\n" "RSS growth (KB)" "$claw_growth" "$claude_growth" "$growth_ratio"
    printf "%-16s %-12s %-12s\n" "Samples" "$claw_samples" "$claude_samples"
    echo "Note: RSS sampling is capped at ${API_CALL_TIMEOUT:-45}s if a process lingers after responding."
)
