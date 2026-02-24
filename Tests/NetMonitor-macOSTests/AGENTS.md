<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitor-macOSTests

## Purpose
Unit tests for the macOS app target. Tests shell-based service parsers, SwiftData-backed coordinators, companion message handling, monitoring session state, and platform-specific utilities. All tests use Swift Testing (`@Suite`, `@Test`, `#expect`) rather than XCTest.

## Key Files

| File | Description |
|------|-------------|
| `ShellPingParserTests.swift` | Thorough parser tests for `ShellPingOutputParser`: valid response lines, timeout lines, summary parsing, stats parsing, malformed/garbage input, Linux-format variants |
| `CompanionMessageHandlerTests.swift` | Tests for `CompanionMessageHandler`: heartbeat, unsupported commands, missing parameters, target list from SwiftData, device list payload mapping |
| `MonitoringSessionTests.swift` | Tests for `MonitoringSession`: no-enabled-targets guard, stop idempotency, measurement pruning with 7-day and Forever retention |
| `DeviceDiscoveryCoordinatorTests.swift` | Tests for `DeviceDiscoveryCoordinator`: device merge, profile scoping |
| `StatisticsServiceTests.swift` | Tests for `StatisticsService`: latency aggregation, uptime calculation |
| `NetworkInfoServiceTests.swift` | Tests for `NetworkInfoService`: interface info parsing |
| `DefaultTargetsProviderTests.swift` | Tests for `DefaultTargetsProvider`: default target list correctness |
| `ContinuationTrackerTests.swift` | Tests for `ContinuationTracker`: AsyncStream continuation lifecycle |
| `WakeOnLanActionTests.swift` | Tests for Wake-on-LAN magic packet construction and send logic |
| `NetMonitor_macOSTests.swift` | Suite entry point |

## For AI Agents

### Working In This Directory
- Tests use **Swift Testing** framework, not XCTest. Use `@Suite`, `@Test`, and `#expect` — not `XCTestCase` or `XCTAssert*`.
- Mark test structs/classes `@MainActor` when testing `@MainActor`-isolated types.
- SwiftData tests use `makeFixture()` or `makeInMemoryStore()` helpers that create an in-memory `ModelContainer`. Always capture and hold the container reference (even with `_ = container`) to prevent deallocation mid-test.
- `CompanionMessageHandlerTests` creates real service instances (not mocks) with minimal configurations (e.g. `ARPScannerService(timeout: 0.05)`) to keep tests fast.

### Testing Requirements
```bash
xcodebuild test -scheme NetMonitor-macOS -only-testing:NetMonitor-macOSTests
```

### Common Patterns

**Swift Testing suite structure:**
```swift
@Suite("MyService")
@MainActor
struct MyServiceTests {
    @Test func someCondition() throws {
        #expect(value == expected)
    }
}
```

**In-memory SwiftData fixture:**
```swift
let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: [config])
let context = container.mainContext
// Keep `container` alive for the duration of the test
```

**Shell parser test:**
```swift
let line = "64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=1.234 ms"
let result = ShellPingOutputParser.parseResponseLine(line)
#expect(result?.latency == 1.234)
```

## Dependencies

### Internal
- `NetMonitorCore` — `NetworkTarget`, `TargetMeasurement`, `SessionRecord`, `LocalDevice`, service protocols
- macOS app target (`@testable import NetMonitor_macOS`) — `ShellPingOutputParser`, `ShellPingResult`, `CompanionMessageHandler`, `MonitoringSession`, `DeviceDiscoveryCoordinator`, `NetworkProfileManager`

<!-- MANUAL: -->
