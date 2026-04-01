# claw-bench

Benchmark suite comparing **Claw Code** (Rust single-binary CLI) vs **Claude Code** (Node.js CLI).

Inspired by [claw-code](https://github.com/devswha/claw-code).

## Sample Results

Measured on Ubuntu 24.04 (Linux 6.8), same machine, same API endpoint.

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Startup time | **1.3 ms** | 120.4 ms | 91x faster |
| Binary size | **13 MB** | 218 MB | 17x smaller |
| Memory (idle) | **4.0 MB** | 191.7 MB | 48x less |

> Results vary by machine, network, and API provider. Run your own benchmarks.

### Runtime Overhead (why it's faster)

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Syscalls | **78** | 1,476 | 18.9x fewer |
| CPU cycles | **4.7M** | 387.9M | 83x fewer |
| CPU instructions | **3.0M** | 423.6M | 139x fewer |
| Cache misses | **54,684** | 2,512,171 | 45.9x fewer |
| Page faults | **228** | 20,149 | 88x fewer |
| File opens | **5** | 19 | 3.8x fewer |
| File reads | **7** | 31 | 4.4x fewer |
| Threads (API call) | — | 19 | — |

> These numbers explain *why* the performance gap exists — not just *that* it exists.
> CPU and page fault benchmarks require `perf_event_paranoid ≤ 2`. See Prerequisites.

### Task Effectiveness (what it can do)

These benchmarks measure whether the CLI tools can successfully complete real-world development tasks. They require Docker, Python, and API keys, and take hours to run.

| Benchmark | Tasks | Measures | Source |
|-----------|-------|----------|--------|
| [SWE-bench Verified](https://swebench.com/) | 500 | Real GitHub issue resolution | princeton-nlp |
| [Terminal-Bench 2.0](https://tbench.ai/) | 89 | Terminal-native task completion | Laude Institute |
| [Aider Polyglot](https://aider.chat/2024/12/21/polyglot.html) | 225 | Multi-language code editing | Aider-AI |

> Run individually: `./bench-swebench.sh`, `./bench-terminal.sh`, `./bench-polyglot.sh`
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
sudo apt install hyperfine sysstat

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

# Run all benchmarks
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
API_KEY="your-anthropic-api-key"
```

An **Anthropic API key** is required to run the TTFT, memory (API call), and session benchmarks. Get one at [console.anthropic.com](https://console.anthropic.com/).

## Security

- `env.sh` is gitignored and never committed
- API keys are exported in subshells only — automatically cleaned up on exit
- Binary paths are validated before execution
- No temporary files written to disk

## License

MIT
