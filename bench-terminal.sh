#!/usr/bin/env bash
# Benchmark: Terminal-Bench 2.0 — terminal-native task completion
# WARNING: This benchmark takes hours to run and requires Docker
set -euo pipefail
source "$(dirname "$0")/env.sh"

DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$DIR/terminal-bench/results/$(date '+%Y%m%d-%H%M%S')"

echo "=== Terminal-Bench 2.0 Benchmark ==="
echo "Tasks: ${TB2_TASKS:-89} | Max turns: ${TB2_MAX_TURNS:-100}"
echo "Results: $RESULTS_DIR"
echo ""

# --- Prerequisites ---
command -v docker &>/dev/null || { echo "docker required: https://docs.docker.com/get-docker/"; exit 1; }
command -v python3 &>/dev/null || { echo "python3 required"; exit 1; }

if [ ! -x "$CLAW_BIN" ]; then
    echo "ERROR: Binary not found or not executable: $CLAW_BIN" >&2
    exit 1
fi

if [ "${API_KEY:-REPLACE_ME_WITH_YOUR_API_KEY}" = "REPLACE_ME_WITH_YOUR_API_KEY" ]; then
    echo "ERROR: Set API_KEY in env.sh (required for Terminal-Bench)" >&2
    exit 1
fi

# --- Setup Terminal-Bench harness ---
TB_DIR="$DIR/.terminal-bench-harness"
if [ ! -d "$TB_DIR" ]; then
    echo "Installing Terminal-Bench 2.0 harness..."
    git clone https://github.com/laude-institute/terminal-bench.git "$TB_DIR"
    python3 -m venv "$TB_DIR/venv"
    source "$TB_DIR/venv/bin/activate"
    pip install -e "$TB_DIR" 2>&1 | tail -1
    deactivate
else
    echo "Terminal-Bench harness found at $TB_DIR"
fi

mkdir -p "$RESULTS_DIR"

# --- Run agent on Terminal-Bench tasks ---
run_tb2() {
    local label="$1"
    local bin="$2"
    local output_dir="$RESULTS_DIR/${label,,}"

    echo "--- Running $label on Terminal-Bench 2.0 ---"
    echo "Output: $output_dir"

    mkdir -p "$output_dir"
    source "$TB_DIR/venv/bin/activate"

    (
        export ANTHROPIC_BASE_URL="$API_BASE_URL"
        export ANTHROPIC_API_KEY="$API_KEY"

        cd "$TB_DIR"

        python3 -c "
import json, subprocess, os, sys

# Load task list — find the task directory with fallback candidates
tasks_dir = None
for candidate in ['tasks', 'benchmarks', 'data']:
    if os.path.isdir(candidate):
        tasks_dir = candidate
        break
if tasks_dir is None:
    # List repo root to help diagnose
    top_level = sorted(os.listdir('.'))
    print(f'ERROR: could not find task directory. Repo root contains: {top_level}', file=sys.stderr)
    sys.exit(1)

task_files = sorted([f for f in os.listdir(tasks_dir) if f.endswith('.json')])
max_tasks = int('${TB2_TASKS:-89}')
max_turns = int('${TB2_MAX_TURNS:-100}')

results = []
total = min(len(task_files), max_tasks)

for i, tf in enumerate(task_files[:max_tasks]):
    with open(os.path.join(tasks_dir, tf)) as f:
        task = json.load(f)

    task_id = task.get('id', tf.replace('.json', ''))
    instruction = task.get('instruction', '')
    difficulty = task.get('difficulty', 'unknown')

    print(f'[{i+1}/{total}] {task_id} ({difficulty})', flush=True)

    try:
        result = subprocess.run(
            ['$bin', '--dangerously-skip-permissions', '-p', f'Complete this terminal task:\n\n{instruction}\n\nYou have access to a terminal. Execute commands to complete the task.', '--max-turns', str(max_turns)],
            capture_output=True, text=True, timeout=600,
            env={**dict(os.environ)}
        )
        output = result.stdout.strip()
        exit_code = result.returncode
    except subprocess.TimeoutExpired:
        output = ''
        exit_code = -1
        print(f'  TIMEOUT', flush=True)
    except Exception as e:
        output = ''
        exit_code = -1
        print(f'  ERROR: {e}', flush=True)

    results.append({
        'task_id': task_id,
        'difficulty': difficulty,
        'agent': '$label',
        'output': output[:5000],
        'exit_code': exit_code
    })

output_file = '$output_dir/results.jsonl'
with open(output_file, 'w') as f:
    for r in results:
        f.write(json.dumps(r) + '\n')

print(f'Results saved: {len(results)} tasks')
"
    )

    deactivate
    echo ""
}

# --- Run benchmarks ---
run_tb2 "Claw" "$CLAW_BIN"

# --- Report ---
echo "=== Terminal-Bench 2.0 Results ==="
echo ""

python3 -c "
import json

results_file = '$RESULTS_DIR/claw/results.jsonl'
try:
    with open(results_file) as f:
        results = [json.loads(line) for line in f]
except FileNotFoundError:
    print('Claw        No results found')
    results = []

if results:
    total = len(results)
    passed = sum(1 for r in results if r.get('exit_code', -1) == 0)
    pct = (passed / total * 100) if total > 0 else 0

    by_diff = {}
    for r in results:
        d = r.get('difficulty', 'unknown')
        by_diff.setdefault(d, {'total': 0, 'passed': 0})
        by_diff[d]['total'] += 1
        if r.get('exit_code', -1) == 0:
            by_diff[d]['passed'] += 1

    print(f'Claw         {passed}/{total} passed  ({pct:.1f}%)')
    for d in ['easy', 'medium', 'hard']:
        if d in by_diff:
            dp = by_diff[d]['passed']
            dt = by_diff[d]['total']
            print(f'  {d:10s} {dp}/{dt}')
    print()

print('Claude       ~65.4% (published score — not run here)')
print()
"

echo "Full results: $RESULTS_DIR"
