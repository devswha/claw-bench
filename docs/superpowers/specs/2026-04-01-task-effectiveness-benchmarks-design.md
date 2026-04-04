# Task Effectiveness Benchmarks — Design Spec

**Date**: 2026-04-01
**Status**: Historical Reference (Draft)
**Role**: Historical Reference
**Authority**: Non-authoritative design note. Current-state truth lives in `README.md` plus runnable scripts (`bench-all.sh`, `experimental/*.sh`).
**Relationship**: Retained as April 1 design context. The broader future-state direction appears in `docs/superpowers/specs/2026-04-03-layered-benchmark-suite-design.md`, but current runnable harness behavior remains manual and Claw-first.
**Purpose**: Add task-level effectiveness benchmarks that measure *what the CLI tools can do*, complementing the existing runtime performance benchmarks that measure *how fast they do it*.

> **Current-state note:** In the current repo, heavy harnesses live under `experimental/`, remain manual to run, and runnable scripts are Claw-first even where config JSON files already encode possible future symmetric intent.

## Context

claw-bench currently measures runtime performance (startup, memory, CPU, syscalls, etc.). These answer "is Claw faster?" but not "can Claw do the same work?"

Task effectiveness benchmarks measure whether a CLI coding tool can successfully complete real-world development tasks — fixing bugs, implementing features, navigating codebases, and executing terminal commands.

## Target Audiences

1. **Promotional**: "Claw Code resolves X% of SWE-bench tasks" — credibility metric
2. **Technical decision-makers**: Objective capability comparison, not just speed

## Research Summary

### Benchmark Landscape

| Benchmark | Measures | CLI Applicability | Recommendation |
|---|---|---|---|
| SWE-bench Verified | Real GitHub issue resolution | High — industry standard | **Primary** |
| Terminal-Bench 2.0 | Terminal-native task completion | Very high — designed for CLI | **Primary** |
| Aider Polyglot | Multi-language code editing | Moderate-high | **Secondary** |
| LiveCodeBench | Competitive programming | Moderate (model quality) | Optional |
| HumanEval / MBPP | Single-function generation | Low — saturated | Skip |

### Recommended Benchmarks

#### 1. SWE-bench Verified

**What**: 500 human-validated real-world GitHub issues from 12 Python repos. The tool must produce a patch that fixes the issue and passes all tests.

**Why it matters**: Industry standard for agentic coding. Every major AI lab reports scores on this. Anthropic's Claude Opus 4.5 scores ~80.9%, Codex CLI ~72%.

**How it works**:
- Input: Repository + base commit + issue description
- Output: A `.patch` file
- Evaluation: Apply patch in Docker container, run test suite
- Scoring: Binary pass/fail per task. Score = % of tasks where all FAIL_TO_PASS tests pass AND all PASS_TO_PASS tests still pass.

**Infrastructure**: Docker required. Each task runs in an isolated container with the repo at the correct commit. Evaluation harness provided by [SWE-bench/SWE-bench](https://github.com/SWE-bench/SWE-bench).

**Current SOTA** (Verified):
- Claude Opus 4.5/4.6: ~80.9% / ~79.6%
- Claude Sonnet 4.5: ~77.2%
- Gemini 3.1 Pro: ~80.6%

#### 2. Terminal-Bench 2.0

**What**: 89 curated hard tasks that must be completed entirely via terminal commands. Spans: compiling repos, configuring servers, training ML models, debugging systems, network services, cybersecurity.

**Why it matters**: Most directly applicable to CLI coding tools. Tests terminal-native capabilities — exactly what Claw Code and Claude Code are built for.

**How it works**:
- Input: Docker container with pre-loaded environment + natural language instruction
- Interaction: Terminal commands only, up to 100 turns
- Evaluation: pytest-based verification tests
- Scoring: Binary pass@1 per task

**Infrastructure**: Docker + Harbor eval framework (supports docker, daytona, e2b, modal).

**Current results** (TB2):
- Codex CLI (GPT-5.3): ~77.3%
- Claude Code: ~65.4%

**Source**: [tbench.ai](https://www.tbench.ai/), [GitHub](https://github.com/laude-institute/terminal-bench)

#### 3. Aider Polyglot (Secondary)

**What**: 225 Exercism problems across C++, Go, Java, JavaScript, Python, Rust. Tests code editing + self-repair.

**Why it matters**: Tests multi-language editing accuracy — a core CLI agent capability. Two attempts allowed (second attempt includes test failure output).

**How it works**:
- Input: Problem description + stub file + test suite
- Output: Modified file
- Scoring: % of tasks with all tests passing

**Source**: [aider.chat](https://aider.chat/2024/12/21/polyglot.html), [GitHub](https://github.com/Aider-AI/polyglot-benchmark)

## Proposed Implementation

### Phase 1: SWE-bench Verified Integration

```
bench-swebench.sh
├── Pulls SWE-bench Verified dataset (500 tasks)
├── Runs each task against both CLIs in Docker
├── Collects pass/fail results
└── Reports: score %, task breakdown, comparison table
```

**Dependencies**:
- Docker
- Python 3.11+ (SWE-bench harness)
- ~50GB disk (Docker images for 12 repos)
- API key for both CLIs

**Estimated runtime**: Hours (500 tasks × minutes each)

### Phase 2: Terminal-Bench 2.0 Integration

```
bench-terminal.sh
├── Uses Harbor eval framework
├── Runs TB2 89 tasks against both CLIs
├── Collects pass/fail per task
└── Reports: score %, difficulty breakdown, comparison
```

**Dependencies**:
- Docker
- Harbor CLI (`pip install harbor-ai`)
- ~20GB disk

**Estimated runtime**: Hours (89 tasks, up to 100 turns each)

### Phase 3: Aider Polyglot (Optional)

```
bench-polyglot.sh
├── Clones Aider polyglot benchmark
├── Runs 225 tasks per CLI
├── Reports per-language scores
└── Includes self-repair (2nd attempt) scores
```

## Design Constraints

- Each phase is independently useful — no dependencies between phases
- Docker required (unlike runtime benchmarks which need only bash)
- Results are expensive to generate (hours, not seconds) — run manually, not in bench-all.sh
- Separate from runtime benchmarks in documentation and execution
- API costs: SWE-bench 500 tasks could cost $50-200+ per CLI depending on token usage

## File Structure

```
claw-bench/
├── bench-swebench.sh        # Phase 1
├── bench-terminal.sh        # Phase 2
├── bench-polyglot.sh        # Phase 3 (optional)
├── swebench/                # SWE-bench config and results
│   ├── config.json          # Task selection, Docker settings
│   └── results/             # Per-run result JSONs
├── terminal-bench/          # TB2 config and results
│   ├── config.json
│   └── results/
└── README.md                # Updated with task effectiveness section
```

## Output Format

Consistent with existing benchmarks — ratio column for promotional use:

```
=== SWE-bench Verified (500 tasks) ===
              Claw       Claude     Ratio
Resolved      312/500    405/500
Score         62.4%      81.0%      0.77x
Avg time      2.1 min    3.8 min    1.8x faster

=== Terminal-Bench 2.0 (89 tasks) ===
              Claw       Claude     Ratio
Passed        48/89      58/89
Score         53.9%      65.2%      0.83x
Easy          18/20      19/20
Medium        22/40      28/40
Hard          8/29       11/29
```

## Key Differences from Runtime Benchmarks

| Aspect | Runtime Benchmarks | Task Effectiveness |
|---|---|---|
| Measures | Speed, memory, overhead | Capability, accuracy |
| Duration | Seconds-minutes | Hours |
| Infrastructure | bash + strace/perf | Docker + Python |
| Cost | Free (local only) | API tokens ($50-200+) |
| In bench-all.sh | Yes | No (manual only) |
| Update frequency | Stable | Evolving (new tasks) |

## Anthropic's Evaluation Approach (Reference)

Anthropic uses a layered evaluation strategy for Claude Code:

1. **External benchmarks**: SWE-bench Verified, Terminal-Bench, OSWorld
2. **Internal behavioral evals**: Edit correctness, concision, over-engineering
3. **User preference A/B tests**: Production-level user satisfaction signals
4. **Statistical rigor**: Confidence intervals, proper eval methodology

Source: [Anthropic Engineering: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

## Future Considerations

- **SWE-bench Live**: Rolling monthly updates, contamination-resistant. Good for ongoing tracking.
- **SWE-bench Pro**: Harder enterprise-scale tasks. Consider when available.
- **Community runner**: [jimmc414/claudecode_gemini_and_codex_swebench](https://github.com/jimmc414/claudecode_gemini_and_codex_swebench) — existing toolkit for comparing CLI tools on SWE-bench.
- **LiveCodeBench**: Useful for comparing base model reasoning quality if needed.

## References

- [SWE-bench — swebench.com](https://www.swebench.com/)
- [SWE-bench GitHub](https://github.com/SWE-bench/SWE-bench)
- [SWE-bench Verified — HuggingFace](https://huggingface.co/datasets/princeton-nlp/SWE-bench)
- [SWE-bench Live — microsoft/SWE-bench-Live](https://github.com/microsoft/SWE-bench-Live)
- [Terminal-Bench — tbench.ai](https://www.tbench.ai/)
- [Terminal-Bench GitHub](https://github.com/laude-institute/terminal-bench)
- [Terminal-Bench arXiv — 2601.11868](https://arxiv.org/abs/2601.11868)
- [Aider Polyglot](https://aider.chat/2024/12/21/polyglot.html)
- [Aider-AI/polyglot-benchmark](https://github.com/Aider-AI/polyglot-benchmark)
- [LiveCodeBench](https://livecodebench.github.io/)
- [Anthropic: Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
