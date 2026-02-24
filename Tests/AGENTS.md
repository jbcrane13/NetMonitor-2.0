<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# Tests

## Purpose
Unit and UI test suites for the macOS and iOS app targets. Extensive coverage across ViewModels, services, shell output parsers, SwiftData coordinators, companion message handling, and XCUITest end-to-end flows.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `NetMonitor-iOSTests/` | 21 unit test files for the iOS app target |
| `NetMonitor-iOSUITests/` | 25 XCUITest files for the iOS app target |
| `NetMonitor-macOSTests/` | 10 unit test files for the macOS app target |
| `NetMonitor-macOSUITests/` | 20 XCUITest files for the macOS app target |

Note: Package-level tests for `NetMonitorCore` and `NetworkScanKit` live under `Packages/`, not here.

## For AI Agents

### Running Tests
```bash
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS
```

### Testing Patterns
- Mock platform services by implementing protocols from `NetMonitorCore/Services/ServiceProtocols.swift`
- All iOS mocks are centralized in `NetMonitor-iOSTests/iOSMockServices.swift`
- `AsyncStream` tools: create a mock stream with known values using `AsyncStream<T> { continuation in ... }`
- `@MainActor` ViewModels: wrap test calls in `await MainActor.run { ... }`
- SwiftData: use in-memory `ModelContainer` with `isStoredInMemoryOnly: true` for isolation
- macOS unit tests use Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest
- UI tests subclass `IOSUITestCase` (iOS) or `MacOSUITestCase` (macOS) which handle launch flags and common helpers
- Both UI test base classes inject `--uitesting` launch arguments to suppress auto-start and monitoring

### Accessibility Identifier Convention
UI tests query elements by accessibility ID: `{screen}_{element}_{descriptor}` (e.g. `pingTool_button_run`, `detail_settings`, `sidebar_tools`).

<!-- MANUAL: -->
