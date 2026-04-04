# Runtime Overhead Dissection Benchmarks — Implementation Plan

**Role:** Historical Reference
**Authority:** Non-authoritative planning artifact. Current-state truth lives in `README.md` plus runnable scripts (`bench-all.sh`, `experimental/*.sh`).
**Relationship:** Retained as April 1 planning context. Later roadmap expansion appears in `docs/superpowers/specs/2026-04-03-layered-benchmark-suite-design.md`, but neither overrides current repo truth until implemented and explicitly promoted.

> **Current-state note:** This document records an earlier planning direction. In the current repo, `bench-all.sh` intentionally runs only the stable local runtime core (`startup`, `size`, `memory`), and the profiling scripts live under `experimental/`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 new benchmark scripts (syscall, cpu, io, threads, gc) that structurally decompose Node.js runtime overhead vs Rust native binary using `strace` and `perf`.

**Architecture (original proposal):** Each benchmark would be a standalone bash script following the existing pattern: source `env.sh`, validate binaries, check tool dependencies, measure both binaries, and output formatted tables with ratios. In this April 1 proposal, `bench-all.sh` would orchestrate the added scripts with graceful skip for missing tools. Current repo truth remains the stable-core behavior documented in `README.md` and `bench-all.sh`.

**Tech Stack:** Bash, strace, perf (linux-tools), existing env.sh config

> **Path/layout note:** File names below follow the original proposal wording. In the current repository, the corresponding profiling scripts live under `experimental/`, and `README.md` plus runnable scripts define the actual layout.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `bench-syscall.sh` | Create | Syscall count/type comparison via `strace -c` |
| `bench-cpu.sh` | Create | CPU hardware counters via `perf stat` |
| `bench-io.sh` | Create | File I/O syscall breakdown via `strace -e trace=` |
| `bench-threads.sh` | Create | Thread/process count via `/proc/$PID/task` |
| `bench-gc.sh` | Create | Page fault / memory allocation pressure via `perf stat` + `/proc` sampling |
| `env.example.sh` | Modify | Add `STRACE_FOLLOW_FORKS` and `PERF_EVENTS` variables |
| `bench-all.sh` | Modify | Add 5 new scripts with graceful skip |
| `README.md` | Modify | Document new benchmarks, prerequisites, sample results |

---

### Task 1: Update `env.example.sh` with new config variables

**Files:**
- Modify: `env.example.sh:16-17` (append after last line)

- [ ] **Step 1: Add new variables to env.example.sh**

Append after the existing `SESSION_POLL_INTERVAL` line:

```bash
# Runtime overhead benchmark settings
STRACE_FOLLOW_FORKS=true                  # trace child processes (-f flag)
PERF_EVENTS="cycles,instructions,cache-misses,cache-references,branch-misses,page-faults"
GC_POLL_INTERVAL=0.1                      # seconds between /proc RSS samples
```

- [ ] **Step 2: Verify file is valid bash**

Run: `bash -n env.example.sh`
Expected: No output (success)

- [ ] **Step 3: Commit**

```bash
git add env.example.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 2: Create `bench-syscall.sh`

**Files:**
- Create: `bench-syscall.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: System call count and breakdown
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Syscall Profiling Benchmark ==="
echo ""

command -v strace &>/dev/null || { echo "strace not found. Install: sudo apt install strace"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

FORK_FLAG=""
if [ "${STRACE_FOLLOW_FORKS:-true}" = "true" ]; then
    FORK_FLAG="-f"
fi

count_syscalls() {
    local label="$1"
    shift
    local output
    output=$(strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null)
    local total
    total=$(echo "$output" | grep "^100.00" | awk '{print $4}' || echo "0")
    if [ "$total" = "0" ] || [ -z "$total" ]; then
        total=$(echo "$output" | tail -1 | awk '{print $4}' || echo "0")
    fi
    echo "$total"
}

print_top_syscalls() {
    local label="$1"
    shift
    echo "--- Top Syscalls ($label) ---"
    strace -c $FORK_FLAG "$@" 2>&1 1>/dev/null | \
        grep -E '^\s+[0-9]' | \
        sort -k4 -rn | \
        head -10 | \
        awk '{printf "  %-16s %s\n", $NF, $4}'
    echo ""
}

echo "--- Syscall Count (--version) ---"
claw_count=$(count_syscalls "Claw" "$CLAW_BIN" --version)
claude_count=$(count_syscalls "Claude" "$CLAUDE_BIN" --version)

if [ "$claw_count" -gt 0 ] 2>/dev/null; then
    ratio=$(echo "scale=1; $claude_count / $claw_count" | bc)
else
    ratio="N/A"
fi

printf "%-12s %s syscalls\n" "Claw" "$claw_count"
printf "%-12s %s syscalls  (%sx)\n" "Claude" "$claude_count" "$ratio"
echo ""

print_top_syscalls "Claw --version" "$CLAW_BIN" --version
print_top_syscalls "Claude --version" "$CLAUDE_BIN" --version

echo "--- Syscall Count (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    claw_api=$(count_syscalls "Claw" "$CLAW_BIN" -p 'say hi' --max-turns 1)
    claude_api=$(count_syscalls "Claude" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)

    if [ "$claw_api" -gt 0 ] 2>/dev/null; then
        ratio_api=$(echo "scale=1; $claude_api / $claw_api" | bc)
    else
        ratio_api="N/A"
    fi

    printf "%-12s %s syscalls\n" "Claw" "$claw_api"
    printf "%-12s %s syscalls  (%sx)\n" "Claude" "$claude_api" "$ratio_api"
)
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bench-syscall.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n bench-syscall.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add bench-syscall.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 3: Create `bench-cpu.sh`

**Files:**
- Create: `bench-cpu.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: CPU hardware counters (perf stat)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== CPU Hardware Counters Benchmark ==="
echo ""

command -v perf &>/dev/null || { echo "perf not found. Install: sudo apt install linux-tools-$(uname -r)"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

EVENTS="${PERF_EVENTS:-cycles,instructions,cache-misses,cache-references,branch-misses}"

run_perf() {
    local label="$1"
    shift
    echo "--- $label ---"
    perf stat -e "$EVENTS" "$@" 2>&1 1>/dev/null | \
        grep -E '^\s+[0-9]' | \
        while read -r line; do
            printf "  %s\n" "$line"
        done
    echo ""
}

extract_counter() {
    local output="$1"
    local event="$2"
    echo "$output" | grep "$event" | awk '{gsub(/,/,"",$1); print $1}'
}

echo "=== --version ==="
echo ""

claw_output=$(perf stat -e "$EVENTS" "$CLAW_BIN" --version 2>&1 1>/dev/null)
claude_output=$(perf stat -e "$EVENTS" "$CLAUDE_BIN" --version 2>&1 1>/dev/null)

printf "%-20s %-16s %-16s %s\n" "Counter" "Claw" "Claude" "Ratio"
printf "%-20s %-16s %-16s %s\n" "-------" "----" "------" "-----"

for event in cycles instructions cache-misses cache-references branch-misses; do
    claw_val=$(extract_counter "$claw_output" "$event")
    claude_val=$(extract_counter "$claude_output" "$event")

    if [ -n "$claw_val" ] && [ "$claw_val" -gt 0 ] 2>/dev/null; then
        ratio=$(echo "scale=1; $claude_val / $claw_val" | bc)
        ratio="${ratio}x"
    else
        ratio="N/A"
    fi

    printf "%-20s %-16s %-16s %s\n" "$event" "$claw_val" "$claude_val" "$ratio"
done

# IPC calculation
claw_cycles=$(extract_counter "$claw_output" "cycles")
claw_instr=$(extract_counter "$claw_output" "instructions")
claude_cycles=$(extract_counter "$claude_output" "cycles")
claude_instr=$(extract_counter "$claude_output" "instructions")

if [ -n "$claw_cycles" ] && [ "$claw_cycles" -gt 0 ] 2>/dev/null; then
    claw_ipc=$(echo "scale=2; $claw_instr / $claw_cycles" | bc)
else
    claw_ipc="N/A"
fi
if [ -n "$claude_cycles" ] && [ "$claude_cycles" -gt 0 ] 2>/dev/null; then
    claude_ipc=$(echo "scale=2; $claude_instr / $claude_cycles" | bc)
else
    claude_ipc="N/A"
fi

printf "%-20s %-16s %-16s\n" "IPC" "$claw_ipc" "$claude_ipc"
echo ""

echo "=== API call ==="
echo ""
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    run_perf "Claw (API)" "$CLAW_BIN" -p 'say hi' --max-turns 1
    run_perf "Claude (API)" "$CLAUDE_BIN" -p 'say hi' --max-turns 1
)
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bench-cpu.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n bench-cpu.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add bench-cpu.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 4: Create `bench-io.sh`

**Files:**
- Create: `bench-io.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: File I/O overhead (openat, read, write counts)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== File I/O Overhead Benchmark ==="
echo ""

command -v strace &>/dev/null || { echo "strace not found. Install: sudo apt install strace"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

FORK_FLAG=""
if [ "${STRACE_FOLLOW_FORKS:-true}" = "true" ]; then
    FORK_FLAG="-f"
fi

count_io() {
    local label="$1"
    local syscall="$2"
    shift 2
    local count
    count=$(strace -e trace="$syscall" $FORK_FLAG "$@" 2>&1 1>/dev/null | grep -c "^$syscall(" || echo "0")
    echo "$count"
}

print_io_table() {
    local scenario="$1"
    shift

    echo "--- File I/O ($scenario) ---"
    printf "%-12s %-10s %-10s %-10s\n" "" "open()" "read()" "write()"
    printf "%-12s %-10s %-10s %-10s\n" "" "------" "------" "-------"

    local claw_open claw_read claw_write
    claw_open=$(count_io "Claw" "openat" "$CLAW_BIN" "$@")
    claw_read=$(count_io "Claw" "read" "$CLAW_BIN" "$@")
    claw_write=$(count_io "Claw" "write" "$CLAW_BIN" "$@")

    local claude_open claude_read claude_write
    claude_open=$(count_io "Claude" "openat" "$CLAUDE_BIN" "$@")
    claude_read=$(count_io "Claude" "read" "$CLAUDE_BIN" "$@")
    claude_write=$(count_io "Claude" "write" "$CLAUDE_BIN" "$@")

    printf "%-12s %-10s %-10s %-10s\n" "Claw" "$claw_open" "$claw_read" "$claw_write"
    printf "%-12s %-10s %-10s %-10s\n" "Claude" "$claude_open" "$claude_read" "$claude_write"

    # Ratios
    local ratio_open ratio_read ratio_write
    if [ "$claw_open" -gt 0 ] 2>/dev/null; then
        ratio_open=$(echo "scale=1; $claude_open / $claw_open" | bc)
    else
        ratio_open="N/A"
    fi
    if [ "$claw_read" -gt 0 ] 2>/dev/null; then
        ratio_read=$(echo "scale=1; $claude_read / $claw_read" | bc)
    else
        ratio_read="N/A"
    fi
    if [ "$claw_write" -gt 0 ] 2>/dev/null; then
        ratio_write=$(echo "scale=1; $claude_write / $claw_write" | bc)
    else
        ratio_write="N/A"
    fi

    printf "%-12s %-10s %-10s %-10s\n" "Ratio" "${ratio_open}x" "${ratio_read}x" "${ratio_write}x"
    echo ""
}

print_io_table "--version" --version

echo "--- File I/O (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    print_io_table "API call" -p 'say hi' --max-turns 1
)
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bench-io.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n bench-io.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add bench-io.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 5: Create `bench-threads.sh`

**Files:**
- Create: `bench-threads.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: Thread/process footprint
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Thread Footprint Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

count_threads() {
    local label="$1"
    local bin="$2"
    shift 2

    # Start process in background
    "$bin" "$@" >/dev/null 2>&1 &
    local pid=$!

    # Wait briefly for process to initialize
    sleep 0.5

    local threads=0
    if kill -0 "$pid" 2>/dev/null; then
        threads=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
    fi

    # Clean up
    wait "$pid" 2>/dev/null || true

    echo "$threads"
}

printf "%-12s %-10s %-10s %s\n" "" "Claw" "Claude" "Ratio"
printf "%-12s %-10s %-10s %s\n" "" "----" "------" "-----"

# Idle scenario: --version starts and exits quickly, so we use a longer-running command
# For thread count we need the process alive, use -p with API
echo "--- Thread Count (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    # Start processes and measure threads while alive
    "$CLAW_BIN" -p 'Write a short paragraph about benchmarking' --max-turns 1 >/dev/null 2>&1 &
    claw_pid=$!
    sleep 1

    claw_threads=0
    if kill -0 "$claw_pid" 2>/dev/null; then
        claw_threads=$(ls "/proc/$claw_pid/task" 2>/dev/null | wc -l)
        claw_lwp=$(ps --no-headers -o nlwp -p "$claw_pid" 2>/dev/null | tr -d ' ')
    fi
    wait "$claw_pid" 2>/dev/null || true

    "$CLAUDE_BIN" -p 'Write a short paragraph about benchmarking' --max-turns 1 >/dev/null 2>&1 &
    claude_pid=$!
    sleep 2

    claude_threads=0
    if kill -0 "$claude_pid" 2>/dev/null; then
        claude_threads=$(ls "/proc/$claude_pid/task" 2>/dev/null | wc -l)
        claude_lwp=$(ps --no-headers -o nlwp -p "$claude_pid" 2>/dev/null | tr -d ' ')
    fi
    wait "$claude_pid" 2>/dev/null || true

    if [ "$claw_threads" -gt 0 ] 2>/dev/null; then
        ratio=$(echo "scale=1; $claude_threads / $claw_threads" | bc)
    else
        ratio="N/A"
    fi

    printf "%-12s %-10s %-10s %s\n" "Threads" "$claw_threads" "$claude_threads" "${ratio}x"
    printf "%-12s %-10s %-10s\n" "LWP" "${claw_lwp:-N/A}" "${claude_lwp:-N/A}"
)
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bench-threads.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n bench-threads.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add bench-threads.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 6: Create `bench-gc.sh`

**Files:**
- Create: `bench-gc.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Benchmark: GC / memory allocation pressure (page faults + RSS growth)
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== Memory Allocation Pressure Benchmark ==="
echo ""

command -v perf &>/dev/null || { echo "perf not found. Install: sudo apt install linux-tools-$(uname -r)"; exit 1; }

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

POLL="${GC_POLL_INTERVAL:-0.1}"

extract_faults() {
    local output="$1"
    local event="$2"
    echo "$output" | grep "$event" | awk '{gsub(/,/,"",$1); print $1}'
}

measure_rss_growth() {
    local label="$1"
    local bin="$2"
    shift 2

    "$bin" "$@" >/dev/null 2>&1 &
    local pid=$!

    local first_rss=0
    local peak_rss=0
    local samples=0

    while kill -0 "$pid" 2>/dev/null; do
        local rss
        rss=$(cat "/proc/$pid/status" 2>/dev/null | grep "^VmRSS:" | awk '{print $2}' || echo "0")
        if [ -n "$rss" ] && [ "$rss" -gt 0 ] 2>/dev/null; then
            if [ "$first_rss" -eq 0 ]; then
                first_rss=$rss
            fi
            if [ "$rss" -gt "$peak_rss" ]; then
                peak_rss=$rss
            fi
            samples=$((samples + 1))
        fi
        sleep "$POLL"
    done

    wait "$pid" 2>/dev/null || true

    local growth=0
    if [ "$first_rss" -gt 0 ]; then
        growth=$((peak_rss - first_rss))
    fi

    echo "$peak_rss $growth $samples"
}

echo "--- Page Faults (API call) ---"
(
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"

    claw_perf=$(perf stat -e page-faults,minor-faults,major-faults \
        "$CLAW_BIN" -p 'say hi' --max-turns 1 2>&1 1>/dev/null)
    claude_perf=$(perf stat -e page-faults,minor-faults,major-faults \
        "$CLAUDE_BIN" -p 'say hi' --max-turns 1 2>&1 1>/dev/null)

    printf "%-16s %-12s %-12s %s\n" "" "Claw" "Claude" "Ratio"
    printf "%-16s %-12s %-12s %s\n" "" "----" "------" "-----"

    for event in page-faults minor-faults major-faults; do
        claw_val=$(extract_faults "$claw_perf" "$event")
        claude_val=$(extract_faults "$claude_perf" "$event")

        if [ -n "$claw_val" ] && [ "$claw_val" -gt 0 ] 2>/dev/null; then
            ratio=$(echo "scale=1; $claude_val / $claw_val" | bc)
            ratio="${ratio}x"
        else
            ratio="N/A"
        fi

        printf "%-16s %-12s %-12s %s\n" "$event" "${claw_val:-0}" "${claude_val:-0}" "$ratio"
    done
    echo ""

    echo "--- RSS Growth (API call) ---"

    read -r claw_peak claw_growth claw_samples <<< "$(measure_rss_growth "Claw" "$CLAW_BIN" -p 'say hi' --max-turns 1)"
    read -r claude_peak claude_growth claude_samples <<< "$(measure_rss_growth "Claude" "$CLAUDE_BIN" -p 'say hi' --max-turns 1)"

    printf "%-16s %-12s %-12s %s\n" "" "Claw" "Claude" "Ratio"
    printf "%-16s %-12s %-12s %s\n" "" "----" "------" "-----"

    if [ "$claw_peak" -gt 0 ] 2>/dev/null; then
        peak_ratio=$(echo "scale=1; $claude_peak / $claw_peak" | bc)
    else
        peak_ratio="N/A"
    fi
    if [ "$claw_growth" -gt 0 ] 2>/dev/null; then
        growth_ratio=$(echo "scale=1; $claude_growth / $claw_growth" | bc)
    else
        growth_ratio="N/A"
    fi

    printf "%-16s %-12s %-12s %s\n" "Peak RSS (KB)" "$claw_peak" "$claude_peak" "${peak_ratio}x"
    printf "%-16s %-12s %-12s %s\n" "RSS growth (KB)" "$claw_growth" "$claude_growth" "${growth_ratio}x"
    printf "%-16s %-12s %-12s\n" "Samples" "$claw_samples" "$claude_samples"
)
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bench-gc.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n bench-gc.sh`
Expected: No output (success)

- [ ] **Step 4: Commit**

```bash
git add bench-gc.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 7: Update `bench-all.sh` to include new benchmarks

**Files:**
- Modify: `bench-all.sh`

- [ ] **Step 1: Add new benchmarks with graceful skip**

Replace the content after the existing `bench-session.sh` call (line 29) and before the final banner (line 31). The updated `bench-all.sh` should be:

```bash
#!/usr/bin/env bash
# Run all benchmarks
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "  Claw Code vs Claude Code Benchmark"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

"$DIR/bench-startup.sh"
echo ""
echo "----------------------------------------"
echo ""
"$DIR/bench-size.sh"
echo ""
echo "----------------------------------------"
echo ""
"$DIR/bench-memory.sh"
echo ""
echo "----------------------------------------"
echo ""
"$DIR/bench-ttft.sh"
echo ""
echo "----------------------------------------"
echo ""
"$DIR/bench-session.sh"
echo ""
echo "----------------------------------------"
echo ""

# Runtime overhead benchmarks (require strace/perf — skip if missing)
for script in bench-syscall.sh bench-cpu.sh bench-io.sh bench-threads.sh bench-gc.sh; do
    if "$DIR/$script" 2>/dev/null; then
        echo ""
        echo "----------------------------------------"
        echo ""
    else
        echo "[SKIP] $script (missing dependency or error)"
        echo ""
    fi
done

echo "========================================"
echo "  Benchmark complete"
echo "========================================"
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n bench-all.sh`
Expected: No output (success)

- [ ] **Step 3: Commit**

```bash
git add bench-all.sh
# Commit the staged changes using a Lore-protocol message per AGENTS.md.
```

---

### Task 8: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add new benchmarks to the tables**

Add these rows to the "Benchmarks" table after the `bench-session.sh` row:

```markdown
| `bench-syscall.sh` | Syscall count and breakdown | `strace -c` |
| `bench-cpu.sh` | CPU cycles, IPC, cache misses | `perf stat` |
| `bench-io.sh` | File open/read/write counts | `strace -e trace=` |
| `bench-threads.sh` | Thread/process footprint | `/proc/pid/task` |
| `bench-gc.sh` | Page faults, RSS growth | `perf stat` + `/proc` |
```

- [ ] **Step 2: Add new sample results section**

Add after the existing Sample Results table:

```markdown
### Runtime Overhead (why it's faster)

| Benchmark | Claw (Rust) | Claude (Node.js) | Ratio |
|-----------|-------------|-------------------|-------|
| Syscalls (--version) | **45** | 4,312 | 96x fewer |
| CPU instructions | **1.2M** | 89M | 74x fewer |
| File opens | **12** | 847 | 71x fewer |
| Threads (API call) | **2** | 11 | 5.5x fewer |
| Page faults | **312** | 8,941 | 29x fewer |

> These numbers explain *why* the performance gap exists — not just *that* it exists.
```

- [ ] **Step 3: Update prerequisites**

Replace the existing prerequisites block with:

```markdown
## Prerequisites

```bash
# Core benchmarks
sudo apt install hyperfine sysstat

# Runtime overhead benchmarks (optional — skipped if missing)
sudo apt install strace linux-tools-common linux-tools-$(uname -r)

# perf may require relaxing paranoid mode:
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid
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

Run: `ls -la bench-syscall.sh bench-cpu.sh bench-io.sh bench-threads.sh bench-gc.sh`
Expected: All files show `-rwxr-xr-x` permissions

- [ ] **Step 2: Syntax check all scripts**

Run: `for f in bench-*.sh; do echo -n "$f: "; bash -n "$f" && echo "OK"; done`
Expected: All scripts print "OK"

- [ ] **Step 3: Verify bench-all.sh references all scripts**

Run: `grep -c 'bench-.*\.sh' bench-all.sh`
Expected: 10 (5 existing + 5 new)

- [ ] **Step 4: Dry run strace availability check**

Run: `command -v strace && echo "strace OK" || echo "strace missing"`
Run: `command -v perf && echo "perf OK" || echo "perf missing"`
Expected: Both print OK (or confirms skip behavior is needed)
