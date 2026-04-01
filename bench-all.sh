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
