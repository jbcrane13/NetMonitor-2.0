<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-iOS

## Purpose
iOS app target (iOS 18.0+). Contains the app entry point, platform-specific services, ViewModels, views, and the home screen/lock screen widget. Depends on `NetMonitorCore` and `NetworkScanKit` packages.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `App/` | App entry point (`NetmonitorApp.swift`) |
| `Platform/` | iOS-specific service implementations and UI infrastructure (see `Platform/AGENTS.md`) |
| `ViewModels/` | `@MainActor @Observable` ViewModels for all screens (see `ViewModels/AGENTS.md`) |
| `Views/` | SwiftUI views organized by feature (see `Views/AGENTS.md`) |
| `Widget/` | Home screen and lock screen widget extension |
| `Resources/` | `Info.plist`, asset catalogs |

## For AI Agents

### Architecture Rules
- Views contain **no business logic** — all logic belongs in ViewModels
- ViewModels are `@MainActor @Observable final class` and live in `ViewModels/`
- Platform services implement protocols from `NetMonitorCore/Services/ServiceProtocols.swift`
- Use `AsyncStream<T>` for long-running operations (ping, scan, traceroute)

### iOS-Specific Capabilities
- **Companion connection**: `MacConnectionService` discovers the macOS companion via Bonjour (`_netmon._tcp`)
- **WiFi info**: `WiFiInfoService` uses CoreLocation + `NEHotspotNetwork`
- **Background tasks**: `BackgroundTaskService` uses `BGTaskScheduler`
- **Theme**: Liquid glass — use `GlassCard`, `GlassButton`, `.themedBackground()`, `.glassCard()` from `Platform/Theme.swift`
- **Widget**: `NetmonitorWidget.swift` targets lock screen + home screen

### Testing
```bash
xcodebuild test -scheme NetMonitor-iOS
```

## Dependencies

### Internal
- `NetMonitorCore` — service protocols, models, shared services
- `NetworkScanKit` — device discovery engine

### External
- `CoreLocation` — WiFi SSID/BSSID
- `NetworkExtension` — `NEHotspotNetwork`
- `BackgroundTasks` — `BGTaskScheduler`
- `WidgetKit` — home/lock screen widget

<!-- MANUAL: -->
