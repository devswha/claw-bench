#!/usr/bin/env bash
# Copy to env.sh and edit with your paths
# WARNING: Never commit env.sh — it contains your API key

# Binary paths
CLAW_BIN="$HOME/workspace/claw-code/rust/target/release/claw"
CLAUDE_BIN="$(which claude 2>/dev/null || echo '/usr/local/bin/claude')"

# Anthropic API key (get one at console.anthropic.com)
API_BASE_URL="https://api.anthropic.com"
API_KEY="REPLACE_ME_WITH_YOUR_API_KEY"

# Benchmark settings
HYPERFINE_WARMUP=3
HYPERFINE_RUNS=10
SESSION_DURATION=60        # seconds for long session benchmark
SESSION_POLL_INTERVAL=1    # pidstat interval

# Runtime overhead benchmark settings
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
