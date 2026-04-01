#!/usr/bin/env bash
# Benchmark: SWE-bench Verified — real-world GitHub issue resolution (Claw Code only)
# Claude Code scores are referenced from Anthropic's published results.
# WARNING: This benchmark takes hours to run. Requires Docker for evaluation.
set -euo pipefail
source "$(dirname "$0")/env.sh"

DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$DIR/swebench/results/$(date '+%Y%m%d-%H%M%S')"

echo "=== SWE-bench Verified Benchmark (Claw Code) ==="
echo "Tasks: ${SWEBENCH_TASKS:-500} | Timeout: ${SWEBENCH_TIMEOUT:-600}s per task"
echo "Results: $RESULTS_DIR"
echo ""

# --- Prerequisites ---
command -v docker &>/dev/null || { echo "docker required: https://docs.docker.com/get-docker/"; exit 1; }
command -v python3 &>/dev/null || { echo "python3 required"; exit 1; }
command -v git &>/dev/null || { echo "git required"; exit 1; }

if [ ! -x "$CLAW_BIN" ]; then
    echo "ERROR: Claw binary not found or not executable: $CLAW_BIN" >&2
    exit 1
fi

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
    pip install swebench datasets 2>&1 | tail -1
    deactivate
else
    echo "SWE-bench harness found at $SWEBENCH_DIR"
fi

mkdir -p "$RESULTS_DIR"

# --- Run Claw on SWE-bench tasks ---
echo "--- Running Claw Code on SWE-bench Verified ---"
echo "Output: $RESULTS_DIR/claw-predictions.jsonl"

source "$SWEBENCH_DIR/venv/bin/activate"

(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    python3 -c "
import json, subprocess, sys, os, tempfile, shutil

from datasets import load_dataset

ds = load_dataset('princeton-nlp/SWE-bench_Verified', split='test')
max_tasks = int('${SWEBENCH_TASKS:-500}')
timeout = int('${SWEBENCH_TIMEOUT:-600}')
claw_bin = '$CLAW_BIN'

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

    # Clone repo at base commit into temp directory
    work_dir = tempfile.mkdtemp(prefix='swebench-')
    patch = ''

    try:
        # Full clone + checkout base commit
        subprocess.run(
            ['git', 'clone', f'https://github.com/{repo}.git', work_dir],
            capture_output=True, text=True, timeout=300
        )
        subprocess.run(
            ['git', 'checkout', base_commit],
            capture_output=True, text=True, cwd=work_dir, timeout=30
        )

        # Run Claw inside the repo directory — it edits files directly
        result = subprocess.run(
            [claw_bin, '--dangerously-skip-permissions', '-p',
             f'Fix this GitHub issue. Edit the files directly to resolve it.\n\n{issue_text}',
             '--max-turns', '10'],
            capture_output=True, text=True, timeout=timeout,
            cwd=work_dir,
            env={**dict(os.environ)}
        )

        # Extract patch via git diff
        diff_result = subprocess.run(
            ['git', 'diff'],
            capture_output=True, text=True, cwd=work_dir, timeout=30
        )
        patch = diff_result.stdout.strip()

        if patch:
            print(f'  patch: {len(patch)} bytes', flush=True)
        else:
            print(f'  no changes detected', flush=True)

    except subprocess.TimeoutExpired:
        print(f'  TIMEOUT', flush=True)
    except Exception as e:
        print(f'  ERROR: {e}', flush=True)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)

    results.append({
        'instance_id': instance_id,
        'model_name_or_path': 'Claw',
        'model_patch': patch
    })

output_file = '$RESULTS_DIR/claw-predictions.jsonl'
with open(output_file, 'w') as f:
    for r in results:
        f.write(json.dumps(r) + '\n')

non_empty = sum(1 for r in results if r['model_patch'])
print(f'Predictions saved: {len(results)} tasks ({non_empty} with patches)')
"
)

deactivate
echo ""

# --- Evaluate predictions ---
echo "--- Evaluating Claw predictions ---"

source "$SWEBENCH_DIR/venv/bin/activate"

RUN_ID="claw-$(date '+%Y%m%d%H%M%S')"

python3 -m swebench.harness.run_evaluation \
    --predictions_path "$RESULTS_DIR/claw-predictions.jsonl" \
    --dataset_name princeton-nlp/SWE-bench_Verified \
    --run_id "$RUN_ID" \
    --max_workers 2 \
    --timeout "${SWEBENCH_TIMEOUT:-600}" \
    --report_dir "$RESULTS_DIR/claw-reports" \
    2>&1 | tee "$RESULTS_DIR/claw-eval.log" | tail -10

deactivate
echo ""

# --- Report ---
echo "=== SWE-bench Verified Results ==="
echo ""

source "$SWEBENCH_DIR/venv/bin/activate"

python3 -c "
import json, glob, os

# Parse Claw results from report
report_dir = '$RESULTS_DIR/claw-reports'
report_files = glob.glob(os.path.join(report_dir, '*.json'))

resolved = 0
total = int('${SWEBENCH_TASKS:-500}')

if report_files:
    with open(sorted(report_files)[-1]) as f:
        report = json.load(f)
    resolved = len(report.get('resolved', []))
    total_submitted = report.get('submitted', total)
    if total_submitted:
        total = total_submitted

claw_pct = (resolved / total * 100) if total > 0 else 0

print(f'              Claw         Claude (ref)')
print(f'              ----         -----------')
print(f'Resolved      {resolved}/{total}' + ' ' * (12 - len(f'{resolved}/{total}')) + '~79.6% (Anthropic published)')
print(f'Score         {claw_pct:.1f}%')
print()
print('Note: Claude Code score is from Anthropic\\'s published SWE-bench Verified results.')
print('      See: https://www.anthropic.com/research/swe-bench-sonnet')
"

deactivate

echo ""
echo "Full results: $RESULTS_DIR"
