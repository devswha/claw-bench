#!/usr/bin/env bash
# Benchmark: Binary / install size
set -euo pipefail
source "$(dirname "$0")/env.sh"

JSON_OUTPUT=""

usage() {
    echo "Usage: $0 [--json [OUTPUT_PATH]]" >&2
}

default_json_output() {
    local dir
    dir="$(cd "$(dirname "$0")" && pwd)"
    printf "%s/results/tier0/install-size-%s.json\n" "$dir" "$(date -u '+%Y%m%dT%H%M%SZ')"
}

RUN_ID="${TIER0_RUN_ID:-tier0-$(date -u '+%Y%m%dT%H%M%SZ')}"

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

find_parent_with_file() {
    local dir="$1"
    local file="$2"

    while [ "$dir" != "/" ]; do
        if [ -f "$dir/$file" ]; then
            printf "%s\n" "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

bytes_for_path() {
    local path="$1"
    du -sb "$path" 2>/dev/null | cut -f1
}

write_json_result() {
    [ -n "$JSON_OUTPUT" ] || return 0

    python3 - "$JSON_OUTPUT" "$generated_at" "$RUN_ID" "$CLAW_BIN" "$claw_binary_size" "$claw_binary_bytes" "$claw_install_size" "$claw_install_bytes" "$claw_install_note" "$claw_deps" "$CLAUDE_BIN" "$claude_real" "$claude_binary_size" "$claude_binary_bytes" "$claude_install_size" "$claude_install_bytes" "$claude_install_note" "$claude_deps" "$has_codex" "${CODEX_BIN:-}" "${codex_real:-}" "${codex_binary_size:-}" "${codex_binary_bytes:-}" "${codex_install_size:-}" "${codex_install_bytes:-}" "${codex_install_note:-}" "${codex_deps:-}" <<'PY'
import json
import os
import platform
import socket
import subprocess
import sys
from pathlib import Path

(
    output_path,
    generated_at,
    run_id,
    claw_path,
    claw_binary_size,
    claw_binary_bytes,
    claw_install_size,
    claw_install_bytes,
    claw_install_note,
    claw_deps,
    claude_path,
    claude_real,
    claude_binary_size,
    claude_binary_bytes,
    claude_install_size,
    claude_install_bytes,
    claude_install_note,
    claude_deps,
    has_codex,
    codex_path,
    codex_real,
    codex_binary_size,
    codex_binary_bytes,
    codex_install_size,
    codex_install_bytes,
    codex_install_note,
    codex_deps,
) = sys.argv[1:]


def normalize_count(value: str):
    return int(value) if value.isdigit() else None


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


tools = {
    "claw": {
        "binary": claw_path,
        "resolved_path": os.path.realpath(claw_path),
        "version": tool_version(claw_path),
    },
    "claude": {
        "binary": claude_path,
        "resolved_path": claude_real,
        "version": tool_version(claude_path),
    },
}

results = {
    "claw": {
        "binary_bytes": int(claw_binary_bytes),
        "install_bytes": int(claw_install_bytes),
        "install_scope": claw_install_note,
        "binary_size_human": claw_binary_size,
        "install_size_human": claw_install_size,
        "dependency_count": normalize_count(claw_deps),
        "dependency_count_display": claw_deps,
        "dependency_kind": "cargo_crates",
    },
    "claude": {
        "binary_bytes": int(claude_binary_bytes),
        "install_bytes": int(claude_install_bytes),
        "install_scope": claude_install_note,
        "binary_size_human": claude_binary_size,
        "install_size_human": claude_install_size,
        "dependency_count": normalize_count(claude_deps),
        "dependency_count_display": claude_deps,
        "dependency_kind": "npm_packages",
    },
}

if has_codex == "true":
    tools["codex"] = {
        "binary": codex_path,
        "resolved_path": codex_real,
        "version": tool_version(codex_path),
    }
    results["codex"] = {
        "binary_bytes": int(codex_binary_bytes),
        "install_bytes": int(codex_install_bytes),
        "install_scope": codex_install_note,
        "binary_size_human": codex_binary_size,
        "install_size_human": codex_install_size,
        "dependency_count": normalize_count(codex_deps),
        "dependency_count_display": codex_deps,
        "dependency_kind": "npm_packages",
    }

payload = {
    "schema_version": "1.0",
    "suite": "tier0",
    "tier": 0,
    "benchmark": "install_size",
    "script": "bench-size.sh",
    "run_id": run_id,
    "generated_at": generated_at,
    "environment": {
        "os": platform.system(),
        "kernel": platform.release(),
        "hostname": socket.gethostname(),
    },
    "tools": tools,
    "results": results,
}

path = Path(output_path)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

parse_args "$@"

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "=== Install Size Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

echo "--- Binary size ---"
claw_binary_size="$(du -sh "$CLAW_BIN" | cut -f1)"
claw_binary_bytes="$(bytes_for_path "$CLAW_BIN")"
printf "%-12s %s\n" "Claw" "$claw_binary_size"

claude_real=$(readlink -f "$CLAUDE_BIN" 2>/dev/null || echo "$CLAUDE_BIN")
claude_binary_size="$(du -sh "$claude_real" | cut -f1)"
claude_binary_bytes="$(bytes_for_path "$claude_real")"
printf "%-12s %s\n" "Claude" "$claude_binary_size"
if [ "$has_codex" = true ]; then
    codex_real=$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")
    codex_binary_size="$(du -sh "$codex_real" | cut -f1)"
    codex_binary_bytes="$(bytes_for_path "$codex_real")"
    printf "%-12s %s\n" "Codex" "$codex_binary_size"
fi

echo ""
echo "--- Total install footprint ---"
claw_install_size="$claw_binary_size"
claw_install_bytes="$claw_binary_bytes"
claw_install_note="standalone binary"
printf "%-12s %s  (%s)\n" "Claw" "$claw_install_size" "$claw_install_note"

claude_dir=$(dirname "$claude_real")
if [ -d "$claude_dir/../lib" ]; then
    claude_install_size="$(du -sh "$claude_dir/.." | cut -f1)"
    claude_install_bytes="$(bytes_for_path "$claude_dir/..")"
    claude_install_note="bin + lib"
elif [ -d "$claude_dir/../node_modules" ]; then
    claude_install_size="$(du -sh "$claude_dir/.." | cut -f1)"
    claude_install_bytes="$(bytes_for_path "$claude_dir/..")"
    claude_install_note="with node_modules"
else
    claude_install_size="$claude_binary_size"
    claude_install_bytes="$claude_binary_bytes"
    claude_install_note="binary only, node_modules elsewhere"
fi
printf "%-12s %s  (%s)\n" "Claude" "$claude_install_size" "$claude_install_note"

if [ "$has_codex" = true ]; then
    codex_pkg_root=$(cd "$(dirname "$codex_real")/.." && pwd)
    codex_install_size="$(du -sh "$codex_pkg_root" | cut -f1)"
    codex_install_bytes="$(bytes_for_path "$codex_pkg_root")"
    codex_install_note="global npm package"
    printf "%-12s %s  (%s)\n" "Codex" "$codex_install_size" "$codex_install_note"
fi

echo ""
echo "--- Dependency count ---"
claw_workspace=$(find_parent_with_file "$(dirname "$CLAW_BIN")" Cargo.toml || true)
if [ -n "${claw_workspace:-}" ]; then
    claw_deps=$(cd "$claw_workspace" && cargo metadata --format-version 1 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['packages']))" 2>/dev/null || echo "N/A")
else
    claw_deps="N/A"
fi
printf "%-12s %s Cargo crates\n" "Claw" "$claw_deps"

claude_npm_root="$claude_dir/.."
if [ -d "$claude_npm_root/node_modules" ]; then
    claude_deps=$(find "$claude_npm_root/node_modules" -maxdepth 1 -type d | wc -l)
    printf "%-12s %s npm packages\n" "Claude" "$claude_deps"
else
    claude_deps="N/A"
    printf "%-12s %s\n" "Claude" "N/A (node_modules not found)"
fi

if [ "$has_codex" = true ]; then
    if [ -d "$codex_pkg_root/node_modules" ]; then
        codex_deps=$(find "$codex_pkg_root/node_modules" -maxdepth 1 -type d | wc -l)
        printf "%-12s %s npm packages\n" "Codex" "$codex_deps"
    else
        codex_deps="N/A"
        printf "%-12s %s\n" "Codex" "N/A (node_modules not found)"
    fi
fi

write_json_result
