#!/usr/bin/env bash
# Benchmark: System call count and breakdown
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Syscall Profiling Benchmark ==="
echo ""

command -v strace &>/dev/null || { echo "strace not found. Install: sudo apt install strace"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

FORK_FLAG=""
if [ "${STRACE_FOLLOW_FORKS:-true}" = "true" ]; then
    FORK_FLAG="-f"
fi

count_syscalls() {
    local label="$1"
    shift
    local output
    output=$(strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null)
    local total
    total=$(echo "$output" | grep "^100.00" | awk '{print $4}' || echo "0")
    if [ "$total" = "0" ] || [ -z "$total" ]; then
        total=$(echo "$output" | tail -1 | awk '{print $4}' || echo "0")
    fi
    echo "$total"
}

print_top_syscalls() {
    local label="$1"
    shift
    echo "--- Top Syscalls ($label) ---"
    strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null | \
        grep -E '^\s+[0-9]' | \
        sort -k4 -rn | \
        head -10 | \
        awk '{printf "  %-16s %s\n", $NF, $4}'
    echo ""
}

echo "--- Syscall Count (--version) ---"
claw_count=$(count_syscalls "Claw" "$CLAW_BIN" --version)
claude_count=$(count_syscalls "Claude" "$CLAUDE_BIN" --version)

if [ "$claw_count" -gt 0 ] 2>/dev/null; then
    ratio=$(echo "scale=1; $claude_count / $claw_count" | bc)
else
    ratio="N/A"
fi

printf "%-12s %s syscalls\n" "Claw" "$claw_count"
printf "%-12s %s syscalls  (%sx)\n" "Claude" "$claude_count" "$ratio"
echo ""

print_top_syscalls "Claw --version" "$CLAW_BIN" --version
print_top_syscalls "Claude --version" "$CLAUDE_BIN" --version

echo "--- Syscall Count (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    claw_api=$(count_syscalls "Claw" "$CLAW_BIN" -p 'say hi' --max-turns 1)
    claude_api=$(count_syscalls "Claude" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)

    if [ "$claw_api" -gt 0 ] 2>/dev/null; then
        ratio_api=$(echo "scale=1; $claude_api / $claw_api" | bc)
    else
        ratio_api="N/A"
    fi

    printf "%-12s %s syscalls\n" "Claw" "$claw_api"
    printf "%-12s %s syscalls  (%sx)\n" "Claude" "$claude_api" "$ratio_api"
)
