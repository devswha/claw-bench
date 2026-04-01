# claw-bench

Benchmark suite comparing **Claw Code** (Rust single-binary CLI) vs **Claude Code** (Node.js CLI), with **optional Codex runtime comparison** for the core benchmarks.

Inspired by [claw-code](https://github.com/devswha/claw-code).

## Sample Results

Measured on Ubuntu 24.04 (Linux 6.8), same machine, same API endpoint.

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Startup time | **1.2 ms** | 86.4 ms | 73.2x faster |
| Binary size | **13 MB** | 218 MB | 17x smaller |
| Memory (idle) | **4.1 MB** | 191.5 MB | 46.7x less |
| Memory (API call) | **9.9 MB** | 314.5 MB | 31.8x less |
| Response time (TTFT) | **2.1 s** | 8.1 s | 3.8x faster |

> Results vary by machine, network, and API provider. Run your own benchmarks.
> Current API-path benchmarks may be capped by `API_CALL_TIMEOUT` when helper processes linger after the first response.

### Optional Codex Runtime Comparison

If `CODEX_BIN` is configured and `codex` is already authenticated locally, the core runtime scripts (`startup`, `size`, `memory`, `ttft`) will include **Codex CLI** automatically.

Codex is currently treated as a **runtime-only comparison target** in this repo:
- included automatically in the lightweight runtime benchmarks
- **not** yet wired into the long-running task-effectiveness harnesses
- uses its own local Codex auth/session, not `ANTHROPIC_API_KEY`

| Benchmark | Claw (Rust) | Codex CLI | Ratio |
|-----------|-------------|-----------|-------|
| Startup time | **1.2 ms** | 34.5 ms | 29.2x faster |
| Memory (idle) | **4.1 MB** | 46.0 MB | 11.2x less |
| Memory (API call) | **9.9 MB** | 80.8 MB | 8.2x less |
| Response time (TTFT) | **2.1 s** | 5.8 s | 2.7x faster |

### Runtime Overhead (why it's faster)

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Syscalls | **78** | 883 | 11.3x fewer |
| CPU cycles | **3.9M** | 331.3M | 85.2x fewer |
| CPU instructions | **3.1M** | 423.8M | 137.9x fewer |
| Cache misses | **55,650** | 2,434,187 | 43.7x fewer |
| Page faults (--version) | **226** | 20,089 | 88.8x fewer |
| Page faults (API call) | **1,704** | 279,837 | 164.2x fewer |
| File opens | **5** | 19 | 3.8x fewer |
| File reads | **7** | 31 | 4.4x fewer |
| Threads (API call) | **14** | 24 | 1.7x fewer |
| RSS growth (API call) | **5.6 MB** | 312.3 MB | 54.9x less |

> These numbers explain *why* the performance gap exists — not just *that* it exists.
> CPU and page fault benchmarks require `perf_event_paranoid ≤ 2`. See Prerequisites.

### Task Effectiveness (what it can do)

These benchmarks measure whether the CLI tools can successfully complete real-world development tasks. They require Docker, Python, and API keys, and take hours to run.

At the moment, the task-effectiveness scripts are **Claw-first harnesses**:
- `bench-swebench.sh` runs Claw locally and compares against published Claude reference scores
- `bench-terminal.sh` currently runs Claw locally and prints Claude as a published reference score
- `bench-polyglot.sh` currently runs Claw locally only

| Benchmark | Tasks | Measures | Source |
|-----------|-------|----------|--------|
| [SWE-bench Verified](https://swebench.com/) | 500 | Real GitHub issue resolution | princeton-nlp |
| [Terminal-Bench 2.0](https://tbench.ai/) | 89 | Terminal-native task completion | Laude Institute |
| [Aider Polyglot](https://aider.chat/2024/12/21/polyglot.html) | 225 | Multi-language code editing | Aider-AI |

**SWE-bench Sample Results** (3 tasks: flask, requests):

| Task | Claw (Rust) | Claude Code (ref) |
|------|-------------|-------------------|
| pallets/flask-5014 | **Resolved** | ~79.6% overall (Anthropic published) |
| psf/requests-1142 | **Resolved** | |
| psf/requests-1724 | **Resolved** | |
| **Sample score** | **3/3 (100%)** | |

> Full 500-task run pending. Run: `SWEBENCH_TASKS=500 ./bench-swebench.sh`
> These are NOT included in `bench-all.sh` due to long runtime and API cost.

## Benchmarks

| Script | Measures | Tool |
|--------|----------|------|
| `bench-startup.sh` | Cold start time | [hyperfine](https://github.com/sharkdp/hyperfine) |
| `bench-memory.sh` | Peak RSS memory | `/usr/bin/time -v` |
| `bench-ttft.sh` | Time to first response | `date +%s%N` |
| `bench-size.sh` | Binary and install size | `du` |
| `bench-session.sh` | Memory over long session | `ps` polling |
| `bench-syscall.sh` | Syscall count and breakdown | `strace -c` |
| `bench-cpu.sh` | CPU cycles, IPC, cache misses | `perf stat` |
| `bench-io.sh` | File open/read/write counts | `strace -e trace=` |
| `bench-threads.sh` | Thread/process footprint | `/proc/pid/task` |
| `bench-gc.sh` | Page faults, RSS growth | `perf stat` + `/proc` |
| `bench-all.sh` | All runtime benchmarks | — |
| `bench-swebench.sh` | SWE-bench Verified score | Docker + Python |
| `bench-terminal.sh` | Terminal-Bench 2.0 score | Docker + Harbor |
| `bench-polyglot.sh` | Aider Polyglot score | Python + git |

## Prerequisites

```bash
# Core benchmarks
sudo apt install hyperfine bc

# Runtime overhead benchmarks (optional — skipped if missing)
sudo apt install strace linux-tools-common linux-tools-$(uname -r)

# perf may require relaxing paranoid mode:
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid
```

### Task Effectiveness Prerequisites

```bash
# Docker (required for SWE-bench and Terminal-Bench)
# See: https://docs.docker.com/get-docker/

# Python 3.10+ with venv
sudo apt install python3-venv

# Harnesses are auto-installed on first run
# Disk space: ~50GB for SWE-bench, ~20GB for Terminal-Bench
```

## Quick Start

```bash
git clone https://github.com/devswha/claw-bench.git
cd claw-bench

# Configure paths and API key
cp env.example.sh env.sh
vi env.sh

# Run the runtime suite
./bench-all.sh

# Or run individually
./bench-startup.sh
./bench-memory.sh
```

## Configuration

Edit `env.sh` (never committed — gitignored):

```bash
CLAW_BIN="$HOME/workspace/claw-code/rust/target/release/claw"
CLAUDE_BIN="$(which claude)"
CODEX_BIN="$(which codex)"
API_KEY="your-anthropic-api-key"
```

An **Anthropic API key** is required to run the TTFT, memory (API call), and session benchmarks. Get one at [console.anthropic.com](https://console.anthropic.com/).

Codex does **not** use `ANTHROPIC_API_KEY` in this repo; it relies on your existing `codex login` session.

## Security

- `env.sh` is gitignored and never committed
- API keys are exported in subshells only — automatically cleaned up on exit
- Binary paths are validated before execution
- Runtime benchmarks do not intentionally persist result files, but task-effectiveness harnesses clone repos, create virtualenvs, and write timestamped results under `swebench/results/`, `terminal-bench/results/`, and `polyglot/results/`

## License

MIT
