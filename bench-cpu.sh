#!/usr/bin/env bash
# Benchmark: CPU hardware counters (perf stat)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== CPU Hardware Counters Benchmark ==="
echo ""

command -v perf &>/dev/null || { echo "perf not found. Install: sudo apt install linux-tools-$(uname -r)"; exit 1; }
command -v bc &>/dev/null || { echo "bc required: apt install bc"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

EVENTS="${PERF_EVENTS:-cycles,instructions,cache-misses,cache-references,branch-misses}"

run_perf() {
    local label="$1"
    shift
    echo "--- $label ---"
    perf stat -e "$EVENTS" "$@" 2>&1 1>/dev/null | \
        grep -E '^\s+[0-9]' | \
        while read -r line; do
            printf "  %s\n" "$line"
        done
    echo ""
}

extract_counter() {
    local output="$1"
    local event="$2"
    echo "$output" | grep "$event" | awk '{gsub(/,/,"",$1); print $1}'
}

echo "=== --version ==="
echo ""

claw_output=$(perf stat -e "$EVENTS" "$CLAW_BIN" --version 2>&1 1>/dev/null)
claude_output=$(perf stat -e "$EVENTS" "$CLAUDE_BIN" --version 2>&1 1>/dev/null)

printf "%-20s %-16s %-16s %s\n" "Counter" "Claw" "Claude" "Ratio"
printf "%-20s %-16s %-16s %s\n" "-------" "----" "------" "-----"

IFS=',' read -ra EVENT_LIST <<< "$EVENTS"
for event in "${EVENT_LIST[@]}"; do
    claw_val=$(extract_counter "$claw_output" "$event")
    claude_val=$(extract_counter "$claude_output" "$event")

    if [ -n "$claw_val" ] && [ "$claw_val" -gt 0 ] 2>/dev/null; then
        ratio=$(echo "scale=1; $claude_val / $claw_val" | bc)
        ratio="${ratio}x"
    else
        ratio="N/A"
    fi

    printf "%-20s %-16s %-16s %s\n" "$event" "$claw_val" "$claude_val" "$ratio"
done

# IPC calculation (only if both cycles and instructions are in the event list)
has_cycles=0
has_instructions=0
for event in "${EVENT_LIST[@]}"; do
    [ "$event" = "cycles" ] && has_cycles=1
    [ "$event" = "instructions" ] && has_instructions=1
done

if [ "$has_cycles" -eq 1 ] && [ "$has_instructions" -eq 1 ]; then
    claw_cycles=$(extract_counter "$claw_output" "cycles")
    claw_instr=$(extract_counter "$claw_output" "instructions")
    claude_cycles=$(extract_counter "$claude_output" "cycles")
    claude_instr=$(extract_counter "$claude_output" "instructions")

    if [ -n "$claw_cycles" ] && [ "$claw_cycles" -gt 0 ] 2>/dev/null; then
        claw_ipc=$(echo "scale=2; $claw_instr / $claw_cycles" | bc)
    else
        claw_ipc="N/A"
    fi
    if [ -n "$claude_cycles" ] && [ "$claude_cycles" -gt 0 ] 2>/dev/null; then
        claude_ipc=$(echo "scale=2; $claude_instr / $claude_cycles" | bc)
    else
        claude_ipc="N/A"
    fi

    if [ "$claw_ipc" != "N/A" ] && [ "$claude_ipc" != "N/A" ] && \
       [ "$(echo "$claw_ipc > 0" | bc)" -eq 1 ]; then
        ipc_ratio=$(echo "scale=2; $claw_ipc / $claude_ipc" | bc)
        ipc_ratio="${ipc_ratio}x"
    else
        ipc_ratio="N/A"
    fi

    printf "%-20s %-16s %-16s %s\n" "IPC" "$claw_ipc" "$claude_ipc" "$ipc_ratio"
fi
echo ""

echo "=== API call ==="
echo ""
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    run_perf "Claw (API)" "$CLAW_BIN" -p 'say hi' --max-turns 1
    run_perf "Claude (API)" "$CLAUDE_BIN" -p 'say hi' --max-turns 1
)
