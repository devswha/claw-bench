#!/usr/bin/env bash
# Benchmark: System call count and breakdown
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/env.sh"

echo "=== Syscall Profiling Benchmark ==="
echo ""

command -v strace &>/dev/null || { echo "strace not found. Install: sudo apt install strace"; exit 1; }
command -v bc &>/dev/null || { echo "bc required: apt install bc"; exit 1; }

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

run_strace_summary() {
    local timeout_secs="${1:-0}"
    shift

    local output
    set +e
    if [ "$timeout_secs" -gt 0 ] 2>/dev/null; then
        output=$(timeout -s INT "$timeout_secs" strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null)
    else
        output=$(strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null)
    fi
    local status=$?
    set -e

    if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
        return "$status"
    fi

    printf "%s\n" "$output"
}

parse_syscall_total() {
    local output="$1"
    local total

    total=$(echo "$output" | grep "^100.00" | awk '{print $4}' || echo "0")
    if [ "$total" = "0" ] || [ -z "$total" ]; then
        total=$(echo "$output" | tail -1 | awk '{print $4}' || echo "0")
    fi

    printf "%s\n" "$total"
}

print_top_syscalls() {
    local label="$1"
    local timeout_secs="$2"
    shift
    shift
    echo "--- Top Syscalls ($label) ---"
    run_strace_summary "$timeout_secs" "$@" | \
        grep -E '^\s+[0-9]' | \
        sort -k4 -rn | \
        head -10 | \
        awk '{printf "  %-16s %s\n", $NF, $4}'
    echo ""
}

echo "--- Syscall Count (--version) ---"
set +e
claw_version_output=$(run_strace_summary 0 "$CLAW_BIN" --version)
claw_version_status=$?
claude_version_output=$(run_strace_summary 0 "$CLAUDE_BIN" --version)
claude_version_status=$?
set -e

claw_count=$(parse_syscall_total "$claw_version_output")
claude_count=$(parse_syscall_total "$claude_version_output")

if [ -z "$claw_count" ] || [ -z "$claude_count" ] || [ "$claw_count" = "0" ] || [ "$claude_count" = "0" ]; then
    echo "ERROR: failed to parse --version syscall totals" >&2
    exit 1
fi

if [ "$claw_count" -gt 0 ] 2>/dev/null; then
    ratio=$(echo "scale=1; $claude_count / $claw_count" | bc)
    ratio_fmt="${ratio}x"
else
    ratio_fmt="N/A"
fi

printf "%-12s %s syscalls\n" "Claw" "$claw_count"
printf "%-12s %s syscalls  (%s)\n" "Claude" "$claude_count" "$ratio_fmt"
echo ""

print_top_syscalls "Claw --version" 0 "$CLAW_BIN" --version
print_top_syscalls "Claude --version" 0 "$CLAUDE_BIN" --version

echo "--- Syscall Count (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    set +e
    claw_api_output=$(run_strace_summary "${API_CALL_TIMEOUT:-45}" "$CLAW_BIN" -p 'say hi' --max-turns 1)
    claw_api_status=$?
    claude_api_output=$(run_strace_summary "${API_CALL_TIMEOUT:-45}" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)
    claude_api_status=$?
    set -e

    claw_api=$(parse_syscall_total "$claw_api_output")
    claude_api=$(parse_syscall_total "$claude_api_output")

    if [ -z "$claw_api" ] || [ -z "$claude_api" ] || [ "$claw_api" = "0" ] || [ "$claude_api" = "0" ]; then
        echo "ERROR: failed to parse API-call syscall totals" >&2
        exit 1
    fi

    if [ "$claw_api" -gt 0 ] 2>/dev/null; then
        ratio_api=$(echo "scale=1; $claude_api / $claw_api" | bc)
        ratio_api_fmt="${ratio_api}x"
    else
        ratio_api_fmt="N/A"
    fi

    printf "%-12s %s syscalls\n" "Claw" "$claw_api"
    printf "%-12s %s syscalls  (%s)\n" "Claude" "$claude_api" "$ratio_api_fmt"

    if [ "$claw_api_status" -eq 124 ] || [ "$claude_api_status" -eq 124 ]; then
        echo "Note: API-path syscall profiling was interrupted at ${API_CALL_TIMEOUT:-45}s to cap lingering helper activity."
    fi
)
