#!/usr/bin/env bash
# Benchmark: Cold start time (--version)
set -euo pipefail
source "$(dirname "$0")/env.sh"

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

echo "=== Startup Time Benchmark ==="
echo ""

if ! command -v hyperfine &>/dev/null; then
    echo "hyperfine not found. Install: sudo apt install hyperfine"
    exit 1
fi

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

echo "Comparing: --version cold start"
echo "  Claw:   $CLAW_BIN"
echo "  Claude: $CLAUDE_BIN"
if [ "$has_codex" = true ]; then
    echo "  Codex:  $CODEX_BIN"
fi
echo ""

commands=(
    "$CLAW_BIN --version"
    "$CLAUDE_BIN --version"
)

if [ "$has_codex" = true ]; then
    commands+=("$CODEX_BIN --version")
fi

hyperfine \
    --warmup "$HYPERFINE_WARMUP" \
    --runs "$HYPERFINE_RUNS" \
    --export-markdown /dev/stdout \
    "${commands[@]}"
