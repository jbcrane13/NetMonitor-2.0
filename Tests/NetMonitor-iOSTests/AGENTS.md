<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitor-iOSTests

## Purpose
Unit tests for the iOS app target. Tests all ViewModels, services, and platform-specific code using mock implementations of service protocols. All mocks are defined in `iOSMockServices.swift` and implement the protocols from `NetMonitorCore/Services/ServiceProtocols.swift`.

## Key Files

| File | Description |
|------|-------------|
| `iOSMockServices.swift` | Centralized mock service implementations for all protocols (Ping, Traceroute, DNS, WHOIS, WakeOnLAN, PortScanner, Bonjour, SpeedTest, NetworkMonitor, WiFiInfo, Gateway, PublicIP, DeviceDiscovery, MacConnection) |
| `DashboardViewModelTests.swift` | Tests for `DashboardViewModel`: device list, scan state, network status |
| `PingToolViewModelTests.swift` | Tests for `PingToolViewModel`: AsyncStream consumption, start/stop, result accumulation |
| `TracerouteToolViewModelTests.swift` | Tests for `TracerouteToolViewModel`: hop streaming, stop behavior |
| `PortScannerToolViewModelTests.swift` | Tests for `PortScannerToolViewModel`: scan results, preset selection |
| `DNSLookupToolViewModelTests.swift` | Tests for `DNSLookupToolViewModel`: query dispatch, record type handling |
| `WHOISToolViewModelTests.swift` | Tests for `WHOISToolViewModel`: lookup, error propagation |
| `SpeedTestToolViewModelTests.swift` | Tests for `SpeedTestToolViewModel`: phase transitions, result display |
| `WakeOnLANToolViewModelTests.swift` | Tests for `WakeOnLANToolViewModel`: MAC validation, send outcome |
| `BonjourDiscoveryToolViewModelTests.swift` | Tests for `BonjourDiscoveryToolViewModel`: discovery stream, start/stop |
| `SSLCertificateMonitorViewModelTests.swift` | Tests for `SSLCertificateMonitorViewModel` |
| `DeviceDetailViewModelTests.swift` | Tests for `DeviceDetailViewModel` |
| `NetworkMapViewModelTests.swift` | Tests for `NetworkMapViewModel`: scan trigger, device accumulation |
| `SettingsViewModelTests.swift` | Tests for `SettingsViewModel`: preference persistence |
| `ToolsViewModelTests.swift` | Tests for `ToolsViewModel`: tool card state, target prefill |
| `GeoFenceSettingsViewModelTests.swift` | Tests for `GeoFenceSettingsViewModel` |
| `TargetManagerTests.swift` | Tests for `TargetManager`: CRUD operations, persistence |
| `AppSettingsTests.swift` | Tests for `AppSettings`: default values, UserDefaults round-trips |
| `DataExportServiceTests.swift` | Tests for `DataExportService`: export format correctness |
| `ThemeTests.swift` | Tests for `Theme`: color resolution, accent mapping |
| `NetMonitor_iOSTests.swift` | Placeholder / suite entry point |

## For AI Agents

### Working In This Directory
- All tests use XCTest with `@MainActor` on ViewModel test classes.
- Inject mocks via ViewModel initializer parameters — all ViewModels accept protocol types.
- `iOSMockServices.swift` is the single source of truth for mocks; add new mocks there rather than inline in test files.
- Mocks that implement `@MainActor` protocols are marked `@MainActor`. Mocks for `Sendable` streaming services use `@unchecked Sendable`.

### Testing Requirements
```bash
xcodebuild test -scheme NetMonitor-iOS -only-testing:NetMonitor-iOSTests
```

### Common Patterns

**AsyncStream ViewModel test:**
```swift
let mockPing = MockPingService()
mockPing.mockResults = [PingResult(sequenceNumber: 1, latency: 5.0, isReachable: true)]
let vm = await MainActor.run { PingToolViewModel(pingService: mockPing) }
await vm.startPing(host: "1.1.1.1")
// assert vm.results, vm.isRunning, etc.
```

**Error path test:**
```swift
let mockWHOIS = MockWHOISService()
mockWHOIS.shouldThrow = true
mockWHOIS.thrownError = URLError(.notConnectedToInternet)
// assert ViewModel surfaces error message
```

**SwiftData isolation (TargetManager, AppSettings):**
```swift
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: [config])
```

## Dependencies

### Internal
- `NetMonitorCore` — service protocols, model types, `AsyncStream`-based results
- `NetworkScanKit` — `DiscoveredDevice`, scan types used in `NetworkMapViewModel`
- iOS app target (`@testable import NetMonitor_iOS`) — ViewModels, services, `AppSettings`, `TargetManager`, `Theme`

<!-- MANUAL: -->
