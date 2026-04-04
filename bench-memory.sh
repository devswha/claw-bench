#!/usr/bin/env bash
# Benchmark: Idle memory usage (RSS)
set -euo pipefail
source "$(dirname "$0")/env.sh"

JSON_OUTPUT=""

usage() {
    echo "Usage: $0 [--json [OUTPUT_PATH]]" >&2
}

default_json_output() {
    local dir
    dir="$(cd "$(dirname "$0")" && pwd)"
    printf "%s/results/tier0/idle-memory-%s.json\n" "$dir" "$(date '+%Y%m%d-%H%M%S')"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --json)
                if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
                    JSON_OUTPUT="$2"
                    shift 2
                else
                    JSON_OUTPUT="$(default_json_output)"
                    shift
                fi
                ;;
            --json=*)
                JSON_OUTPUT="${1#--json=}"
                shift
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "${JSON_OUTPUT}" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$JSON_OUTPUT")"
}

write_json_result() {
    [ -n "$JSON_OUTPUT" ] || return 0

    python3 - "$JSON_OUTPUT" "$generated_at" "$CLAW_BIN" "$claw_rss_kb" "$claw_rss_mb" "$claw_timed_out" "$CLAUDE_BIN" "$claude_rss_kb" "$claude_rss_mb" "$claude_timed_out" "$has_codex" "${CODEX_BIN:-}" "${codex_rss_kb:-}" "${codex_rss_mb:-}" "${codex_timed_out:-}" <<'PY'
import json
import sys
from pathlib import Path

(
    output_path,
    generated_at,
    claw_path,
    claw_rss_kb,
    claw_rss_mb,
    claw_timed_out,
    claude_path,
    claude_rss_kb,
    claude_rss_mb,
    claude_timed_out,
    has_codex,
    codex_path,
    codex_rss_kb,
    codex_rss_mb,
    codex_timed_out,
) = sys.argv[1:]


def as_number(value: str):
    return int(value) if value.isdigit() else None


results = {
    "claw": {
        "path": claw_path,
        "rss_kb": as_number(claw_rss_kb),
        "rss_mb": float(claw_rss_mb),
        "timed_out": claw_timed_out == "true",
    },
    "claude": {
        "path": claude_path,
        "rss_kb": as_number(claude_rss_kb),
        "rss_mb": float(claude_rss_mb),
        "timed_out": claude_timed_out == "true",
    },
}

if has_codex == "true":
    results["codex"] = {
        "path": codex_path,
        "rss_kb": as_number(codex_rss_kb),
        "rss_mb": float(codex_rss_mb),
        "timed_out": codex_timed_out == "true",
    }

payload = {
    "schema_version": 1,
    "suite": "tier0",
    "benchmark": "idle_memory",
    "generated_at": generated_at,
    "command_mode": "--version",
    "results": results,
}

path = Path(output_path)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

parse_args "$@"

command -v bc &>/dev/null || { echo "bc required: sudo apt install bc"; exit 1; }

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

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

    LAST_RSS_KB="$rss"
    LAST_RSS_MB="$(echo "scale=1; $rss/1024" | bc)"
    LAST_TIMED_OUT=false
    if [ "$status" -eq 124 ]; then
        LAST_TIMED_OUT=true
    fi

    printf "%-12s %s KB  (%s MB)%s\n" "$label" "$LAST_RSS_KB" "$LAST_RSS_MB" "$note"
}

echo "--- --version (minimal load) ---"
measure_rss "Claw" "$CLAW_BIN" --version
claw_rss_kb="$LAST_RSS_KB"
claw_rss_mb="$LAST_RSS_MB"
claw_timed_out="$LAST_TIMED_OUT"
measure_rss "Claude" "$CLAUDE_BIN" --version
claude_rss_kb="$LAST_RSS_KB"
claude_rss_mb="$LAST_RSS_MB"
claude_timed_out="$LAST_TIMED_OUT"
if [ "$has_codex" = true ]; then
    measure_rss "Codex" "$CODEX_BIN" --version
    codex_rss_kb="$LAST_RSS_KB"
    codex_rss_mb="$LAST_RSS_MB"
    codex_timed_out="$LAST_TIMED_OUT"
fi

write_json_result
