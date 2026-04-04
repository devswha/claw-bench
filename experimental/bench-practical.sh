#!/usr/bin/env bash
# Benchmark: Tier 1 practical coding task preview
# WARNING: Manual / experimental. Runs one real coding task through configured CLIs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/env.sh"

TASK_ID=""
JSON_OUTPUT=""
RUN_ID="tier1-$(date -u '+%Y%m%dT%H%M%SZ')"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PRACTICAL_TIMEOUT=180

usage() {
    cat <<'EOF' >&2
Usage: ./experimental/bench-practical.sh [--task TASK_ID] [--json [OUTPUT_PATH]]

Options:
  --task TASK_ID        Run a specific enabled task from tasks/manifest.json
  --json [OUTPUT_PATH]  Write JSON results (default: results/tier1/practical-<timestamp>.json)
  -h, --help            Show this help
EOF
}

default_json_output() {
    printf "%s/results/tier1/practical-%s.json\n" "$ROOT_DIR" "$(date -u '+%Y%m%dT%H%M%SZ')"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --task)
                [ "$#" -ge 2 ] || { echo "ERROR: --task requires a value" >&2; usage; exit 1; }
                TASK_ID="$2"
                shift 2
                ;;
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
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [ -n "$JSON_OUTPUT" ]; then
        mkdir -p "$(dirname "$JSON_OUTPUT")"
    fi
}

api_key_configured() {
    [ -n "${API_KEY:-}" ] && [ "${API_KEY:-}" != "REPLACE_ME_WITH_YOUR_API_KEY" ]
}

load_task_selection() {
    python3 - "$ROOT_DIR/tasks/manifest.json" "$TASK_ID" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
requested = sys.argv[2]
manifest = json.loads(manifest_path.read_text())

tasks = [task for task in manifest.get("tasks", []) if task.get("enabled")]
if requested:
    tasks = [task for task in tasks if task.get("id") == requested]

if not tasks:
    raise SystemExit("NO_ENABLED_TASK")

task = tasks[0]
print(task["id"])
print(task["name"])
print(task["dir"])
PY
}

load_task_metadata() {
    local task_dir="$1"
    python3 - "$task_dir/task.json" <<'PY'
import json
import sys
from pathlib import Path

task = json.loads(Path(sys.argv[1]).read_text())
print(task["id"])
print(task["prompt_file"])
print(task["workspace_dir"])
print(task["tests_dir"])
print(task["verify_command"])
print(task["max_turns"])
print(task["language"])
PY
}

copy_task_workspace() {
    local task_dir="$1"
    local workspace_dir="$2"
    local tests_dir="$3"
    local dest="$4"

    mkdir -p "$dest"
    cp -R "$task_dir/$workspace_dir/." "$dest/"
    cp -R "$task_dir/$tests_dir" "$dest/tests"
}

count_diff_lines() {
    local src="$1"
    local dest="$2"
    python3 - "$src" "$dest" <<'PY'
import difflib
import pathlib
import sys

src_root = pathlib.Path(sys.argv[1])
dst_root = pathlib.Path(sys.argv[2])
total = 0

for src_path in sorted(p for p in src_root.rglob("*") if p.is_file()):
    if "__pycache__" in src_path.parts or src_path.suffix == ".pyc":
        continue
    rel = src_path.relative_to(src_root)
    dst_path = dst_root / rel
    before = src_path.read_text(encoding="utf-8")
    after = dst_path.read_text(encoding="utf-8") if dst_path.exists() else ""
    diff = difflib.unified_diff(
        before.splitlines(),
        after.splitlines(),
        lineterm="",
    )
    for line in diff:
        if line.startswith(("+++", "---", "@@")):
            continue
        if line.startswith("+") or line.startswith("-"):
            total += 1

print(total)
PY
}

run_claw() {
    local workdir="$1"
    local prompt="$2"

    (
        cd "$workdir"
        export ANTHROPIC_BASE_URL="$API_BASE_URL"
        export ANTHROPIC_API_KEY="$API_KEY"
        timeout "$PRACTICAL_TIMEOUT" "$CLAW_BIN" --dangerously-skip-permissions --output-format text prompt "$prompt"
    )
}

run_claude() {
    local workdir="$1"
    local prompt="$2"

    (
        cd "$workdir"
        export ANTHROPIC_BASE_URL="$API_BASE_URL"
        export ANTHROPIC_API_KEY="$API_KEY"
        timeout "$PRACTICAL_TIMEOUT" "$CLAUDE_BIN" --dangerously-skip-permissions -p "$prompt"
    )
}

run_codex() {
    local workdir="$1"
    local prompt="$2"

    timeout "$PRACTICAL_TIMEOUT" "$CODEX_BIN" exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$workdir" "$prompt"
}

run_verification() {
    local workdir="$1"
    local verify_command="$2"

    (
        cd "$workdir"
        bash -lc "$verify_command"
    )
}

record_result() {
    local tool="$1"
    local status="$2"
    local duration_ms="$3"
    local verification_command="$4"
    local diff_lines="$5"
    local skip_reason="${6:-}"
    local agent_exit_code="${7:-}"
    local verify_exit_code="${8:-}"

    python3 - "$RESULTS_FILE" "$tool" "$TASK_JSON_ID" "$status" "$duration_ms" "$MAX_TURNS" "$verification_command" "$diff_lines" "$skip_reason" "$agent_exit_code" "$verify_exit_code" <<'PY'
import json
import sys
from pathlib import Path

(
    path,
    tool,
    task_id,
    status,
    duration_ms,
    max_turns,
    verification_command,
    diff_lines,
    skip_reason,
    agent_exit_code,
    verify_exit_code,
) = sys.argv[1:]

payload = json.loads(Path(path).read_text())
payload["results"][tool] = {
    "tool": tool,
    "task_id": task_id,
    "status": status,
    "duration_ms": int(duration_ms),
    "max_turns": int(max_turns),
    "verification_command": verification_command,
    "diff_lines": int(diff_lines),
}
if skip_reason:
    payload["results"][tool]["skip_reason"] = skip_reason
if agent_exit_code:
    payload["results"][tool]["agent_exit_code"] = int(agent_exit_code)
if verify_exit_code:
    payload["results"][tool]["verification_exit_code"] = int(verify_exit_code)

Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

initialize_results_file() {
    RESULTS_FILE="$1"
    python3 - "$RESULTS_FILE" "$GENERATED_AT" "$RUN_ID" "$ROOT_DIR" "$TASK_JSON_ID" "$TASK_NAME" "$VERIFY_COMMAND" "$MAX_TURNS" "$CLAW_BIN" "$CLAUDE_BIN" "${CODEX_BIN:-}" <<'PY'
import json
import os
import platform
import socket
import subprocess
import sys
from pathlib import Path

(
    results_path,
    generated_at,
    run_id,
    root_dir,
    task_id,
    task_name,
    verify_command,
    max_turns,
    claw_bin,
    claude_bin,
    codex_bin,
) = sys.argv[1:]

def version(binary: str) -> str:
    if not binary or not os.access(binary, os.X_OK):
        return ""
    proc = subprocess.run([binary, "--version"], capture_output=True, text=True, check=False)
    for line in (proc.stdout + "\n" + proc.stderr).splitlines():
        line = line.strip()
        if line:
            return line
    return ""

tools = {}
for name, binary in [("claw", claw_bin), ("claude", claude_bin), ("codex", codex_bin)]:
    if binary:
        tools[name] = {
            "binary": binary,
            "resolved_path": os.path.realpath(binary) if os.path.exists(binary) else binary,
            "version": version(binary),
        }

payload = {
    "schema_version": "1.0",
    "suite": "tier1",
    "tier": 1,
    "benchmark": "practical_tasks",
    "script": "experimental/bench-practical.sh",
    "run_id": run_id,
    "generated_at": generated_at,
    "environment": {
        "os": platform.system(),
        "kernel": platform.release(),
        "hostname": socket.gethostname(),
    },
    "tools": tools,
    "task": {
        "id": task_id,
        "name": task_name,
        "verification_command": verify_command,
        "max_turns": int(max_turns),
    },
    "results": {},
}

Path(results_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

parse_args "$@"

TASK_SELECTION="$(load_task_selection)"
TASK_MANIFEST_ID="$(printf '%s\n' "$TASK_SELECTION" | sed -n '1p')"
TASK_NAME="$(printf '%s\n' "$TASK_SELECTION" | sed -n '2p')"
TASK_DIR_REL="$(printf '%s\n' "$TASK_SELECTION" | sed -n '3p')"
TASK_DIR="$ROOT_DIR/$TASK_DIR_REL"

TASK_METADATA="$(load_task_metadata "$TASK_DIR")"
TASK_JSON_ID="$(printf '%s\n' "$TASK_METADATA" | sed -n '1p')"
PROMPT_FILE_REL="$(printf '%s\n' "$TASK_METADATA" | sed -n '2p')"
WORKSPACE_DIR_REL="$(printf '%s\n' "$TASK_METADATA" | sed -n '3p')"
TESTS_DIR_REL="$(printf '%s\n' "$TASK_METADATA" | sed -n '4p')"
VERIFY_COMMAND="$(printf '%s\n' "$TASK_METADATA" | sed -n '5p')"
MAX_TURNS="$(printf '%s\n' "$TASK_METADATA" | sed -n '6p')"
LANGUAGE="$(printf '%s\n' "$TASK_METADATA" | sed -n '7p')"

if [ "$TASK_MANIFEST_ID" != "$TASK_JSON_ID" ]; then
    echo "ERROR: manifest/task metadata mismatch: $TASK_MANIFEST_ID != $TASK_JSON_ID" >&2
    exit 1
fi

PROMPT_TEXT="$(cat "$TASK_DIR/$PROMPT_FILE_REL")"

if [ -z "$JSON_OUTPUT" ]; then
    JSON_OUTPUT="$(default_json_output)"
    mkdir -p "$(dirname "$JSON_OUTPUT")"
fi

RESULTS_FILE="$JSON_OUTPUT"
initialize_results_file "$RESULTS_FILE"

echo "=== Tier 1 Practical Benchmark (manual / experimental) ==="
echo "Task: $TASK_JSON_ID ($TASK_NAME)"
echo "Language: $LANGUAGE | Max turns: $MAX_TURNS"
echo "JSON output: $RESULTS_FILE"
echo ""

ORIGINAL_WORKSPACE="$TASK_DIR/$WORKSPACE_DIR_REL"

run_tool_flow() {
    local tool="$1"
    local runner="$2"
    local skip_reason="$3"

    if [ -n "$skip_reason" ]; then
        echo "Skipping $tool: $skip_reason"
        record_result "$tool" "skipped" 0 "$VERIFY_COMMAND" 0 "$skip_reason"
        echo ""
        return 0
    fi

    local temp_root
    temp_root="$(mktemp -d)"
    copy_task_workspace "$TASK_DIR" "$WORKSPACE_DIR_REL" "$TESTS_DIR_REL" "$temp_root"

    local start_ms end_ms duration_ms agent_status verify_status diff_lines status
    start_ms="$(date +%s%3N)"
    set +e
    "$runner" "$temp_root" "$PROMPT_TEXT" >/tmp/bench-practical-"$tool".out 2>/tmp/bench-practical-"$tool".err
    agent_status=$?
    run_verification "$temp_root" "$VERIFY_COMMAND" >/tmp/bench-practical-"$tool"-verify.out 2>/tmp/bench-practical-"$tool"-verify.err
    verify_status=$?
    set -e
    end_ms="$(date +%s%3N)"
    duration_ms="$((end_ms - start_ms))"
    diff_lines="$(count_diff_lines "$ORIGINAL_WORKSPACE" "$temp_root")"

    if [ "$verify_status" -eq 0 ]; then
        status="passed"
    else
        status="failed"
    fi

    echo "--- $tool ---"
    echo "status: $status"
    echo "duration_ms: $duration_ms"
    echo "diff_lines: $diff_lines"
    echo "agent_exit_code: $agent_status"
    echo "verification_exit_code: $verify_status"
    echo ""

    record_result "$tool" "$status" "$duration_ms" "$VERIFY_COMMAND" "$diff_lines" "" "$agent_status" "$verify_status"
}

claw_skip=""
if [ ! -x "$CLAW_BIN" ]; then
    claw_skip="claw binary missing"
elif ! api_key_configured; then
    claw_skip="api key missing"
fi

claude_skip=""
if [ ! -x "$CLAUDE_BIN" ]; then
    claude_skip="claude binary missing"
elif ! api_key_configured; then
    claude_skip="api key missing"
fi

codex_skip=""
if [ -z "${CODEX_BIN:-}" ] || [ ! -x "${CODEX_BIN:-}" ]; then
    codex_skip="codex binary missing"
fi

run_tool_flow "claw" run_claw "$claw_skip"
run_tool_flow "claude" run_claude "$claude_skip"
run_tool_flow "codex" run_codex "$codex_skip"

echo "Tier 1 JSON results written to $RESULTS_FILE"
