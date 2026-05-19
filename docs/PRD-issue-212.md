# PRD: feat(ios): adopt iOS 18 Liquid Glass APIs (.glassEffect) over .ultraThinMaterial

## Issue
#212 in jbcrane13/netmonitor-2.0
## Tasks
- [x] Implement feat(ios): adopt iOS 18 Liquid Glass APIs (.glassEffect) over .ultraThinMaterial
- [x] Run full test suite
- [x] Review code quality and suggest improvements
- [ ] Add accessibilityIdentifier to every interactive element
- [ ] Build verify: xcodebuild -scheme NetMonitor -destination 'platform=macOS' build
## Constraints
- Swift 6 strict concurrency
- @Observable not ObservableObject
- accessibilityIdentifier on every interactive element

## Anti-Stall Rules
- Never wait for input. Never pause for confirmation. Keep moving.
- When done: commit, push to feature branch, STOP.
- Report: "DONE: [accomplished] | BLOCKED: [anything open]"