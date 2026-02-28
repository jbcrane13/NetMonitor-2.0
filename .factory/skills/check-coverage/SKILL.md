---
name: check-coverage
description: Run the NetMonitor-2.0 coverage gates and interpret results. Use after making code changes to verify coverage thresholds are still met before completing work. Must run on mac-mini via SSH.
---

# Check Coverage — NetMonitor-2.0

## Coverage thresholds (enforced in CI)

| Target | Floor |
|--------|-------|
| NetMonitor-iOS | 30% |
| NetMonitor-macOS | 20% |
| NetMonitorCore | 40% |
| NetworkScanKit | 38% |

Failing any threshold blocks the CI `coverage-gates` job on PRs.

## Run full coverage collection on mac-mini

```bash
# Sync latest changes first
git push
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && git pull --rebase"

# Run coverage gates (takes 10-30 min — runs full test suite)
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && bash scripts/coverage/collect-and-gate.sh 2>&1 | tail -40"
```

## Run package tests only (faster — ~2 min)

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && \
  SKIP_XCODE_TESTS=1 bash scripts/coverage/collect-and-gate.sh 2>&1 | tail -20"
```

## Skip package tests and only run Xcode targets

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && \
  SKIP_PACKAGE_TESTS=1 bash scripts/coverage/collect-and-gate.sh 2>&1 | tail -20"
```

## Interpreting output

```
PASS NetMonitorCore: 43.2% >= 40%      ← target met
FAIL NetMonitor-iOS: 28.1% < 30%       ← threshold not met — write more tests
```

A `FAIL` line means you need additional unit tests for that target before merging.

## Coverage artifacts

After running, artifacts are in `build/coverage/` on mac-mini:

```bash
ssh mac-mini "cat ~/Projects/NetMonitor-2.0/build/coverage/coverage-summary.md"
```

## Adding coverage for a new file

1. Identify the uncovered file: check the per-target JSON (`*-coverage.json`)
2. Write unit tests in the appropriate test target
3. Re-run coverage gates to confirm the threshold is met
4. The test file naming convention is `{TypeName}Tests.swift` in the matching test directory
