#!/usr/bin/env bash
# Run all benchmarks
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

run_required_benchmark() {
    local script="$1"

    "$DIR/$script"

    echo ""
    echo "----------------------------------------"
    echo ""
}

run_optional_benchmark() {
    local script="$1"

    if "$DIR/$script"; then
        :
    else
        local rc=$?
        echo "[WARN] $script failed or skipped (exit $rc)"
    fi

    echo ""
    echo "----------------------------------------"
    echo ""
}

echo "========================================"
echo "  Claw Code vs Claude Code Benchmark"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

for script in \
    bench-startup.sh \
    bench-size.sh \
    bench-memory.sh \
    bench-ttft.sh \
    bench-session.sh
do
    run_required_benchmark "$script"
done

for script in \
    bench-syscall.sh \
    bench-cpu.sh \
    bench-io.sh \
    bench-threads.sh \
    bench-gc.sh
do
    run_optional_benchmark "$script"
done

echo "========================================"
echo "  Benchmark complete"
echo "========================================"
