# Task Effectiveness Benchmarks — Implementation Plan

**Role:** Historical Reference
**Authority:** Non-authoritative planning artifact. Current-state truth lives in `README.md` plus runnable scripts (`bench-all.sh`, `experimental/*.sh`).
**Relationship:** Retained as April 1 planning context. The broader future-state direction is captured in `docs/superpowers/specs/2026-04-03-layered-benchmark-suite-design.md`, but current repo behavior still follows `README.md` and runnable scripts.

> **Current-state note:** This document records an earlier plan for symmetric task-effectiveness benchmarking. In the current repo, heavy harnesses live under `experimental/`, are manual to run, and runnable scripts remain Claw-first even where config JSON files encode future symmetric intent.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3 task-level effectiveness benchmark scripts (SWE-bench, Terminal-Bench 2.0, Aider Polyglot) that measure CLI tool capability, complementing existing runtime performance benchmarks.

**Architecture (original proposal):** Each benchmark would be a self-contained bash script that: (1) validates prerequisites (Docker, Python, CLI tools), (2) sets up the benchmark harness if not already installed, (3) runs tasks against both Claw and Claude, (4) collects results into JSON, and (5) outputs a formatted comparison table. In the current repo, these harnesses remain manual `experimental/` scripts, and runnable behavior is still Claw-first unless future script changes explicitly implement symmetric flows.

**Tech Stack:** Bash, Docker, Python 3.10+, SWE-bench harness, Harbor eval framework, Aider polyglot runner

> **Path/layout note:** File names below follow the original proposal wording. In the current repository, the heavy harness scripts live under `experimental/`, and runnable scripts are authoritative for present behavior.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `bench-swebench.sh` | Create | SWE-bench Verified runner + result reporter |
| `bench-terminal.sh` | Create | Terminal-Bench 2.0 runner + result reporter |
| `bench-polyglot.sh` | Create | Aider Polyglot runner + result reporter |
| `swebench/config.json` | Create | SWE-bench task selection and settings |
| `swebench/.gitkeep` | Create | Keep results directory in git |
| `terminal-bench/config.json` | Create | Terminal-Bench settings |
| `terminal-bench/.gitkeep` | Create | Keep results directory in git |
| `polyglot/config.json` | Create | Aider Polyglot settings |
| `polyglot/.gitkeep` | Create | Keep results directory in git |
| `env.example.sh` | Modify | Add task effectiveness config variables |
| `README.md` | Modify | Add task effectiveness benchmarks section |
| `.gitignore` | Modify | Ignore result JSON files and venv |

---

### Task 1: Update config files and shared infrastructure

**Files:**
- Modify: `env.example.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Add task effectiveness variables to env.example.sh**

Append after `GC_POLL_INTERVAL` line:

```bash
# Task effectiveness benchmark settings
SWEBENCH_TASKS=500                        # number of SWE-bench Verified tasks (max 500)
SWEBENCH_TIMEOUT=300                      # seconds per task
SWEBENCH_MODEL="claude-sonnet-4-5-20250514"  # model for API-based runs
TB2_TASKS=89                              # Terminal-Bench 2.0 tasks (max 89)
TB2_MAX_TURNS=100                         # max terminal turns per task
POLYGLOT_LANGUAGES="python,javascript,go,rust,java,cpp"  # Aider polyglot languages
POLYGLOT_MAX_ATTEMPTS=2                   # attempts per problem (2 = includes self-repair)
```

- [ ] **Step 2: Add result directories and venv to .gitignore**

Append to `.gitignore`:

```
# Task effectiveness benchmark results (large JSON files)
swebench/results/
terminal-bench/results/
polyglot/results/

# Python virtual environments
.venv/
venv/

# Auto-installed benchmark harnesses
.swebench-harness/
.terminal-bench-harness/
.polyglot-harness/
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n env.example.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add env.example.sh .gitignore
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 2: Create SWE-bench config and directory structure

**Files:**
- Create: `swebench/config.json`
- Create: `swebench/results/.gitkeep`

- [ ] **Step 1: Create swebench directory and config**

```bash
mkdir -p swebench/results
```

Create `swebench/config.json`:

```json
{
  "dataset": "princeton-nlp/SWE-bench_Verified",
  "split": "test",
  "max_tasks": 500,
  "timeout_per_task": 300,
  "docker_image_prefix": "swebench",
  "output_format": "jsonl",
  "evaluation": {
    "run_tests": true,
    "fail_to_pass": true,
    "pass_to_pass": true
  },
  "agents": {
    "claw": {
      "command": "$CLAW_BIN -p '{issue_text}' --max-turns 10",
      "env": {
        "ANTHROPIC_API_KEY": "$API_KEY",
        "ANTHROPIC_BASE_URL": "$API_BASE_URL"
      }
    },
    "claude": {
      "command": "$CLAUDE_BIN -p '{issue_text}' --max-turns 10",
      "env": {
        "ANTHROPIC_API_KEY": "$API_KEY",
        "ANTHROPIC_BASE_URL": "$API_BASE_URL"
      }
    }
  }
}
```

- [ ] **Step 2: Create .gitkeep**

```bash
touch swebench/results/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add swebench/
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 3: Create `bench-swebench.sh`

**Files:**
- Create: `bench-swebench.sh`

- [ ] **Step 1: Create the script**

```bash
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
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x bench-swebench.sh
bash -n bench-swebench.sh
```
Expected: No output (success)

- [ ] **Step 3: Commit**

```bash
git add bench-swebench.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 4: Create Terminal-Bench config and directory structure

**Files:**
- Create: `terminal-bench/config.json`
- Create: `terminal-bench/results/.gitkeep`

- [ ] **Step 1: Create directory and config**

```bash
mkdir -p terminal-bench/results
```

Create `terminal-bench/config.json`:

```json
{
  "benchmark": "terminal-bench-2.0",
  "tasks": 89,
  "max_turns_per_task": 100,
  "runtime": "docker",
  "difficulty_tiers": ["easy", "medium", "hard"],
  "agents": {
    "claw": {
      "command": "$CLAW_BIN",
      "type": "cli"
    },
    "claude": {
      "command": "$CLAUDE_BIN",
      "type": "cli"
    }
  }
}
```

- [ ] **Step 2: Create .gitkeep**

```bash
touch terminal-bench/results/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add terminal-bench/
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 5: Create `bench-terminal.sh`

**Files:**
- Create: `bench-terminal.sh`

- [ ] **Step 1: Create the script**

```bash
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

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

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

# Load task list
tasks_dir = 'tasks'
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
            ['$bin', '-p', f'Complete this terminal task:\n\n{instruction}\n\nYou have access to a terminal. Execute commands to complete the task.', '--max-turns', str(max_turns)],
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
run_tb2 "Claude" "$CLAUDE_BIN"

# --- Report ---
echo "=== Terminal-Bench 2.0 Results ==="
echo ""

python3 -c "
import json

for label in ['Claw', 'Claude']:
    results_file = '$RESULTS_DIR/' + label.lower() + '/results.jsonl'
    try:
        with open(results_file) as f:
            results = [json.loads(line) for line in f]
    except FileNotFoundError:
        print(f'{label:12s} No results found')
        continue

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

    print(f'{label:12s} {passed}/{total} passed  ({pct:.1f}%)')
    for d in ['easy', 'medium', 'hard']:
        if d in by_diff:
            dp = by_diff[d]['passed']
            dt = by_diff[d]['total']
            print(f'  {d:10s} {dp}/{dt}')

print()
"

echo "Full results: $RESULTS_DIR"
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x bench-terminal.sh
bash -n bench-terminal.sh
```
Expected: No output (success)

- [ ] **Step 3: Commit**

```bash
git add bench-terminal.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 6: Create Aider Polyglot config and directory structure

**Files:**
- Create: `polyglot/config.json`
- Create: `polyglot/results/.gitkeep`

- [ ] **Step 1: Create directory and config**

```bash
mkdir -p polyglot/results
```

Create `polyglot/config.json`:

```json
{
  "benchmark": "aider-polyglot",
  "source": "https://github.com/Aider-AI/polyglot-benchmark",
  "languages": ["python", "javascript", "go", "rust", "java", "cpp"],
  "total_problems": 225,
  "max_attempts": 2,
  "agents": {
    "claw": {
      "command": "$CLAW_BIN"
    },
    "claude": {
      "command": "$CLAUDE_BIN"
    }
  }
}
```

- [ ] **Step 2: Create .gitkeep**

```bash
touch polyglot/results/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add polyglot/
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 7: Create `bench-polyglot.sh`

**Files:**
- Create: `bench-polyglot.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: Aider Polyglot — multi-language code editing + self-repair
# WARNING: This benchmark takes hours to run and costs API tokens
set -euo pipefail
source "$(dirname "$0")/env.sh"

DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$DIR/polyglot/results/$(date '+%Y%m%d-%H%M%S')"

LANGUAGES="${POLYGLOT_LANGUAGES:-python,javascript,go,rust,java,cpp}"
MAX_ATTEMPTS="${POLYGLOT_MAX_ATTEMPTS:-2}"

echo "=== Aider Polyglot Benchmark ==="
echo "Languages: $LANGUAGES | Max attempts: $MAX_ATTEMPTS"
echo "Results: $RESULTS_DIR"
echo ""

# --- Prerequisites ---
command -v python3 &>/dev/null || { echo "python3 required"; exit 1; }
command -v git &>/dev/null || { echo "git required"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

if [ "${API_KEY:-REPLACE_ME_WITH_YOUR_API_KEY}" = "REPLACE_ME_WITH_YOUR_API_KEY" ]; then
    echo "ERROR: Set API_KEY in env.sh (required for Polyglot)" >&2
    exit 1
fi

# --- Setup Aider Polyglot harness ---
POLYGLOT_DIR="$DIR/.polyglot-harness"
if [ ! -d "$POLYGLOT_DIR" ]; then
    echo "Cloning Aider Polyglot benchmark..."
    git clone https://github.com/Aider-AI/polyglot-benchmark.git "$POLYGLOT_DIR"
    python3 -m venv "$POLYGLOT_DIR/venv"
    source "$POLYGLOT_DIR/venv/bin/activate"
    pip install -r "$POLYGLOT_DIR/requirements.txt" 2>&1 | tail -1
    deactivate
else
    echo "Polyglot harness found at $POLYGLOT_DIR"
fi

mkdir -p "$RESULTS_DIR"

# --- Run agent on Polyglot problems ---
run_polyglot() {
    local label="$1"
    local bin="$2"
    local output_dir="$RESULTS_DIR/${label,,}"

    echo "--- Running $label on Aider Polyglot ---"
    echo "Output: $output_dir"

    mkdir -p "$output_dir"
    source "$POLYGLOT_DIR/venv/bin/activate"

    (
        export ANTHROPIC_BASE_URL="$API_BASE_URL"
        export ANTHROPIC_API_KEY="$API_KEY"

        IFS=',' read -ra LANG_LIST <<< "$LANGUAGES"

        python3 -c "
import json, subprocess, os, sys, glob

languages = '${LANGUAGES}'.split(',')
max_attempts = int('${MAX_ATTEMPTS}')
results = []

for lang in languages:
    problems_dir = os.path.join('$POLYGLOT_DIR', 'exercises', lang)
    if not os.path.isdir(problems_dir):
        print(f'  Skipping {lang}: no exercises found')
        continue

    problems = sorted([d for d in os.listdir(problems_dir) if os.path.isdir(os.path.join(problems_dir, d))])
    print(f'  {lang}: {len(problems)} problems', flush=True)

    for prob in problems:
        prob_dir = os.path.join(problems_dir, prob)

        # Read problem description
        desc_file = os.path.join(prob_dir, '.docs', 'instructions.md')
        if not os.path.exists(desc_file):
            desc_files = glob.glob(os.path.join(prob_dir, '*.md'))
            desc_file = desc_files[0] if desc_files else None

        description = ''
        if desc_file and os.path.exists(desc_file):
            with open(desc_file) as f:
                description = f.read()

        # Find stub file
        stub_files = [f for f in os.listdir(prob_dir) if not f.startswith('.') and not f.endswith('.md') and os.path.isfile(os.path.join(prob_dir, f))]

        passed = False
        for attempt in range(1, max_attempts + 1):
            prompt = f'Solve this {lang} exercise:\n\n{description}\n\nFiles in directory: {stub_files}\nAttempt {attempt}/{max_attempts}'

            if attempt > 1 and 'last_error' in dir():
                prompt += f'\n\nPrevious attempt failed with:\n{last_error}'

            try:
                result = subprocess.run(
                    ['$bin', '-p', prompt, '--max-turns', '5'],
                    capture_output=True, text=True, timeout=120,
                    cwd=prob_dir,
                    env={**dict(os.environ)}
                )
            except subprocess.TimeoutExpired:
                last_error = 'TIMEOUT'
                continue
            except Exception as e:
                last_error = str(e)
                continue

            # Check if tests pass (language-specific test runners)
            test_cmd = {
                'python': ['python3', '-m', 'pytest', '-x'],
                'javascript': ['node', '--test'],
                'go': ['go', 'test', './...'],
                'rust': ['cargo', 'test'],
                'java': ['gradle', 'test'],
                'cpp': ['cmake', '--build', '.', '--target', 'test']
            }.get(lang, ['echo', 'no test runner'])

            try:
                test_result = subprocess.run(
                    test_cmd, capture_output=True, text=True, timeout=60, cwd=prob_dir
                )
                if test_result.returncode == 0:
                    passed = True
                    break
                else:
                    last_error = test_result.stderr[:500]
            except Exception:
                last_error = 'test runner failed'

        results.append({
            'language': lang,
            'problem': prob,
            'passed': passed,
            'attempts': attempt,
            'agent': '$label'
        })

output_file = '$output_dir/results.jsonl'
with open(output_file, 'w') as f:
    for r in results:
        f.write(json.dumps(r) + '\n')

# Summary
by_lang = {}
for r in results:
    lang = r['language']
    by_lang.setdefault(lang, {'total': 0, 'passed': 0})
    by_lang[lang]['total'] += 1
    if r['passed']:
        by_lang[lang]['passed'] += 1

total_passed = sum(v['passed'] for v in by_lang.values())
total_all = sum(v['total'] for v in by_lang.values())
pct = (total_passed / total_all * 100) if total_all > 0 else 0

print(f'$label: {total_passed}/{total_all} passed ({pct:.1f}%)')
for lang, v in sorted(by_lang.items()):
    lp = (v['passed'] / v['total'] * 100) if v['total'] > 0 else 0
    print(f'  {lang:12s} {v[\"passed\"]}/{v[\"total\"]} ({lp:.1f}%)')
"
    )

    deactivate
    echo ""
}

# --- Run benchmarks ---
run_polyglot "Claw" "$CLAW_BIN"
run_polyglot "Claude" "$CLAUDE_BIN"

# --- Final Report ---
echo "=== Aider Polyglot Results ==="
echo ""

python3 -c "
import json

for label in ['Claw', 'Claude']:
    results_file = '$RESULTS_DIR/' + label.lower() + '/results.jsonl'
    try:
        with open(results_file) as f:
            results = [json.loads(line) for line in f]
    except FileNotFoundError:
        print(f'{label:12s} No results found')
        continue

    total = len(results)
    passed = sum(1 for r in results if r.get('passed', False))
    pct = (passed / total * 100) if total > 0 else 0

    by_lang = {}
    for r in results:
        lang = r.get('language', 'unknown')
        by_lang.setdefault(lang, {'total': 0, 'passed': 0})
        by_lang[lang]['total'] += 1
        if r.get('passed', False):
            by_lang[lang]['passed'] += 1

    print(f'{label:12s} {passed}/{total} passed  ({pct:.1f}%)')
    for lang in sorted(by_lang):
        v = by_lang[lang]
        print(f'  {lang:12s} {v[\"passed\"]}/{v[\"total\"]}')

print()
"

echo "Full results: $RESULTS_DIR"
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x bench-polyglot.sh
bash -n bench-polyglot.sh
```
Expected: No output (success)

- [ ] **Step 3: Commit**

```bash
git add bench-polyglot.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 8: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add task effectiveness section after the Runtime Overhead section**

Add after the existing "Runtime Overhead" section and before "## Benchmarks":

```markdown
### Task Effectiveness (what it can do)

These benchmarks measure whether the CLI tools can successfully complete real-world development tasks. They require Docker, Python, and API keys, and take hours to run.

| Benchmark | Tasks | Measures | Source |
|-----------|-------|----------|--------|
| [SWE-bench Verified](https://swebench.com/) | 500 | Real GitHub issue resolution | princeton-nlp |
| [Terminal-Bench 2.0](https://tbench.ai/) | 89 | Terminal-native task completion | Laude Institute |
| [Aider Polyglot](https://aider.chat/2024/12/21/polyglot.html) | 225 | Multi-language code editing | Aider-AI |

> Run individually: `./bench-swebench.sh`, `./bench-terminal.sh`, `./bench-polyglot.sh`
> These are NOT included in `bench-all.sh` due to long runtime and API cost.
```

- [ ] **Step 2: Add new scripts to the Benchmarks table**

Add after `bench-gc.sh` row:

```markdown
| `bench-swebench.sh` | SWE-bench Verified score | Docker + Python |
| `bench-terminal.sh` | Terminal-Bench 2.0 score | Docker + Harbor |
| `bench-polyglot.sh` | Aider Polyglot score | Python + git |
```

- [ ] **Step 3: Update prerequisites**

Add a new section after the existing prerequisites block:

```markdown
### Task Effectiveness Prerequisites

```bash
# Docker (required for SWE-bench and Terminal-Bench)
# See: https://docs.docker.com/get-docker/

# Python 3.10+ with venv
sudo apt install python3-venv

# Harnesses are auto-installed on first run
# Disk space: ~50GB for SWE-bench, ~20GB for Terminal-Bench
```
```

- [ ] **Step 4: Commit**

```bash
git add README.md
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 9: Final validation

- [ ] **Step 1: Verify all new scripts are executable**

Run: `ls -la bench-swebench.sh bench-terminal.sh bench-polyglot.sh`
Expected: All show `-rwxr-xr-x`

- [ ] **Step 2: Syntax check all scripts**

Run: `for f in bench-swebench.sh bench-terminal.sh bench-polyglot.sh; do echo -n "$f: "; bash -n "$f" && echo "OK"; done`
Expected: All print "OK"

- [ ] **Step 3: Verify config files are valid JSON**

Run: `for f in swebench/config.json terminal-bench/config.json polyglot/config.json; do echo -n "$f: "; python3 -m json.tool "$f" > /dev/null && echo "OK"; done`
Expected: All print "OK"

- [ ] **Step 4: Verify directory structure**

Run: `find swebench terminal-bench polyglot -type f | sort`
Expected:
```
polyglot/config.json
polyglot/results/.gitkeep
swebench/config.json
swebench/results/.gitkeep
terminal-bench/config.json
terminal-bench/results/.gitkeep
```

- [ ] **Step 5: Verify harness directories are gitignored**

Run: `git status --short .swebench-harness .terminal-bench-harness .polyglot-harness 2>/dev/null`
Expected: No output (not tracked)
