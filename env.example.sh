#!/usr/bin/env bash
# Copy to env.sh and edit with your paths
# WARNING: Never commit env.sh — it contains your API key

# Binary paths
CLAW_BIN="$HOME/workspace/claw-code/rust/target/release/claw"
CLAUDE_BIN="$(which claude 2>/dev/null || echo '/usr/local/bin/claude')"
# Optional Codex CLI (uses local Codex login/auth, not ANTHROPIC_API_KEY)
CODEX_BIN="$(which codex 2>/dev/null || echo '')"
CODEX_MODEL="gpt-5.3-codex"

# Anthropic API settings for experimental API-path / task-harness benchmarks
# (the stable default suite does not need these)
API_BASE_URL="https://api.anthropic.com"
API_KEY="REPLACE_ME_WITH_YOUR_API_KEY"

# Stable suite settings
HYPERFINE_WARMUP=3
HYPERFINE_RUNS=10

# Experimental benchmark settings
API_CALL_TIMEOUT=45      # seconds for API-path benchmarks that may linger on helper processes
SESSION_DURATION=60        # seconds for long session benchmark
SESSION_POLL_INTERVAL=1    # seconds between RSS samples during session benchmark

# Experimental profiling benchmark settings
STRACE_FOLLOW_FORKS=true                  # trace child processes (-f flag)
PERF_EVENTS="cycles,instructions,cache-misses,cache-references,branch-misses,page-faults"
GC_POLL_INTERVAL=0.1                      # seconds between /proc RSS samples

# Task effectiveness benchmark settings
SWEBENCH_TASKS=500                        # number of SWE-bench Verified tasks (max 500)
SWEBENCH_TIMEOUT=300                      # seconds per task
SWEBENCH_MODEL="claude-sonnet-4-5-20250514"  # model for API-based runs
TB2_TASKS=89                              # Terminal-Bench 2.0 tasks (max 89)
TB2_MAX_TURNS=100                         # max terminal turns per task
POLYGLOT_LANGUAGES="python,javascript,go,rust,java,cpp"  # Aider polyglot languages
POLYGLOT_MAX_ATTEMPTS=2                   # attempts per problem (2 = includes self-repair)
