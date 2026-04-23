# PRD: P2: Upgrade 95 shallow macOS UI tests to functional verification

## Context
## Test Coverage: macOS UI Test Functional Upgrades

95 shallow macOS UI tests that only check element existence.

### Priority Upgrades:
- [x] Device context menu: verify action triggers result
- [x] Tool outcome tests: verify data appears in results
- [x] Settings: verify preference changes persist
- [x] Sidebar navigation: verify content changes on selection

### Estimated: 25 test upgrades
## Tasks
- [x] Implement P2: Upgrade 95 shallow macOS UI tests to functional verification
- [x] Handle edge cases and error states
- [x] Add accessibilityIdentifier to every interactive element
- [x] Build verify: xcodebuild -scheme NetMonitor-macOS -configuration Debug build
- [x] Run tests: ssh mac-mini "cd ~/Projects/jbcrane13/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO"
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