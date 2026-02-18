<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitorCore/Models

## Purpose
Data models shared between macOS and iOS. All models are `Codable` and `Sendable`. SwiftData models (`@Model`) are macOS-only and conditionally compiled.

## Key Files

| File | Description |
|------|-------------|
| `Enums.swift` | Core enumerations: `DeviceType`, `StatusType`, `ConnectionType`, `ToolType`, `TargetProtocol`, `DNSRecordType`, `PortScanPreset`, `ScanDisplayPhase`, `SpeedTestPhase` |
| `NetworkModels.swift` | `NetworkStatus`, `WiFiInfo`, `WiFiBand`, `GatewayInfo`, `ISPInfo`, `SignalQuality` |
| `ToolModels.swift` | `PingResult`, `PingStatistics`, `PortScanResult`, `TracerouteHop`, `BonjourService`, `DNSQueryResult`, `WHOISResult`, `SpeedTestResult` |
| `ToolResult.swift` | Generic `ToolResult` wrapper for persisting tool execution results |
| `ToolActivityLog.swift` | Record of tool execution history |
| `CompanionMessage.swift` | Wire format for Mac–iOS communication (Bonjour companion protocol) |
| `NavigationSection.swift` | Navigation section definitions for both platforms |
| `NetworkError.swift` | Shared error types |
| `LocalDevice.swift` | `@Model` SwiftData model for discovered LAN devices (macOS) |
| `NetworkTarget.swift` | `@Model` SwiftData model for monitored targets (macOS) |
| `SessionRecord.swift` | `@Model` SwiftData model for monitoring sessions (macOS) |
| `MonitoringTarget.swift` | Plain struct for a monitoring target (cross-platform) |
| `TargetMeasurement.swift` | Single latency/status measurement |
| `PairedMac.swift` | Mac companion device info (stored on iOS) |

## For AI Agents

### Rules
- All models must be `Sendable` — use `struct` by default, `final class` only when reference semantics are required
- `Codable` conformance is required for any type crossing the companion protocol wire
- `@Model` types (SwiftData) are macOS-only — guard with `#if os(macOS)` or keep in a separate file
- Adding enum cases is a breaking change for Codable — add `unknown` fallback cases

### Companion Wire Format
`CompanionMessage.swift` defines the JSON envelope. Any new message type must be added here and implemented in both `CompanionService` (macOS) and `MacConnectionService` (iOS).

<!-- MANUAL: -->
