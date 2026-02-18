<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-iOS/ViewModels

## Purpose
`@MainActor @Observable` ViewModels for all iOS screens. Each ViewModel corresponds to one view or feature and encapsulates all business logic, service interactions, and state management for that feature.

## Key Files

| File | Description |
|------|-------------|
| `DashboardViewModel.swift` | Network status, WiFi info, gateway latency, public IP, scan trigger |
| `NetworkMapViewModel.swift` | Device discovery orchestration, scan progress, device list |
| `DeviceDetailViewModel.swift` | Device enrichment (port scan, Bonjour), notes persistence |
| `ToolsViewModel.swift` | Tool navigation state |
| `PingToolViewModel.swift` | Streaming ping results via `AsyncStream<PingResult>` |
| `PortScannerToolViewModel.swift` | Concurrent port scan with streaming results |
| `TracerouteToolViewModel.swift` | Traceroute hop streaming |
| `DNSLookupToolViewModel.swift` | DNS record queries |
| `WHOISToolViewModel.swift` | WHOIS lookups |
| `SpeedTestToolViewModel.swift` | Download/upload speed test phases |
| `BonjourDiscoveryToolViewModel.swift` | mDNS service browser |
| `WakeOnLANToolViewModel.swift` | Magic packet dispatch |
| `SettingsViewModel.swift` | User preferences, data management, export |

## For AI Agents

### ViewModel Pattern
```swift
@MainActor @Observable
final class FooViewModel {
    // Published state (read by views)
    private(set) var results: [FooResult] = []
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    // Service dependency (injected or singleton)
    private let service: FooServiceProtocol

    func run() async { ... }
    func stop() { ... }
}
```

### AsyncStream Consumption Pattern
```swift
func runPing(host: String) async {
    isRunning = true
    let stream = await service.ping(host: host, count: count, timeout: timeout)
    for await result in stream {
        results.append(result)
    }
    isRunning = false
}
```

### Rules
- All ViewModels are `@MainActor @Observable final class`
- Never put business logic in views — it belongs here
- Use `Task { await viewModel.run() }` from views to start async work
- Cancel running tasks in `stop()` or on deinit
- Errors surface as `errorMessage: String?` for the view to display

### Dependencies
- Services from `../Platform/SharedServices.swift` (singletons)
- Models from `NetMonitorCore`

<!-- MANUAL: -->
