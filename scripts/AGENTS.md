<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# scripts

## Purpose
Build and utility scripts for the project. Contains code coverage collection and gating infrastructure used by CI.

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `coverage/` | Test coverage collection and threshold enforcement scripts |
| `hooks/` | Git hook installer (`install-hooks.sh`) — points `core.hooksPath` at `.githooks/` |

## For AI Agents

### Working In This Directory
- Scripts are invoked by GitHub Actions workflows — changes here affect CI directly.
- All scripts use `set -euo pipefail`. Maintain this convention in any new scripts.
- New scripts must be executable (`chmod +x`) before committing.
- Place new scripts in a purpose-named subdirectory rather than at the `scripts/` root.

<!-- MANUAL: -->
