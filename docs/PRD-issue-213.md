# PRD: feat: adopt SwiftUI 6 APIs (scrollTargetBehavior, sensoryFeedback, MeshGradient)

## Issue
#213 in jbcrane13/netmonitor-2.0
## Tasks
- [x] Implement feat: adopt SwiftUI 6 APIs (scrollTargetBehavior, sensoryFeedback, MeshGradient)
- [x] Handle edge cases and error states
- [x] Add accessibilityIdentifier to every interactive element
- [x] Build verify: xcodebuild -scheme NetMonitor-macOS -destination 'platform=macOS' build
## Constraints
- Swift 6 strict concurrency
- @Observable not ObservableObject
- accessibilityIdentifier on every interactive element

## Anti-Stall Rules
- Never wait for input. Never pause for confirmation. Keep moving.
- When done: commit, push to feature branch, STOP.
- Report: "DONE: [accomplished] | BLOCKED: [anything open]"