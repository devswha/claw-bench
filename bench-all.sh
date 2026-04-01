#!/usr/bin/env bash
# Run the stable runtime benchmark core
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

run_benchmark() {
    local script="$1"

    "$DIR/$script"

    echo ""
    echo "----------------------------------------"
    echo ""
}

echo "========================================"
echo "  Claw Code Stable Runtime Benchmarks"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""
echo "Default suite:"
echo "  - startup"
echo "  - install size"
echo "  - idle memory"
echo ""
echo "Experimental scripts remain available for manual runs:"
echo "  bench-ttft.sh bench-session.sh bench-syscall.sh bench-cpu.sh"
echo "  bench-io.sh bench-threads.sh bench-gc.sh"
echo ""

for script in \
    bench-startup.sh \
    bench-size.sh \
    bench-memory.sh
do
    run_benchmark "$script"
done

echo "========================================"
echo "  Stable benchmark complete"
echo "========================================"
