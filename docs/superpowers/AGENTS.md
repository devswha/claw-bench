<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-02 | Updated: 2026-04-02 -->

# superpowers

## Purpose
AI-assisted planning and design artifacts generated during project development. Contains implementation plans and technical design specifications for the benchmark suite.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `plans/` | Step-by-step implementation plans |
| `specs/` | Technical design specifications |

## Key Files

### plans/
| File | Description |
|------|-------------|
| `2026-04-01-runtime-overhead-benchmarks.md` | Implementation plan for the stable runtime overhead benchmarks |
| `2026-04-01-task-effectiveness-benchmarks.md` | Implementation plan for SWE-bench, Terminal-Bench, and Polyglot harnesses |

### specs/
| File | Description |
|------|-------------|
| `2026-04-01-runtime-overhead-benchmarks-design.md` | Design spec for startup, size, and memory benchmarks |
| `2026-04-01-task-effectiveness-benchmarks-design.md` | Design spec for task-effectiveness benchmark harnesses |
| `2026-04-03-layered-benchmark-suite-design.md` | Roadmap proposal for a future layered benchmark suite |

## For AI Agents

### Working In This Directory
- These are reference documents capturing design decisions made during initial development.
- Current-state benchmark truth lives in `README.md` plus runnable scripts such as `bench-all.sh` and `experimental/*.sh`.
- Files in this directory are roadmap/history/reference unless a document is explicitly promoted to authoritative status.
- Plans describe the "what and when"; specs describe the "how and why".
- Do not modify these files unless explicitly updating the project design.
- New plans/specs should follow the naming convention: `YYYY-MM-DD-<topic>.md`.

<!-- MANUAL: -->
