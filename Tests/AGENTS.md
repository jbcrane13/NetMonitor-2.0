<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# Tests

## Purpose
Unit and integration test suites for all targets. Currently minimal coverage — test infrastructure is in place but most files are stubs.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `NetMonitorCoreTests/` | Tests for the `NetMonitorCore` package |
| `NetMonitor-macOSTests/` | Tests for the macOS app target |
| `NetMonitor-iOSTests/` | Tests for the iOS app target |

## For AI Agents

### Running Tests
```bash
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS
```

### Current State
Coverage is low — most test files are stubs. Service protocols are designed for testability via dependency injection.

### Testing Patterns
- Mock platform services by implementing protocols from `NetMonitorCore/Services/ServiceProtocols.swift`
- `AsyncStream` tools: create a mock stream with known values using `AsyncStream<T> { continuation in ... }`
- `@MainActor` ViewModels: wrap test calls in `await MainActor.run { ... }`
- SwiftData: use in-memory `ModelContainer` for isolation

<!-- MANUAL: -->
