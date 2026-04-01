# claw-bench

Benchmark suite comparing **Claw Code** (Rust single-binary CLI) vs **Claude Code** (Node.js CLI).

Inspired by [claw-code](https://github.com/devswha/claw-code).

## Sample Results

Measured on Ubuntu 24.04 (Linux 6.8), same machine, same API endpoint.

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Startup time | **2.9 ms** | 110 ms | 38x faster |
| Binary size | **13 MB** | 218 MB | 17x smaller |
| Memory (idle) | **4 MB** | 192 MB | 47x less |
| Memory (API call) | **10 MB** | 321 MB | 31x less |
| Response time | **3.1 s** | 11.2 s | 3.6x faster |

> Results vary by machine, network, and API provider. Run your own benchmarks.

### Runtime Overhead (why it's faster)

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Syscalls (--version) | **78** | 731 | 9.3x fewer |
| File opens (--version) | **5** | 19 | 3.8x fewer |
| File reads (--version) | **7** | 31 | 4.4x fewer |
| File opens (API call) | **181** | 55,592 | 307x fewer |
| File reads (API call) | **131** | 35,359 | 270x fewer |
| Threads (API call) | — | 18 | — |
| CPU instructions | — | — | *requires `perf` access* |
| Page faults | — | — | *requires `perf` access* |

> These numbers explain *why* the performance gap exists — not just *that* it exists.
> CPU and page fault benchmarks require `perf_event_paranoid ≤ 2`. See Prerequisites.

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
| `bench-all.sh` | All of the above | — |

## Prerequisites

```bash
# Core benchmarks
sudo apt install hyperfine sysstat

# Runtime overhead benchmarks (optional — skipped if missing)
sudo apt install strace linux-tools-common linux-tools-$(uname -r)

# perf may require relaxing paranoid mode:
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid
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
