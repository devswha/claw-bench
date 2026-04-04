# Runtime Overhead Dissection Benchmarks — Design Spec

**Date**: 2026-04-01
**Status**: Historical Reference (Draft)
**Role**: Historical Reference
**Authority**: Non-authoritative design note. Current-state truth lives in `README.md` plus runnable scripts (`bench-all.sh`, `experimental/*.sh`).
**Relationship**: Retained as April 1 design context. Later layered-suite roadmap direction appears in `docs/superpowers/specs/2026-04-03-layered-benchmark-suite-design.md`.
**Purpose**: Add 5 new benchmarks that structurally decompose Node.js runtime overhead vs Rust native binary performance.

> **Current-state note:** This design captures an earlier direction. In the current repo, `bench-all.sh` still runs only the stable core (`startup`, `size`, `memory`), while the profiling scripts live under `experimental/`.

## Context

claw-bench currently measures: startup time, memory (idle/API), TTFT, binary size, and session memory. These show *what* is faster but not *why*.

The new benchmarks target the **root causes** of the performance gap — syscall volume, CPU efficiency, file I/O, thread footprint, and memory allocation pressure. This serves two audiences:

1. **Promotional**: Clear, quotable ratios (e.g., "96x fewer syscalls")
2. **Technical decision-makers**: Structural evidence for Node.js vs Rust CLI architecture choices

## Design Constraints

- Maintain current lightweight bash harness style
- No result persistence or CI integration
- Linux profiling tools allowed: `strace`, `perf`
- No language-specific instrumentation (no `--trace-gc`, no `cargo flamegraph`)
- Each script is self-contained, follows existing conventions

## New Benchmarks

### 1. `bench-syscall.sh` — System Call Profiling

**Rationale**: Node.js V8 initialization, libuv event loop, and module loading generate orders of magnitude more syscalls than a Rust binary.

**Method**:
- `strace -c -f $BIN --version` → syscall count/type summary (idle)
- `strace -c -f $BIN -p 'say hi' --max-turns 1` → syscall count (API call)
- `-f` flag traces child processes/threads

**Output**:
```
=== Syscall Count (--version) ===
         Claw      Claude     Ratio
Total    45        4,312      96x

=== Top Syscalls by Count (Claude, --version) ===
  read     1,847  (module loading)
  openat     892  (file resolution)
  mmap       634  (memory allocation)
```

### 2. `bench-cpu.sh` — CPU Hardware Counters

**Rationale**: IPC (Instructions Per Cycle) and cache miss rate are the most objective measures of runtime execution efficiency.

**Method**:
- `perf stat -e cycles,instructions,cache-misses,cache-references,branch-misses $BIN --version`
- Same command for API call scenario

**Output**:
```
=== CPU Counters (--version) ===
              Claw         Claude      Ratio
Instructions  1.2M         89M         74x
Cycles        0.8M         112M        140x
IPC           1.50         0.79        1.9x
Cache miss %  0.1%         3.2%        32x
```

### 3. `bench-io.sh` — File I/O Overhead

**Rationale**: Node.js `require()` chains open and read hundreds of files. A Rust single binary skips this entirely.

**Method**:
- `strace -e trace=openat,read,write -f $BIN --version 2>&1` → count I/O syscalls
- Separate counts for `openat` (file opens), `read`, `write`

**Output**:
```
=== File I/O (--version) ===
         Claw     Claude     Ratio
open()   12       847        71x
read()   18       1,923      107x
write()  3        42         14x
```

### 4. `bench-threads.sh` — Thread/Process Footprint

**Rationale**: Node.js spawns libuv worker thread pool (default 4) + V8 compiler threads. This causes resource contention when running multiple instances in CI/server environments.

**Method**:
- Start process, then `ls /proc/$PID/task | wc -l` → thread count
- `ps --no-headers -o nlwp -p $PID` → lightweight process count
- Measure in both idle and API call scenarios

**Output**:
```
=== Thread Count ===
              Claw    Claude    Ratio
Idle          2       11        5.5x
API call      3       14        4.7x
```

### 5. `bench-gc.sh` — GC / Memory Allocation Pressure

**Rationale**: V8 GC causes stop-the-world pauses that affect response latency. Rust has no GC, so this overhead is zero.

**Method**:
- `perf stat -e page-faults,minor-faults,major-faults $BIN -p 'say hi' --max-turns 1`
- Sample `/proc/$PID/status` (VmRSS, VmPeak) every 100ms during API call to track memory growth pattern
- Compare page fault counts as proxy for allocation pressure

**Output**:
```
=== Memory Allocation Pressure (API call) ===
                Claw       Claude     Ratio
Page faults     312        8,941      29x
Peak RSS        10 MB      321 MB     32x
RSS growth      +2 MB      +129 MB    65x
```

## Script Conventions

All new scripts follow the existing pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

# Binary validation
[[ -x "$CLAW_BIN" ]]   || { echo "Claw binary not found"; exit 1; }
[[ -x "$CLAUDE_BIN" ]] || { echo "Claude binary not found"; exit 1; }

# Tool dependency check
command -v strace &>/dev/null || { echo "strace required: apt install strace"; exit 1; }
command -v perf &>/dev/null   || { echo "perf required: apt install linux-tools-$(uname -r)"; exit 1; }

# Measure → Output with ratio
```

Every output includes a **Ratio** column for immediate promotional use.

## Additional Dependencies

| Package | Purpose | Install |
|---|---|---|
| `strace` | Syscall and I/O tracing | `apt install strace` |
| `linux-tools-common` | `perf stat` CPU counters | `apt install linux-tools-$(uname -r)` |

## Configuration Additions (`env.example.sh`)

```bash
# New variables (added to existing config)
STRACE_FOLLOW_FORKS=true
PERF_EVENTS="cycles,instructions,cache-misses,cache-references,branch-misses,page-faults"
```

## File Structure (after implementation)

```
claw-bench/
├── bench-startup.sh      # existing
├── bench-memory.sh       # existing
├── bench-ttft.sh         # existing
├── bench-size.sh         # existing
├── bench-session.sh      # existing
├── bench-syscall.sh      # NEW
├── bench-cpu.sh          # NEW
├── bench-io.sh           # NEW
├── bench-threads.sh      # NEW
├── bench-gc.sh           # NEW
├── bench-all.sh          # existing — add calls to 5 new scripts
├── env.example.sh        # add new variables
└── README.md             # document new benchmarks
```

## `bench-all.sh` Update

Add new scripts to the orchestration, in order:
1. Existing benchmarks (startup, memory, ttft, size, session)
2. New benchmarks (syscall, cpu, io, threads, gc)

Each new benchmark is optional — if `strace` or `perf` is missing, print a warning and skip rather than failing.

## Future Work

- **Anthropic Claude Code Benchmarking Methodology**: Incorporate evaluation approaches used by Anthropic for Claude Code (e.g., SWE-bench task completion, terminal-bench, code generation accuracy benchmarks). This would shift from pure runtime performance to **task-level effectiveness** comparison.

## Prerequisites Note (README update)

Add to prerequisites section:
```
# Required for runtime overhead benchmarks
sudo apt install strace linux-tools-common linux-tools-$(uname -r)

# perf may require:
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid
```
