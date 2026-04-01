#!/usr/bin/env bash
# Benchmark: GC / memory allocation pressure (page faults + RSS growth)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Memory Allocation Pressure Benchmark ==="
echo ""

command -v perf &>/dev/null || { echo "perf not found. Install: sudo apt install linux-tools-$(uname -r)"; exit 1; }

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
        sleep "$POLL"
    done

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

    claw_perf=$(perf stat -e page-faults,minor-faults,major-faults \
        "$CLAW_BIN" -p 'say hi' --max-turns 1 2>&1 1>/dev/null)
    claude_perf=$(perf stat -e page-faults,minor-faults,major-faults \
        "$CLAUDE_BIN" -p 'say hi' --max-turns 1 2>&1 1>/dev/null)

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
)
