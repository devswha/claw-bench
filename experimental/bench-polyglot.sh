#!/usr/bin/env bash
# Benchmark: Aider Polyglot — Claw-first multi-language code editing + self-repair
# WARNING: This benchmark takes hours to run and costs API tokens
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/env.sh"

DIR="$ROOT_DIR"
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

if [ ! -x "$CLAW_BIN" ]; then
    echo "ERROR: Binary not found or not executable: $CLAW_BIN" >&2
    exit 1
fi

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
    if [ -f "$POLYGLOT_DIR/requirements.txt" ]; then
        pip install -r "$POLYGLOT_DIR/requirements.txt" 2>&1 | tail -1
    fi
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

        python3 -c "
import json, subprocess, os, sys, glob

languages = '${LANGUAGES}'.split(',')
max_attempts = int('${MAX_ATTEMPTS}')
results = []

exercises_base = os.path.join('$POLYGLOT_DIR', 'exercises')
if not os.path.isdir(exercises_base):
    # Find actual exercise directory
    candidates = [d for d in os.listdir('$POLYGLOT_DIR') if os.path.isdir(os.path.join('$POLYGLOT_DIR', d)) and not d.startswith('.') and d not in ('venv',)]
    print(f'  No exercises/ dir found. Repo contents: {candidates}')
    exercises_base = None
    for c in candidates:
        sub = os.path.join('$POLYGLOT_DIR', c)
        if any(os.path.isdir(os.path.join(sub, lang)) for lang in languages):
            exercises_base = sub
            print(f'  Using {c}/ as exercise root')
            break

for lang in languages:
    if exercises_base is None:
        print(f'  Skipping {lang}: could not find exercise directory')
        continue
    problems_dir = os.path.join(exercises_base, lang)
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

            if attempt > 1 and 'last_error' in locals():
                prompt += f'\n\nPrevious attempt failed with:\n{last_error}'

            try:
                result = subprocess.run(
                    ['$bin', '--dangerously-skip-permissions', '-p', prompt, '--max-turns', '5'],
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

# --- Final Report ---
echo "=== Aider Polyglot Results ==="
echo ""

python3 -c "
import json

results_file = '$RESULTS_DIR/claw/results.jsonl'
try:
    with open(results_file) as f:
        results = [json.loads(line) for line in f]
except FileNotFoundError:
    print('Claw        No results found')
    exit()

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

print(f'Claw         {passed}/{total} passed  ({pct:.1f}%)')
for lang in sorted(by_lang):
    v = by_lang[lang]
    print(f'  {lang:12s} {v[\"passed\"]}/{v[\"total\"]}')

print()
"

echo "Full results: $RESULTS_DIR"
