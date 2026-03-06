# Data Model Reference

## Overview

NetMonitor uses two persistence strategies depending on the platform:

- **macOS:** SwiftData with a versioned schema (`SchemaV1`) and `ModelContainer`
- **iOS:** `UserDefaults` via `AppSettings` + SwiftData for structured data (targets, devices, measurements)

Both platforms share the `@Model` types defined in `NetMonitorCore/Models/`.

## SwiftData Models (Shared via NetMonitorCore)

All `@Model` types live in `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/`.

| Model | Purpose | Key Fields |
|-------|---------|------------|
| `NetworkTarget` | Monitored host/IP with check scheduling | `address`, `label`, `protocol`, `port`, `checkInterval`, `isEnabled` |
| `TargetMeasurement` | Single latency/status measurement for a target | `latency`, `status`, `timestamp`, `errorMessage` |
| `LocalDevice` | Discovered LAN device | `ipAddress`, `macAddress`, `hostname`, `deviceType`, `manufacturer` |
| `SessionRecord` | Monitoring session lifecycle (macOS) | `startDate`, `endDate`, `state` |
| `MonitoringTarget` | iOS monitoring target with uptime tracking | `address`, `label`, `isUp`, `lastLatency`, `uptimePercentage` |
| `PairedMac` | Paired macOS companion device (iOS) | `name`, `hostName`, `port` |
| `ToolResult` | Persisted result of a single tool invocation | `toolType`, `target`, `timestamp`, `resultJSON` |
| `SpeedTestResult` | Persisted speed test measurement | `downloadSpeed`, `uploadSpeed`, `latency`, `timestamp` |

### Relationships

- `NetworkTarget` → `TargetMeasurement` (one-to-many, cascade delete)

### Schema Versioning (macOS)

`SchemaV1` in `NetMonitor-macOS/App/SchemaV1.swift` registers: `NetworkTarget`, `TargetMeasurement`, `LocalDevice`, `SessionRecord`.

To add a new model version, create `SchemaV2` conforming to `VersionedSchema` and update the `MigrationPlan`.

### Concurrency Notes

`@Model` generates an unavailable `Sendable` extension. Cross-actor access to SwiftData objects should use `persistentModelID` to avoid data races, then re-fetch on the target actor's `ModelContext`.

## iOS: UserDefaults Layer (AppSettings)

`NetMonitor-iOS/Platform/AppSettings.swift` defines a centralized key namespace for all `UserDefaults`-backed settings.

### Key Categories

| Category | Keys | Storage |
|----------|------|---------|
| Network Tools | `defaultPingCount`, `pingTimeout`, `portScanTimeout`, `dnsServer`, `speedTestDuration`, `speedTestServer` | `UserDefaults.standard` |
| Data | `dataRetentionDays`, `showDetailedResults` | `UserDefaults.standard` |
| Monitoring | `autoRefreshInterval`, `backgroundRefreshEnabled`, `selectedNetworkProfileID` | `UserDefaults.standard` |
| Notifications | `targetDownAlertEnabled`, `highLatencyAlertEnabled`, `highLatencyThreshold`, `newDeviceAlertEnabled` | `UserDefaults.standard` |
| Appearance | `selectedTheme`, `selectedAccentColor` | `UserDefaults.standard` |
| Widget | `widgetIsConnected`, `widgetConnectionType`, `widgetSSID`, `widgetPublicIP`, `widgetGatewayLatency`, `widgetDeviceCount`, `widgetDownloadSpeed`, `widgetUploadSpeed` | App Group suite (`group.com.blakemiller.netmonitor`) |

### Typed Accessors

`UserDefaults` extensions provide `bool(forAppKey:default:)`, `int(forAppKey:default:)`, `double(forAppKey:default:)`, `string(forAppKey:default:)` and corresponding setters.

## iOS: TargetManager

`NetMonitor-iOS/Platform/TargetManager.swift` — `@MainActor @Observable` singleton managing a shared target address that pre-fills tool input fields.

- `currentTarget: String?` — in-memory only, resets on launch
- `savedTargets: [String]` — persisted to `UserDefaults`, max 10 entries
- FIFO with deduplication on insert

## Platform Comparison

| Concern | macOS | iOS |
|---------|-------|-----|
| Structured data | SwiftData `ModelContainer` | SwiftData (shared models) |
| User preferences | `@AppStorage` / SwiftData | `UserDefaults` via `AppSettings` |
| Widget data sharing | N/A | App Group `UserDefaults` suite |
| Schema versioning | `SchemaV1` + `MigrationPlan` | Shared `@Model` types |
| Target selection | SwiftData `NetworkTarget` | `TargetManager` (UserDefaults) |
