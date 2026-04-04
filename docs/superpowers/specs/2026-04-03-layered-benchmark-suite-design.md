# Layered Benchmark Suite Design

**Date:** 2026-04-03
**Status:** Roadmap Proposal
**Role:** Roadmap
**Authority:** Non-authoritative future-state design. Current-state truth lives in `README.md` plus runnable scripts (`bench-all.sh`, `experimental/*.sh`).
**Relationship:** Broadens the April 1 planning/design artifacts into a future layered-suite roadmap. It does not supersede current repo truth until implemented and explicitly promoted.

## Overview

> **Target-state note:** This document describes a proposed layered suite, not current repo behavior. As of the current repo review, `tasks/`, `results/`, `bench-practical.sh`, `bench-scale.sh`, `bench-harness.sh`, `scripts/lib/`, and `scripts/generate-charts.py` are not present. Heavy harnesses remain manual `experimental/` scripts, and runnable behavior is still Claw-first where script implementations differ from config JSON intent.

Target state: evolve claw-bench from a 2-tier structure (stable + experimental) to a 4-tier layered benchmark suite. In the proposed future state, all tiers would run Claw Code, Claude Code, and Codex CLI symmetrically under identical conditions, with structured JSON results feeding an automated chart pipeline.

## Goals

1. **New benchmark dimensions** — practical coding tasks, token/cost efficiency, concurrent scaling, interactive sessions
2. **Symmetry** — every tool runs the same harness, same prompts, same evaluation
3. **Structured output** — machine-readable JSON results enabling historical tracking and automated chart generation

## Non-Goals

- Statistical rigor improvements (confidence intervals, variance analysis) — future work
- Docker-based reproducible execution environment — future work
- macOS support — future work

## 4-Tier Architecture

```
Tier 0: Runtime Core       Tier 1: Practical Tasks
(existing stable suite)    (NEW — self-contained coding tasks)
- startup time             - 5 micro-tasks (add function, fix bug, refactor, multi-file, debug)
- binary size              - token/cost measurement per task
- idle memory              - multi-turn session performance
~30 seconds, no API key    ~5-10 minutes, API key required

Tier 2: Scaling            Tier 3: Heavy Harnesses
(NEW — concurrency)        (existing experimental, symmetrized)
- concurrent agents        - SWE-bench Verified (symmetric)
- memory under load        - Terminal-Bench 2.0 (symmetric)
- resource ceiling         - Aider Polyglot (symmetric)
~10-20 min, API key        ~hours, API key + Docker
```

Each tier is independently runnable. Higher tiers depend on heavier infrastructure but not on lower tiers.

## Tier 0: Runtime Core (existing)

No changes to `bench-startup.sh`, `bench-size.sh`, `bench-memory.sh`. Already symmetric for Claw/Claude/Codex.

**Output change only:** Each script gains an optional `--json` flag that writes results to `results/tier0/{timestamp}.json`.

## Tier 1: Practical Tasks

### Task Set (5 tasks, ascending difficulty)

| # | Task | Language | Turns | Verification |
|---|------|----------|-------|-------------|
| 1 | Add `is_palindrome(s)` function to empty file | Python | 1 | pytest |
| 2 | Fix off-by-one error in array processing | JavaScript | 1 | node --test |
| 3 | Refactor 200-line file: merge 3 duplicate functions | Python | 3 | pytest + diff size |
| 4 | Update import paths across 3 files | Python | 3 | pytest (all files) |
| 5 | Debug from stack trace: find root cause and fix | Python | 5 | pytest |

### Task Storage Structure

```
tasks/
├── manifest.json              # task list with metadata
├── 01-add-function/
│   ├── task.json              # prompt text, max_turns, language, difficulty
│   ├── workspace/             # initial file state (copied to tmpdir before run)
│   ├── tests/                 # verification tests (run after agent completes)
│   └── expected/              # reference solution (optional, for diff analysis)
├── 02-fix-bug/
│   └── ...
└── 05-debug-session/
    └── ...
```

### Execution Protocol

For each tool (claw, claude, codex) and each task:

1. Copy `workspace/` to a fresh temporary directory
2. Run the agent:
   ```bash
   $BIN --dangerously-skip-permissions \
        -p "$PROMPT" \
        --max-turns $MAX_TURNS \
        --cwd "$TMPDIR"
   ```
3. Run `tests/` against the modified workspace
4. Record results as JSON

### Token/Cost Measurement

**Primary method:** Parse CLI output for token counts. Each CLI has different output formats:
- Claw: parse `--output-format json` if available
- Claude Code: parse stderr session summary
- Codex: parse `--output-format json`

**Fallback method:** API proxy (mitmproxy) to intercept and count request/response tokens. Configured via `API_BASE_URL` redirect.

**Cost calculation:** Token counts multiplied by per-model pricing table defined in `env.sh`:
```bash
COST_PER_1K_INPUT_CLAW=0.003
COST_PER_1K_OUTPUT_CLAW=0.015
# ... etc
```

### Result Schema (per task)

```json
{
  "tool": "claw",
  "task": "01-add-function",
  "passed": true,
  "duration_ms": 3200,
  "turns_used": 1,
  "tokens_in": 450,
  "tokens_out": 120,
  "estimated_cost_usd": 0.0032,
  "diff_lines": 8
}
```

## Tier 2: Scaling

### Benchmarks

| Benchmark | Method | Key Metrics |
|-----------|--------|-------------|
| **Concurrent Agents** | Run N agents (1, 2, 4, 8, 16) in parallel on Task #1 | Per-agent completion time, total throughput (tasks/min), failure rate |
| **Memory Under Load** | Poll `/proc/{pid}/status` VmRSS during N-agent run | Per-agent RSS, total RSS, memory growth curve |
| **Resource Ceiling** | Increase N until OOM or >3x latency degradation | Max stable agent count, latency at ceiling |

### Execution

```bash
for n in 1 2 4 8 16; do
    pids=()
    for i in $(seq 1 $n); do
        workdir=$(mktemp -d)
        cp -r tasks/01-add-function/workspace/* "$workdir/"
        ($BIN --dangerously-skip-permissions -p "$PROMPT" --max-turns 5 \
              --cwd "$workdir") &
        pids+=($!)
    done

    # Monitor loop
    while [ $(alive_count "${pids[@]}") -gt 0 ]; do
        for pid in "${pids[@]}"; do
            record_rss "$pid" >> "$RESULTS_DIR/rss-$n.csv"
        done
        sleep "$POLL_INTERVAL"
    done

    collect_results "$n" "${pids[@]}" >> "$RESULTS_DIR/scaling.json"
done
```

### Result Schema

```json
{
  "tool": "claw",
  "concurrency": 8,
  "agents": [
    {"id": 1, "duration_ms": 4200, "peak_rss_kb": 5100, "passed": true},
    {"id": 2, "duration_ms": 4500, "peak_rss_kb": 5200, "passed": true}
  ],
  "total_rss_peak_kb": 41200,
  "throughput_tasks_per_min": 11.4,
  "failure_count": 0
}
```

## Tier 3: Heavy Harnesses (Symmetrized)

### Changes from Current State

Current: Each experimental script runs Claw only; Claude/Codex scores referenced from published results.

New: Unified harness runner loops over all configured tools:

```bash
# In each bench-{harness}.sh
for tool in claw claude codex; do
    bin_var="${tool^^}_BIN"
    if [ -n "${!bin_var}" ] && [ -x "${!bin_var}" ]; then
        run_harness "$tool" "${!bin_var}" "$RESULTS_DIR"
    else
        echo "Skipping $tool (binary not configured)"
    fi
done
```

### Per-Harness Changes

**SWE-bench (`bench-swebench.sh`):**
- Output: `{tool}-predictions.jsonl` instead of `claw-predictions.jsonl`
- Evaluation: Run `swebench.harness.run_evaluation` per tool
- Report: Side-by-side resolved count and percentage

**Terminal-Bench (`bench-terminal.sh`):**
- Output: `{tool}/results.jsonl` instead of `claw/results.jsonl`
- Report: Per-difficulty breakdown for each tool

**Polyglot (`bench-polyglot.sh`):**
- Output: `{tool}/results.jsonl` instead of `claw/results.jsonl`
- Report: Per-language pass rate for each tool

### Comparison Report

After all tools complete, a Python script generates a comparison table:

```
=== SWE-bench Verified Results ===
              Claw         Claude       Codex
Resolved      12/50        38/50        35/50
Score         24.0%        76.0%        70.0%
```

## Common Infrastructure

### JSON Result Schema (all tiers)

```json
{
  "schema_version": "1.0",
  "timestamp": "2026-04-03T12:00:00Z",
  "tier": 1,
  "benchmark": "practical-tasks",
  "environment": {
    "os": "Ubuntu 24.04",
    "kernel": "6.8.0-106-generic",
    "cpu": "AMD Ryzen 9 7950X",
    "memory_gb": 64,
    "hostname": "bench-host"
  },
  "tools": {
    "claw": {"version": "0.5.2", "binary": "/usr/local/bin/claw"},
    "claude": {"version": "1.0.38", "binary": "/usr/local/bin/claude"},
    "codex": {"version": "0.1.5", "binary": "/usr/local/bin/codex"}
  },
  "results": []
}
```

### Chart Pipeline

```
bench-*.sh --json → results/tier{N}/{timestamp}.json
                              ↓
              scripts/generate-charts.py (reads latest JSON per tier)
                              ↓
              assets/tier-{N}-chart.svg
                              ↓
              README.md references (manual or CI-updated)
```

`generate-charts.py` is extended from the existing `generate-chart.py` to read JSON result files and produce per-tier SVG charts.

### File Structure (new files)

```
claw-bench/
├── tasks/                          # Tier 1 task definitions
│   ├── manifest.json
│   └── 01-add-function/
│       ├── task.json
│       ├── workspace/
│       └── tests/
├── bench-practical.sh              # Tier 1 runner
├── bench-scale.sh                  # Tier 2 runner
├── bench-harness.sh                # Tier 3 unified runner (replaces individual experimental scripts)
├── scripts/
│   ├── generate-chart.py           # existing (Tier 0 chart)
│   ├── generate-charts.py          # extended (all tiers)
│   ├── compare-results.py          # cross-tool comparison tables
│   └── lib/
│       ├── runner.sh               # common agent execution functions
│       ├── monitor.sh              # RSS/CPU monitoring functions
│       └── results.sh              # JSON result writing functions
├── results/                        # structured result storage
│   ├── tier0/
│   ├── tier1/
│   ├── tier2/
│   └── tier3/
└── assets/
    ├── benchmark-chart.svg         # existing (Tier 0)
    ├── tier-1-chart.svg
    ├── tier-2-chart.svg
    └── tier-3-chart.svg
```

### Shared Shell Library (`scripts/lib/`)

Common functions extracted to avoid duplication across tier scripts:

- `runner.sh`: `run_agent()`, `validate_binary()`, `detect_tools()`
- `monitor.sh`: `record_rss()`, `alive_count()`, `poll_resources()`
- `results.sh`: `write_json_header()`, `append_result()`, `finalize_json()`

## Implementation Priority

| Phase | Scope | Estimate |
|-------|-------|----------|
| Phase 1 | Shared library + JSON output for Tier 0 | Small |
| Phase 2 | Tier 1: task set + runner + token measurement | Medium |
| Phase 3 | Tier 2: scaling benchmarks | Medium |
| Phase 4 | Tier 3: symmetrize existing harnesses | Medium |
| Phase 5 | Chart pipeline + CI integration | Small |

Phases are independent after Phase 1 (shared library).

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Token counting varies by CLI version | Document supported versions; fallback to API proxy |
| Concurrent agent execution exhausts API rate limits | Add configurable delay between agent starts; document rate limit requirements |
| Claude Code / Codex CLI flags differ from Claw | Abstract CLI invocation in `runner.sh` with per-tool argument profiles |
| Task set too easy/hard to differentiate tools | Calibrate difficulty with all 3 tools before finalizing; keep tasks versioned |
| SWE-bench full run takes hours × 3 tools | Support `--tasks N` to limit task count for quick comparison runs |
