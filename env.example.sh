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
