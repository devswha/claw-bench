#!/usr/bin/env bash
# Benchmark: Cold start time (--version)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/env.sh"

usage() {
    cat <<'EOF'
Usage: ./bench-startup.sh [--json [OUTPUT_PATH]]

Options:
  --json    Write machine-readable Tier 0 results to results/tier0/<timestamp>.json
  -h, --help
EOF
}

default_json_output() {
    printf "%s/results/tier0/startup-time-%s.json\n" "$DIR" "$(date -u '+%Y%m%dT%H%M%SZ')"
}

json_output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
                json_output="$2"
                shift 2
            else
                json_output="$(default_json_output)"
                shift
            fi
            ;;
        --json=*)
            json_output="${1#--json=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

echo "=== Startup Time Benchmark ==="
echo ""

if ! command -v hyperfine &>/dev/null; then
    echo "hyperfine not found. Install: sudo apt install hyperfine"
    exit 1
fi

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

echo "Comparing: --version cold start"
echo "  Claw:   $CLAW_BIN"
echo "  Claude: $CLAUDE_BIN"
if [ "$has_codex" = true ]; then
    echo "  Codex:  $CODEX_BIN"
fi
echo ""

commands=(
    "$CLAW_BIN --version"
    "$CLAUDE_BIN --version"
)

if [ "$has_codex" = true ]; then
    commands+=("$CODEX_BIN --version")
fi

hyperfine_export=""
cleanup() {
    if [ -n "${hyperfine_export:-}" ] && [ -f "$hyperfine_export" ]; then
        rm -f "$hyperfine_export"
    fi
}
trap cleanup EXIT

hyperfine_args=(
    --warmup "$HYPERFINE_WARMUP"
    --runs "$HYPERFINE_RUNS"
    --export-markdown /dev/stdout
)

if [ -n "$json_output" ]; then
    mkdir -p "$(dirname "$json_output")"
    hyperfine_export="$(mktemp)"
    hyperfine_args+=(--export-json "$hyperfine_export")
fi

hyperfine "${hyperfine_args[@]}" "${commands[@]}"

if [ -n "$json_output" ]; then
    python3 - "$hyperfine_export" "$json_output" "$CLAW_BIN" "$CLAUDE_BIN" "${CODEX_BIN:-}" <<'PY'
import json
import os
import pathlib
import platform
import socket
import subprocess
import sys
from datetime import datetime, timezone

raw_path, output_path, claw_bin, claude_bin, codex_bin = sys.argv[1:6]

with open(raw_path, "r", encoding="utf-8") as fh:
    raw = json.load(fh)

tool_bins = {
    "claw": claw_bin,
    "claude": claude_bin,
}
if codex_bin and os.access(codex_bin, os.X_OK):
    tool_bins["codex"] = codex_bin


def detect_tool(command: str) -> str:
    for tool, binary in tool_bins.items():
        if command.startswith(binary):
            return tool
    return "unknown"


def tool_version(binary: str) -> str:
    try:
        proc = subprocess.run(
            [binary, "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return ""

    combined = [line.strip() for line in (proc.stdout + "\n" + proc.stderr).splitlines() if line.strip()]
    return combined[0] if combined else ""


payload = {
    "schema_version": "1.0",
    "timestamp": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "tier": 0,
    "benchmark": "startup",
    "script": "bench-startup.sh",
    "environment": {
        "os": platform.system(),
        "kernel": platform.release(),
        "hostname": socket.gethostname(),
    },
    "tools": {
        tool: {
            "binary": binary,
            "version": tool_version(binary),
        }
        for tool, binary in tool_bins.items()
    },
    "results": [],
}

for result in raw.get("results", []):
    payload["results"].append(
        {
            "tool": detect_tool(result.get("command", "")),
            "command": result.get("command"),
            "mean_seconds": result.get("mean"),
            "stddev_seconds": result.get("stddev"),
            "median_seconds": result.get("median"),
            "min_seconds": result.get("min"),
            "max_seconds": result.get("max"),
            "times_seconds": result.get("times", []),
        }
    )

pathlib.Path(output_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

    echo ""
    echo "JSON results written to $json_output"
fi
