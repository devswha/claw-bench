#!/usr/bin/env bash
# Benchmark: File I/O overhead (openat, read, write counts)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/env.sh"

echo "=== File I/O Overhead Benchmark ==="
echo ""

command -v strace &>/dev/null || { echo "strace not found. Install: sudo apt install strace"; exit 1; }
command -v bc &>/dev/null || { echo "bc required: sudo apt install bc"; exit 1; }

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
    local timeout_secs="$1"
    shift
    local summary
    set +e
    if [ "$timeout_secs" -gt 0 ] 2>/dev/null; then
        summary=$(timeout -s INT "$timeout_secs" strace -c $FORK_FLAG -e trace=openat,read,write "$@" 2>&1 1>/dev/null)
    else
        summary=$(strace -c $FORK_FLAG -e trace=openat,read,write "$@" 2>&1 1>/dev/null)
    fi
    local status=$?
    set -e

    if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
        return "$status"
    fi

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
    set +e
    claw_counts=$(get_io_counts "$io_timeout" "$CLAW_BIN" "$@")
    local claw_status=$?
    claude_counts=$(get_io_counts "$io_timeout" "$CLAUDE_BIN" "$@")
    local claude_status=$?
    set -e

    local claw_open claw_read claw_write
    read -r claw_open claw_read claw_write <<< "$claw_counts"

    local claude_open claude_read claude_write
    read -r claude_open claude_read claude_write <<< "$claude_counts"

    if [ -z "$claw_open" ] || [ -z "$claw_read" ] || [ -z "$claw_write" ] || \
       [ -z "$claude_open" ] || [ -z "$claude_read" ] || [ -z "$claude_write" ]; then
        echo "ERROR: failed to parse I/O counts for $scenario" >&2
        return 1
    fi

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
    if [ "$claw_status" -eq 124 ] || [ "$claude_status" -eq 124 ]; then
        echo "Note: $scenario I/O profiling was interrupted at ${io_timeout}s to cap lingering helper activity."
    fi
    echo ""
}

io_timeout=0
print_io_table "--version" --version

(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    io_timeout="${API_CALL_TIMEOUT:-45}"
    print_io_table "API call" -p 'say hi' --max-turns 1
)
