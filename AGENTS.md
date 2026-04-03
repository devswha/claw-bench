<!-- Generated: 2026-04-02 | Updated: 2026-04-02 -->

# claw-bench

## Purpose
Benchmark suite comparing **Claw Code** (Rust single-binary CLI) vs **Claude Code** (Node.js CLI) runtime overhead, with optional **Codex CLI** as a third comparison target. The stable default suite measures local runtime characteristics (startup, size, memory); experimental scripts cover profiling, API-path latency, and task-effectiveness harnesses (SWE-bench, Terminal-Bench, Aider Polyglot).

## Key Files

| File | Description |
|------|-------------|
| `bench-all.sh` | Runs the stable runtime suite (startup + size + memory) |
| `bench-startup.sh` | Cold-start time via `hyperfine` (`--version` invocation) |
| `bench-size.sh` | Binary size, install footprint, and dependency count via `du` |
| `bench-memory.sh` | Idle RSS memory via `/usr/bin/time -v` |
| `env.example.sh` | Configuration template: binary paths, API key, tuning knobs |
| `env.sh` | Active configuration (gitignored, never committed) |
| `README.md` | Project documentation with sample results and quick-start |
| `LICENSE` | MIT license |
| `.gitignore` | Excludes env.sh, harness dirs, results, and tool artifacts |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `experimental/` | Profiling and task-effectiveness benchmark scripts (see `experimental/AGENTS.md`) |
| `swebench/` | SWE-bench Verified results storage (see `swebench/AGENTS.md`) |
| `terminal-bench/` | Terminal-Bench 2.0 results storage (see `terminal-bench/AGENTS.md`) |
| `polyglot/` | Aider Polyglot results storage (see `polyglot/AGENTS.md`) |
| `docs/` | Plans and design specs (see `docs/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- All scripts source `env.sh` for configuration. Ensure it exists before running any benchmark.
- The stable suite (`bench-all.sh`) requires only `hyperfine` and `bc` -- no API key needed.
- Experimental scripts have heavier dependencies (strace, perf, Docker, Python venv). Check prerequisites in each script header.
- Codex CLI inclusion is automatic when `CODEX_BIN` is set and executable in `env.sh`.
- Never commit `env.sh` -- it contains API keys.

### Testing Requirements
- Scripts are self-contained bash; there is no test framework. Validate by running individual scripts.
- For the stable suite: `./bench-all.sh` should complete in under a minute.
- For experimental scripts: check the `# WARNING:` comment at the top of each script for time/cost expectations.

### Common Patterns
- Every script starts with `set -euo pipefail` and `source "$(dirname "$0")/env.sh"`.
- Experimental scripts use `SCRIPT_DIR` / `ROOT_DIR` to resolve paths since they live in a subdirectory.
- Binary validation: each script checks `[ -x "$bin" ]` before execution.
- Optional Codex: guarded by `has_codex=true/false` based on `CODEX_BIN` availability.
- Timeout-capped measurements: API-path benchmarks use `timeout` to prevent hangs, with `[timeout]` annotations in output.
- Ratio computation: all comparisons compute `claude_value / claw_value` ratios via `bc`.

## Dependencies

### External
- `hyperfine` -- stable suite startup benchmark
- `bc` -- arithmetic in all scripts
- `strace` -- syscall and I/O profiling (experimental)
- `perf` -- CPU counters and page-fault profiling (experimental)
- `docker` -- SWE-bench and Terminal-Bench evaluation harnesses (experimental)
- `python3` + `venv` -- task-effectiveness harness runners (experimental)

<!-- MANUAL: -->
