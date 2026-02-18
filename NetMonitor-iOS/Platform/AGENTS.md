<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-iOS/Platform

## Purpose
iOS-specific service implementations and UI infrastructure. Implements service protocols from `NetMonitorCore`, provides the liquid glass theme system, and manages iOS platform concerns (companion connection, WiFi info, background tasks, data management).

## Key Files

| File | Description |
|------|-------------|
| `SharedServices.swift` | Service singletons and retroactive conformances wiring protocols to implementations |
| `MacConnectionService.swift` | Connects to macOS companion via Bonjour (`_netmon._tcp`, port 8849) using `NWConnection` |
| `WiFiInfoService.swift` | Reads SSID/BSSID via `NEHotspotNetwork.fetchCurrent()` (requires CoreLocation permission) |
| `GatewayService.swift` | Detects default gateway IP via routing table |
| `PublicIPService.swift` | Fetches public IP and geolocation via HTTP |
| `Theme.swift` | Color, spacing, and font constants for the liquid glass design system |
| `ThemeManager.swift` | `@Observable` singleton managing accent color and theme persistence |
| `GlassCard.swift` | `UIVisualEffectView`-backed glass card component and `.glassCard()` modifier |
| `TargetManager.swift` | Persists monitoring targets to `UserDefaults` |
| `AppSettings.swift` | `@Observable` user preferences (ping count, timeout, DNS server, theme, etc.) |
| `DataExportService.swift` | Exports tool results and devices as CSV or JSON |
| `DataMaintenanceService.swift` | Cleanup and archival of old tool results |
| `BackgroundTaskService.swift` | Registers and handles `BGTaskScheduler` background refresh tasks |

## For AI Agents

### Working In This Directory
- All services are singletons accessed via `ServiceName.shared` (wired in `SharedServices.swift`)
- New services must implement the corresponding protocol from `NetMonitorCore/Services/ServiceProtocols.swift`
- Theme constants live in `Theme.swift` — never hardcode colors, spacing, or fonts
- `MacConnectionService` uses newline-delimited JSON; see `docs/Companion-Protocol-API.md` for wire format

### Theme System
```swift
// Colors
Theme.Colors.primary         // Accent color (user-configurable)
Theme.Colors.glassBackground // Card background
Theme.Colors.secondaryText

// Spacing
Theme.Layout.padding         // Standard padding
Theme.Layout.cornerRadius    // Standard corner radius

// Fonts
Theme.Typography.headline
Theme.Typography.body
```

### Dependencies

#### Internal
- `NetMonitorCore` — service protocols, `CompanionMessage` wire format
- `NetworkScanKit` — `DiscoveredDevice` model

#### External
- `CoreLocation` — WiFi access
- `NetworkExtension` — `NEHotspotNetwork`
- `BackgroundTasks` — `BGTaskScheduler`
- `Network` — `NWConnection` for companion

<!-- MANUAL: -->
