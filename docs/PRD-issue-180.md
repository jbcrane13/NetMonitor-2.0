# PRD: Coverage below target: 63.9% vs 70% target

## Context
## Test Coverage Alert — 2026-04-16

**Current Coverage:** 63.90% (regions)
**Target:** 70%
**Gap:** -6.10 percentage points

### Key Gaps
- NetworkScanKit has significant untested code (ScanEngine, ScanAccumulator, ScanPipeline all at 0%)
- Multiple modules in 20-40% range

### Action Required
1. Focus on NetworkScanKit — largest coverage gap
2. Add tests for scan pipeline and engine
3. Target 70% by next sprint

### Detection
Automated coverage enforcement cron (2026-04-16 10:02 CDT)
## Tasks
- [ ] Write failing tests that define expected behavior
- [ ] Implement Coverage below target: 63.9% vs 70% target to pass tests
- [ ] Handle edge cases
- [ ] Add accessibilityIdentifier to every interactive element
- [ ] Run full test suite — all tests must pass
- [ ] Build verify: xcodebuild -scheme NetMonitor-macOS -configuration Debug build
## Constraints
- Swift 6 strict concurrency
- @Observable not ObservableObject
- accessibilityIdentifier on every interactive element
- Do not modify files not listed above

## If Blocked
- Build error unrelated to this task → note it, continue
- Missing dependency → stub + TODO + GitHub issue, continue
- 5-attempt max → stub, open GitHub issue, stop

## Anti-Stall Rules
- Never wait for input. Never pause for confirmation. Keep moving.
- File doesn't exist: create it. Missing dependency: stub it.
- When done: commit, push to feature branch, STOP.
- Report: "DONE: [accomplished] | BLOCKED: [anything open]"