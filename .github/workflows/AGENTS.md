<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# .github/workflows

## Purpose
GitHub Actions CI/CD workflows. Runs on every pull request and on pushes to `main`.

## Key Files
| File | Description |
|------|-------------|
| `coverage-gates.yml` | Runs `scripts/coverage/collect-and-gate.sh` on macOS 15, uploads coverage artifacts, enforces per-target line coverage thresholds |

## For AI Agents

### Working In This Directory
- The single job uses `macos-15` and has a 120-minute timeout.
- Coverage thresholds are not defined here — they live as environment variable defaults in `scripts/coverage/collect-and-gate.sh` (`IOS_APP_FLOOR`, `MACOS_APP_FLOOR`, `NETMONITORCORE_FLOOR`, `NETWORKSCANKIT_FLOOR`). To change a threshold, edit the script, not this file.
- Artifacts uploaded on every run (including failures): `build/coverage/coverage-summary.json`, `build/coverage/coverage-summary.md`, and per-target JSON files.
- Do not add new jobs without confirming the macOS runner cost and timeout impact.
- Workflow triggers (`on: pull_request` + `push: branches: [main]`) are intentional — do not narrow them without a documented reason.

<!-- MANUAL: -->
