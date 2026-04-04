#!/usr/bin/env bash
# Run the stable runtime benchmark core
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR=""
RUN_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_ID="tier0-$RUN_TIMESTAMP"

usage() {
    echo "Usage: $0 [--json [OUTPUT_DIR]]" >&2
}

default_json_dir() {
    printf "%s/results/tier0/%s\n" "$DIR" "$RUN_TIMESTAMP"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --json)
                if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
                    JSON_DIR="$2"
                    shift 2
                else
                    JSON_DIR="$(default_json_dir)"
                    shift
                fi
                ;;
            --json=*)
                JSON_DIR="${1#--json=}"
                shift
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    if [ -n "$JSON_DIR" ]; then
        mkdir -p "$JSON_DIR"
    fi
}

supports_json() {
    local script="$1"
    grep -q -- "--json" "$DIR/$script"
}

run_benchmark() {
    local script="$1"
    shift

    "$DIR/$script" "$@"

    echo ""
    echo "----------------------------------------"
    echo ""
}

json_path_for_script() {
    local script="$1"

    case "$script" in
        bench-startup.sh)
            printf "%s/startup-time.json\n" "$JSON_DIR"
            ;;
        bench-size.sh)
            printf "%s/install-size.json\n" "$JSON_DIR"
            ;;
        bench-memory.sh)
            printf "%s/idle-memory.json\n" "$JSON_DIR"
            ;;
        *)
            return 1
            ;;
    esac
}

run_stable_script() {
    local script="$1"

    if [ -n "$JSON_DIR" ] && supports_json "$script"; then
        TIER0_RUN_ID="$RUN_ID" run_benchmark "$script" --json "$(json_path_for_script "$script")"
        return 0
    fi

    run_benchmark "$script"
}

write_manifest() {
    [ -n "$JSON_DIR" ] || return 0

    python3 - "$JSON_DIR" "$RUN_ID" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

json_dir = pathlib.Path(sys.argv[1])
run_id = sys.argv[2]
files = sorted(p.name for p in json_dir.glob("*.json") if p.name != "manifest.json")
benchmarks = {}
for name in files:
    if name == "startup-time.json":
        benchmarks["startup"] = name
    elif name == "install-size.json":
        benchmarks["install_size"] = name
    elif name == "idle-memory.json":
        benchmarks["idle_memory"] = name

payload = {
    "schema_version": "1.0",
    "suite": "tier0",
    "tier": 0,
    "script": "bench-all.sh",
    "run_id": run_id,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "benchmarks": benchmarks,
    "files": files,
}

(json_dir / "manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

parse_args "$@"

echo "========================================"
echo "  Claw Code Stable Runtime Benchmarks"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""
echo "Default suite:"
echo "  - startup"
echo "  - install size"
echo "  - idle memory"
echo ""
echo "Experimental scripts remain available for manual runs:"
echo "  bench-ttft.sh bench-session.sh bench-syscall.sh bench-cpu.sh"
echo "  bench-io.sh bench-threads.sh bench-gc.sh"
echo ""

for script in \
    bench-startup.sh \
    bench-size.sh \
    bench-memory.sh
do
    run_stable_script "$script"
done

write_manifest

echo "========================================"
echo "  Stable benchmark complete"
echo "========================================"

if [ -n "$JSON_DIR" ]; then
    echo "Tier 0 JSON results: $JSON_DIR"
fi
