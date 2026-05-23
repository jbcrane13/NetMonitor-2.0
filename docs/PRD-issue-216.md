# PRD: perf(ios): parallelize DashboardViewModel.measureAnchors with TaskGroup

## Issue
#216 in jbcrane13/netmonitor-2.0
## Tasks
- [x] Implement perf(ios): parallelize DashboardViewModel.measureAnchors with TaskGroup
- [ ] Handle edge cases and error states
- [ ] Add accessibilityIdentifier to every interactive element
- [ ] Build verify: xcodebuild -scheme AgentBoard -destination 'platform=macOS' build
## Constraints
- Swift 6 strict concurrency
- @Observable not ObservableObject
- accessibilityIdentifier on every interactive element

## Anti-Stall Rules
- Never wait for input. Never pause for confirmation. Keep moving.
- When done: commit, push to feature branch, STOP.
- Report: "DONE: [accomplished] | BLOCKED: [anything open]"