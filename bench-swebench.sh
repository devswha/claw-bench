#!/usr/bin/env bash
# Benchmark: SWE-bench Verified — real-world GitHub issue resolution
# WARNING: This benchmark takes hours to run and costs API tokens ($50-200+)
set -euo pipefail
source "$(dirname "$0")/env.sh"

DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$DIR/swebench/results/$(date '+%Y%m%d-%H%M%S')"

echo "=== SWE-bench Verified Benchmark ==="
echo "Tasks: ${SWEBENCH_TASKS:-500} | Timeout: ${SWEBENCH_TIMEOUT:-300}s per task"
echo "Results: $RESULTS_DIR"
echo ""

# --- Prerequisites ---
command -v docker &>/dev/null || { echo "docker required: https://docs.docker.com/get-docker/"; exit 1; }
command -v python3 &>/dev/null || { echo "python3 required"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

if [ "${API_KEY:-REPLACE_ME_WITH_YOUR_API_KEY}" = "REPLACE_ME_WITH_YOUR_API_KEY" ]; then
    echo "ERROR: Set API_KEY in env.sh (required for SWE-bench)" >&2
    exit 1
fi

# --- Setup SWE-bench harness ---
SWEBENCH_DIR="$DIR/.swebench-harness"
if [ ! -d "$SWEBENCH_DIR" ]; then
    echo "Installing SWE-bench evaluation harness..."
    python3 -m venv "$SWEBENCH_DIR/venv"
    source "$SWEBENCH_DIR/venv/bin/activate"
    pip install swe-bench 2>&1 | tail -1
    deactivate
else
    echo "SWE-bench harness found at $SWEBENCH_DIR"
fi

mkdir -p "$RESULTS_DIR"

# --- Run agent on SWE-bench tasks ---
run_swebench() {
    local label="$1"
    local bin="$2"
    local output_file="$RESULTS_DIR/${label,,}-predictions.jsonl"

    echo "--- Running $label on SWE-bench Verified ---"
    echo "Output: $output_file"

    source "$SWEBENCH_DIR/venv/bin/activate"

    (
        export ANTHROPIC_BASE_URL="$API_BASE_URL"
        export ANTHROPIC_API_KEY="$API_KEY"

        python3 -c "
import json, subprocess, sys
from datasets import load_dataset

ds = load_dataset('princeton-nlp/SWE-bench_Verified', split='test')
max_tasks = int('${SWEBENCH_TASKS:-500}')
timeout = int('${SWEBENCH_TIMEOUT:-300}')

results = []
total = min(len(ds), max_tasks)

for i, item in enumerate(ds):
    if i >= max_tasks:
        break
    instance_id = item['instance_id']
    issue_text = item['problem_statement']
    repo = item['repo']
    base_commit = item['base_commit']

    print(f'[{i+1}/{total}] {instance_id}', flush=True)

    try:
        result = subprocess.run(
            ['$bin', '-p', f'Fix this issue in {repo} (commit {base_commit}):\n\n{issue_text}\n\nOutput ONLY the unified diff patch.', '--max-turns', '10'],
            capture_output=True, text=True, timeout=timeout,
            env={**dict(__import__('os').environ)}
        )
        patch = result.stdout.strip()
    except subprocess.TimeoutExpired:
        patch = ''
        print(f'  TIMEOUT', flush=True)
    except Exception as e:
        patch = ''
        print(f'  ERROR: {e}', flush=True)

    results.append({
        'instance_id': instance_id,
        'model_name_or_path': '$label',
        'model_patch': patch
    })

with open('$output_file', 'w') as f:
    for r in results:
        f.write(json.dumps(r) + '\n')

print(f'Predictions saved: {len(results)} tasks')
"
    )

    deactivate
    echo ""
}

# --- Evaluate predictions ---
evaluate_predictions() {
    local label="$1"
    local predictions="$RESULTS_DIR/${label,,}-predictions.jsonl"
    local eval_output="$RESULTS_DIR/${label,,}-evaluation.json"

    echo "--- Evaluating $label predictions ---"

    source "$SWEBENCH_DIR/venv/bin/activate"

    python3 -m swebench.harness.run_evaluation \
        --predictions_path "$predictions" \
        --swe_bench_tasks princeton-nlp/SWE-bench_Verified \
        --log_dir "$RESULTS_DIR/${label,,}-logs" \
        --testbed /tmp/swebench-testbed \
        --timeout "${SWEBENCH_TIMEOUT:-300}" \
        2>&1 | tee "$RESULTS_DIR/${label,,}-eval.log" | tail -5

    deactivate
    echo ""
}

# --- Run benchmarks ---
run_swebench "Claw" "$CLAW_BIN"
run_swebench "Claude" "$CLAUDE_BIN"

# --- Evaluate ---
evaluate_predictions "Claw"
evaluate_predictions "Claude"

# --- Report ---
echo "=== SWE-bench Verified Results ==="
echo ""

source "$SWEBENCH_DIR/venv/bin/activate"

python3 -c "
import json, glob

for label in ['Claw', 'Claude']:
    log_dir = '$RESULTS_DIR/' + label.lower() + '-logs'
    logs = glob.glob(f'{log_dir}/**/*.eval.log', recursive=True)

    passed = sum(1 for l in logs if 'PASSED' in open(l).read())
    total = len(logs) if logs else int('${SWEBENCH_TASKS:-500}')
    pct = (passed / total * 100) if total > 0 else 0

    print(f'{label:12s} {passed}/{total} resolved  ({pct:.1f}%)')

print()
"

deactivate

echo "Full results: $RESULTS_DIR"
