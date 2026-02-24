<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitorCoreTests

## Purpose
Unit tests for the NetMonitorCore Swift package. Validates all shared models, enums, service protocol supporting types, utilities, companion message wire format, network profile management, error types, and SwiftData-backed models. These tests cover the shared foundation consumed by both the macOS and iOS app targets.

## Key Files
| File | Description |
|------|-------------|
| `CompanionMessageTests.swift` | Codable round-trip tests for every `CompanionMessage` case (heartbeat, statusUpdate, targetList, deviceList, networkProfile, command, toolResult, error), length-prefixed framing, and all `CommandAction` raw values |
| `EnumsTests.swift` | Property coverage for `DeviceType`, `StatusType`, `DeviceStatus`, `ConnectionType`, `ToolType`, `TargetProtocol`, `DNSRecordType`, `PortScanPreset`, and `PortRange` — icon names, display names, raw values, port arrays, clamping, and legacy JSON decoding |
| `MACVendorLookupServiceTests.swift` | OUI prefix resolution via `MACVendorLookupService`: colon/dash/bare formats, known vendors (Apple, Samsung), too-short input, unknown prefixes |
| `NetMonitorCoreTests.swift` | Smoke test asserting `netMonitorCoreVersion` is non-empty |
| `NetworkErrorTests.swift` | `NetworkError` error descriptions, user-facing messages, `NetworkError.from()` mapping for all cases including `CancellationError` and unknown errors |
| `NetworkModelsTests.swift` | `NetworkStatus`, `WiFiInfo` signal quality/bars dBm thresholds, `GatewayInfo.latencyText` formatting, `ISPInfo.locationText` fallback chain |
| `NetworkProfileManagerTests.swift` | Profile CRUD (add/switch/remove), `UserDefaults` persistence round-trip, local network detection, protection of auto-detected local profiles, active profile defaulting, companion profile upsert idempotency, scan metadata isolation across profiles |
| `NetworkUtilitiesTests.swift` | `NetworkUtilities.ipv4ToUInt32` / `uint32ToIPv4` conversion and round-trip, `IPv4Network.contains`, `prefixLength`, `hostAddresses` (limit, interface exclusion, boundary cases), `detectSubnet` / `detectDefaultGateway` format validation |
| `RemainingModelsTests.swift` | `NavigationSection`, `MeasurementStatistics` formatting, `ToolActivityItem`/`ToolActivityLog`, `MonitoringTarget` (init defaults, uptime, latency, success/failure state machine), `PairedMac` display/connection text, `SessionRecord`, `LocalDevice` display name chain + status/latency mutations, `NetworkTarget`, `TargetMeasurement.calculateStatistics`, `ToolResult` / `SpeedTestResult` formatting |
| `ResumeStateTests.swift` | Actor-based `ResumeState`: initial state, `setResumed`, `tryResume` first-call/subsequent-call semantics, idempotency |
| `ServiceProtocolTypesTests.swift` | Supporting types from `ServiceProtocols.swift`: `WakeOnLANResult`, `SpeedTestData`, `SpeedTestPhase`, `ScanDisplayPhase`, `MacConnectionState` (`isConnected`, equality), `DiscoveredMac` equality |
| `ServiceUtilitiesTests.swift` | `ServiceUtilities`: `isIPAddress` (IPv4/IPv6/invalid), `isIPv4Address`, `resolveHostnameSync` passthrough for IPs and resolution of `localhost` |
| `ToolModelsTests.swift` | `PingResult.timeText` formatting thresholds, `PingStatistics` packet loss / success rate, `TracerouteHop` display address / average time / time text, `PortScanResult` service name lookup + auto-assignment, `PortState.displayName`, `DNSRecord.ttlText` second/minute/hour/day formatting, `DNSQueryResult.queryTimeText`, `BonjourService` fullType + service category mapping, `WHOISResult` domain age / days-until-expiration |

## For AI Agents

### Working In This Directory
- All tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Do not add XCTest.
- Tests import `@testable import NetMonitorCore` — keep this import; do not switch to opaque imports.
- `RemainingModelsTests.swift` and `NetworkProfileManagerTests.swift` use in-memory `ModelContainer` (SwiftData). Always call `context.insert()` before asserting model properties.
- `NetworkProfileManagerTests.swift` creates isolated `UserDefaults` suites per test via `makeUserDefaults()` and cleans up in `defer`. Follow this pattern for any new profile manager tests.
- System-dependent tests (`detectSubnet`, `detectDefaultGateway`, `resolveHostnameSync` for external hostnames) accept `nil` as a valid result — the test environment may have no network interface.
- `ResumeState` is an actor; all access is `async`. Tests must be `async` and use `await`.
- `ToolActivityLog.shared` is a singleton. Always call `log.clear()` at the start and in a `defer` block in any test that touches it.

### Testing Requirements
```bash
# From the package directory
swift test

# Or via xcodebuild
xcodebuild test -scheme NetMonitorCore -destination 'platform=macOS'
```

Tests run on macOS only (no iOS simulator target for this package).

### Common Patterns
- **Round-trip tests**: encode with `CompanionMessage.jsonEncoder`, decode with `CompanionMessage.decode(from:)`, then assert individual payload fields.
- **Enum exhaustiveness**: tests assert `allCases.count` to catch unhandled new cases at the test layer.
- **Boundary value tests**: dBm thresholds (-50/-60/-70/-80), port range clamping (1–65535), latency formatting (<1 ms cutoff).
- **SwiftData model tests**: `ModelConfiguration(isStoredInMemoryOnly: true)` + `ModelContext` — never write to disk in tests.
- **Legacy decoding**: `ConnectionType` tests verify both lowercase canonical values and capitalized legacy values decode correctly.

## Dependencies

### Internal
- `NetMonitorCore` (package under test) — all public and `@testable` types
- `SwiftData` — used in `RemainingModelsTests.swift` for `MonitoringTarget`, `LocalDevice`, `NetworkTarget`, `TargetMeasurement`, `ToolResult`, `SpeedTestResult`, `PairedMac`, `SessionRecord`
- `Foundation` — `Date`, `JSONEncoder`/`JSONDecoder`, `UserDefaults`, `UUID`

<!-- MANUAL: -->
