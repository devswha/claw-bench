#!/usr/bin/env bash
# Benchmark: Idle memory usage (RSS)
set -euo pipefail
source "$(dirname "$0")/env.sh"

command -v bc &>/dev/null || { echo "bc required: sudo apt install bc"; exit 1; }

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

echo "=== Idle Memory Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

measure_rss() {
    local label="$1"
    shift
    local output status note
    local rss

    set +e
    output=$(/usr/bin/time -v "$@" 2>&1 1>/dev/null)
    status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
        output=$(/usr/bin/time -v "$@" 2>&1 1>/dev/null)
        status=$?
    fi
    set -e

    rss=$(echo "$output" | grep "Maximum resident" | awk '{print $NF}')
    note=""
    if [ "$status" -eq 124 ]; then
        note="  [timeout]"
    elif [ "$status" -ne 0 ]; then
        echo "ERROR: $label benchmark command failed (exit $status)" >&2
        return "$status"
    fi

    printf "%-12s %s KB  (%s MB)%s\n" "$label" "$rss" "$(echo "scale=1; $rss/1024" | bc)" "$note"
}

echo "--- --version (minimal load) ---"
measure_rss "Claw" "$CLAW_BIN" --version
measure_rss "Claude" "$CLAUDE_BIN" --version
if [ "$has_codex" = true ]; then
    measure_rss "Codex" "$CODEX_BIN" --version
fi
