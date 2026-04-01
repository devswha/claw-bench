#!/usr/bin/env bash
# Benchmark: Binary / install size
set -euo pipefail
source "$(dirname "$0")/env.sh"

find_parent_with_file() {
    local dir="$1"
    local file="$2"

    while [ "$dir" != "/" ]; do
        if [ -f "$dir/$file" ]; then
            printf "%s\n" "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

has_codex=false
if [ -n "${CODEX_BIN:-}" ] && [ -x "${CODEX_BIN:-}" ]; then
    has_codex=true
fi

echo "=== Install Size Benchmark ==="
echo ""

for bin in "$CLAW_BIN" "$CLAUDE_BIN"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: Binary not found or not executable: $bin" >&2
        exit 1
    fi
done

echo "--- Binary size ---"
printf "%-12s %s\n" "Claw" "$(du -sh "$CLAW_BIN" | cut -f1)"

claude_real=$(readlink -f "$CLAUDE_BIN" 2>/dev/null || echo "$CLAUDE_BIN")
printf "%-12s %s\n" "Claude" "$(du -sh "$claude_real" | cut -f1)"
if [ "$has_codex" = true ]; then
    codex_real=$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")
    printf "%-12s %s\n" "Codex" "$(du -sh "$codex_real" | cut -f1)"
fi

echo ""
echo "--- Total install footprint ---"
printf "%-12s %s  (standalone binary)\n" "Claw" "$(du -sh "$CLAW_BIN" | cut -f1)"

claude_dir=$(dirname "$claude_real")
if [ -d "$claude_dir/../lib" ]; then
    printf "%-12s %s  (bin + lib)\n" "Claude" "$(du -sh "$claude_dir/.." | cut -f1)"
elif [ -d "$claude_dir/../node_modules" ]; then
    printf "%-12s %s  (with node_modules)\n" "Claude" "$(du -sh "$claude_dir/.." | cut -f1)"
else
    printf "%-12s %s  (binary only, node_modules elsewhere)\n" "Claude" "$(du -sh "$claude_real" | cut -f1)"
fi

if [ "$has_codex" = true ]; then
    codex_pkg_root=$(cd "$(dirname "$codex_real")/.." && pwd)
    printf "%-12s %s  (global npm package)\n" "Codex" "$(du -sh "$codex_pkg_root" | cut -f1)"
fi

echo ""
echo "--- Dependency count ---"
claw_workspace=$(find_parent_with_file "$(dirname "$CLAW_BIN")" Cargo.toml || true)
if [ -n "${claw_workspace:-}" ]; then
    claw_deps=$(cd "$claw_workspace" && cargo metadata --format-version 1 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['packages']))" 2>/dev/null || echo "N/A")
else
    claw_deps="N/A"
fi
printf "%-12s %s Cargo crates\n" "Claw" "$claw_deps"

claude_npm_root="$claude_dir/.."
if [ -d "$claude_npm_root/node_modules" ]; then
    claude_deps=$(find "$claude_npm_root/node_modules" -maxdepth 1 -type d | wc -l)
    printf "%-12s %s npm packages\n" "Claude" "$claude_deps"
else
    printf "%-12s %s\n" "Claude" "N/A (node_modules not found)"
fi

if [ "$has_codex" = true ]; then
    if [ -d "$codex_pkg_root/node_modules" ]; then
        codex_deps=$(find "$codex_pkg_root/node_modules" -maxdepth 1 -type d | wc -l)
        printf "%-12s %s npm packages\n" "Codex" "$codex_deps"
    else
        printf "%-12s %s\n" "Codex" "N/A (node_modules not found)"
    fi
fi
