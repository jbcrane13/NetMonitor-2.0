# PRD: fix(concurrency): WorldPingService.lastError data race masked by @unchecked Sendable

## Issue
#198 in jbcrane13/netmonitor-2.0
## Tasks
- [ ] Write failing tests that define expected behavior
- [ ] Implement fix(concurrency): WorldPingService.lastError data race masked by @unchecked Sendable to pass tests
- [ ] Handle edge cases
- [ ] Add accessibilityIdentifier to every interactive element
- [ ] Run full test suite — all tests must pass
## Constraints
- Swift 6 strict concurrency
- @Observable not ObservableObject
- accessibilityIdentifier on every interactive element

## Anti-Stall Rules
- Never wait for input. Never pause for confirmation. Keep moving.
- When done: commit, push to feature branch, STOP.
- Report: "DONE: [accomplished] | BLOCKED: [anything open]"