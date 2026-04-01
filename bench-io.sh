#!/usr/bin/env bash
# Benchmark: File I/O overhead (openat, read, write counts)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== File I/O Overhead Benchmark ==="
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

count_io() {
    local label="$1"
    local syscall="$2"
    shift 2
    local count
    count=$(strace -e trace="$syscall" $FORK_FLAG "$@" 2>&1 1>/dev/null | grep -c "^$syscall(" || echo "0")
    echo "$count"
}

print_io_table() {
    local scenario="$1"
    shift

    echo "--- File I/O ($scenario) ---"
    printf "%-12s %-10s %-10s %-10s\n" "" "open()" "read()" "write()"
    printf "%-12s %-10s %-10s %-10s\n" "" "------" "------" "-------"

    local claw_open claw_read claw_write
    claw_open=$(count_io "Claw" "openat" "$CLAW_BIN" "$@")
    claw_read=$(count_io "Claw" "read" "$CLAW_BIN" "$@")
    claw_write=$(count_io "Claw" "write" "$CLAW_BIN" "$@")

    local claude_open claude_read claude_write
    claude_open=$(count_io "Claude" "openat" "$CLAUDE_BIN" "$@")
    claude_read=$(count_io "Claude" "read" "$CLAUDE_BIN" "$@")
    claude_write=$(count_io "Claude" "write" "$CLAUDE_BIN" "$@")

    printf "%-12s %-10s %-10s %-10s\n" "Claw" "$claw_open" "$claw_read" "$claw_write"
    printf "%-12s %-10s %-10s %-10s\n" "Claude" "$claude_open" "$claude_read" "$claude_write"

    # Ratios
    local ratio_open ratio_read ratio_write
    if [ "$claw_open" -gt 0 ] 2>/dev/null; then
        ratio_open=$(echo "scale=1; $claude_open / $claw_open" | bc)
    else
        ratio_open="N/A"
    fi
    if [ "$claw_read" -gt 0 ] 2>/dev/null; then
        ratio_read=$(echo "scale=1; $claude_read / $claw_read" | bc)
    else
        ratio_read="N/A"
    fi
    if [ "$claw_write" -gt 0 ] 2>/dev/null; then
        ratio_write=$(echo "scale=1; $claude_write / $claw_write" | bc)
    else
        ratio_write="N/A"
    fi

    printf "%-12s %-10s %-10s %-10s\n" "Ratio" "${ratio_open}x" "${ratio_read}x" "${ratio_write}x"
    echo ""
}

print_io_table "--version" --version

echo "--- File I/O (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    print_io_table "API call" -p 'say hi' --max-turns 1
)
