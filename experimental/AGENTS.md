<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-02 | Updated: 2026-04-02 -->

# experimental

## Purpose
Collection of benchmark scripts that are **not** part of the stable default suite. These scripts measure API-path latency, OS-level profiling (syscalls, CPU counters, I/O, threads, memory pressure), and task-effectiveness against external harnesses (SWE-bench Verified, Terminal-Bench 2.0, Aider Polyglot). They are environment-sensitive and intended for manual runs only.

## Key Files

| File | Description |
|------|-------------|
| `bench-ttft.sh` | Time to first token -- measures end-to-end latency of a simple API prompt (`say hi`) |
| `bench-session.sh` | Long session memory -- polls RSS over `SESSION_DURATION` seconds during an API call |
| `bench-syscall.sh` | Syscall count and top-10 breakdown via `strace -c` (--version + API call) |
| `bench-cpu.sh` | CPU hardware counters (cycles, instructions, cache/branch misses, IPC) via `perf stat` |
| `bench-io.sh` | File I/O overhead -- openat/read/write counts via `strace -e trace=` |
| `bench-threads.sh` | Thread/LWP footprint via `/proc/pid/task` during an API call |
| `bench-gc.sh` | Memory allocation pressure -- page faults via `perf stat` + RSS growth via `/proc` polling |
| `bench-swebench.sh` | SWE-bench Verified -- runs Claw on real GitHub issues, evaluates patches via Docker harness |
| `bench-terminal.sh` | Terminal-Bench 2.0 -- terminal-native task completion via Docker harness |
| `bench-polyglot.sh` | Aider Polyglot -- multi-language code editing with self-repair across exercism-style problems |

## For AI Agents

### Working In This Directory
- All scripts source `$ROOT_DIR/env.sh` (one level up). They compute `SCRIPT_DIR` and `ROOT_DIR` at the top.
- API-path scripts (`ttft`, `session`, `syscall` API section, `cpu` API section, `io` API section, `threads`, `gc`) require a valid `API_KEY` in `env.sh`.
- Profiling scripts require Linux-specific tools (`strace`, `perf`). They will not work on macOS.
- Task-effectiveness scripts (`swebench`, `terminal`, `polyglot`) auto-install their harnesses on first run into hidden dirs at the repo root (`.swebench-harness/`, `.terminal-bench-harness/`, `.polyglot-harness/`).
- These scripts take **hours** to run and cost API tokens. Check the `# WARNING:` header comment.
- Codex is included in `bench-ttft.sh` when `CODEX_BIN` is set; task-effectiveness scripts currently run Claw only.

### Testing Requirements
- No automated tests. Validate by running individual scripts with a valid `env.sh`.
- Profiling scripts may require `echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid`.
- Task harness scripts require Docker running and ~50GB+ disk space.

### Common Patterns
- Two-phase measurement: `--version` (local-only, no API) then API call (`-p 'say hi' --max-turns 1`).
- API calls wrapped in subshells `( export ...; ... )` so credentials are not leaked to the parent shell.
- Timeout capping: `timeout -s INT $TIMEOUT` prevents API calls from hanging the suite.
- Results written to timestamped subdirectories under `../swebench/results/`, `../terminal-bench/results/`, `../polyglot/results/`.

## Dependencies

### External
- `strace` -- syscall and I/O profiling (`bench-syscall.sh`, `bench-io.sh`)
- `perf` -- CPU counters and page faults (`bench-cpu.sh`, `bench-gc.sh`)
- `bc` -- arithmetic in all scripts
- `docker` -- SWE-bench and Terminal-Bench evaluation (`bench-swebench.sh`, `bench-terminal.sh`)
- `python3` + `venv` -- harness runners (`bench-swebench.sh`, `bench-terminal.sh`, `bench-polyglot.sh`)
- `git` -- cloning repos for SWE-bench and Polyglot tasks

<!-- MANUAL: -->
