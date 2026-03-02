---
name: run-tests
description: Run the NetMonitor-2.0 test suite. CRITICAL — tests must run on the mac-mini via SSH, never locally on this machine (no display session for UI tests, and the PreToolUse hook blocks local xcodebuild test calls). Use this skill any time you need to verify tests pass before committing or completing work.
---

# Run Tests — NetMonitor-2.0

## CRITICAL: Always run tests on mac-mini, never locally

This machine has no display/accessibility session. Local `xcodebuild test` will hang on UI tests and is blocked by a PreToolUse hook. All test runs must go through SSH to mac-mini.

## Unit Tests (no signing required — run these first)

```bash
# macOS unit tests
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-macOS \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:NetMonitor-macOSTests \
  2>&1 | tail -30"

# iOS unit tests
# -parallel-testing-enabled NO prevents Swift Concurrency runtime crashes with async @MainActor tests on Xcode 26 beta
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:NetMonitor-iOSTests \
  2>&1 | tail -30"

# Swift package tests (NetMonitorCore + NetworkScanKit)
# --no-parallel prevents Swift Concurrency runtime crashes when async actor-isolated tests run concurrently
ssh mac-mini "cd ~/Projects/NetMonitor-2.0/Packages/NetMonitorCore && swift test --no-parallel 2>&1 | tail -20"
ssh mac-mini "cd ~/Projects/NetMonitor-2.0/Packages/NetworkScanKit && swift test --no-parallel 2>&1 | tail -20"
```

## UI Tests (require signed build + active GUI session on mac-mini)

```bash
# macOS UI tests
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-macOS \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:NetMonitor-macOSUITests \
  2>&1 | tail -30"

# iOS UI tests
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' \
  -only-testing:NetMonitor-iOSUITests \
  2>&1 | tail -30"
```

## Sync repo to mac-mini before running tests

If you've made local commits that aren't pushed yet, push first:

```bash
git push
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && git pull --rebase"
```

## Interpreting results

- `** TEST SUCCEEDED **` — all tests passed
- `** TEST FAILED **` — look for `error:` lines above the summary
- Exit code 0 = pass, non-zero = failure

## Running specific tests

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:NetMonitor-macOSTests/ISPCardErrorSurfacingTests \
  2>&1 | tail -20"
```
