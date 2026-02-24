<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# scripts/coverage

## Purpose
Test coverage collection and enforcement. Runs Xcode and Swift package tests with coverage enabled, extracts per-target line coverage percentages, and fails the build if any target falls below its configured threshold.

## Key Files
| File | Description |
|------|-------------|
| `collect-and-gate.sh` | Runs all test suites, collects coverage via `xcrun xccov` and `swift test --enable-code-coverage`, checks thresholds, writes `build/coverage/coverage-summary.json` and `build/coverage/coverage-summary.md` |

## For AI Agents

### Working In This Directory
Coverage thresholds are controlled by environment variables with defaults at the top of `collect-and-gate.sh`:

| Variable | Default | Target |
|----------|---------|--------|
| `IOS_APP_FLOOR` | 30% | NetMonitor-iOS.app |
| `MACOS_APP_FLOOR` | 20% | NetMonitor-macOS.app |
| `NETMONITORCORE_FLOOR` | 40% | NetMonitorCore |
| `NETWORKSCANKIT_FLOOR` | 38% | NetworkScanKit |

- To raise a threshold, increment the default value in the script. Thresholds are intentionally low — raise them as test coverage improves, never lower them.
- `SKIP_XCODE_TESTS=1` and `SKIP_PACKAGE_TESTS=1` environment variables allow skipping test runs when pre-built `.xcresult` and coverage JSON files already exist. Used for local iteration only.
- iOS coverage is extracted from `xccov` target reports (`coveredLines / executableLines`). Package coverage is extracted from LLVM JSON (`data[0].totals.lines.percent`). These are different formats — keep the two extraction functions (`extract_xccov_target_percent`, `extract_llvm_line_percent`) separate.
- Output artifacts land in `build/coverage/` (gitignored). The CI workflow uploads them as build artifacts on every run, including failures.
- The script requires `python3` on `$PATH` for JSON parsing and threshold comparison. This is satisfied by the `macos-15` GitHub Actions runner.

<!-- MANUAL: -->
