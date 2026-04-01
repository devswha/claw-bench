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

# Run strace -c once and parse the summary table for openat, read, write counts.
# Returns three space-separated values: openat_count read_count write_count
get_io_counts() {
    local summary
    summary=$(strace -c $FORK_FLAG -e trace=openat,read,write "$@" 2>&1 1>/dev/null)

    local openat_count read_count write_count
    openat_count=$(echo "$summary" | awk '$NF == "openat" {print $4}')
    read_count=$(echo "$summary"   | awk '$NF == "read"   {print $4}')
    write_count=$(echo "$summary"  | awk '$NF == "write"  {print $4}')

    echo "${openat_count:-0} ${read_count:-0} ${write_count:-0}"
}

print_io_table() {
    local scenario="$1"
    shift

    echo "--- File I/O ($scenario) ---"
    printf "%-12s %-10s %-10s %-10s\n" "" "openat()" "read()" "write()"
    printf "%-12s %-10s %-10s %-10s\n" "" "-------" "------" "-------"

    local claw_counts claude_counts
    claw_counts=$(get_io_counts "$CLAW_BIN" "$@")
    claude_counts=$(get_io_counts "$CLAUDE_BIN" "$@")

    local claw_open claw_read claw_write
    read -r claw_open claw_read claw_write <<< "$claw_counts"

    local claude_open claude_read claude_write
    read -r claude_open claude_read claude_write <<< "$claude_counts"

    printf "%-12s %-10s %-10s %-10s\n" "Claw" "$claw_open" "$claw_read" "$claw_write"
    printf "%-12s %-10s %-10s %-10s\n" "Claude" "$claude_open" "$claude_read" "$claude_write"

    # Ratios
    local ratio_open ratio_read ratio_write
    if [ "${claw_open:-0}" -gt 0 ] 2>/dev/null; then
        ratio_open=$(echo "scale=1; $claude_open / $claw_open" | bc)x
    else
        ratio_open="N/A"
    fi
    if [ "${claw_read:-0}" -gt 0 ] 2>/dev/null; then
        ratio_read=$(echo "scale=1; $claude_read / $claw_read" | bc)x
    else
        ratio_read="N/A"
    fi
    if [ "${claw_write:-0}" -gt 0 ] 2>/dev/null; then
        ratio_write=$(echo "scale=1; $claude_write / $claw_write" | bc)x
    else
        ratio_write="N/A"
    fi

    printf "%-12s %-10s %-10s %-10s\n" "Ratio" "$ratio_open" "$ratio_read" "$ratio_write"
    echo ""
}

print_io_table "--version" --version

echo "--- File I/O (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    print_io_table "API call" -p 'say hi' --max-turns 1
)
