<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS

## Purpose
macOS app target (macOS 15.0+). Contains the app entry point, SwiftData schema, menu bar integration, platform-specific services (shell-based ping/ARP, raw ICMP), and all macOS views. Advertises a Bonjour companion service for iOS to discover.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `App/` | App entry point and SwiftData schema |
| `MenuBar/` | Status bar icon, quick-access popover, and menu commands |
| `Platform/` | macOS-specific service implementations (see `Platform/AGENTS.md`) |
| `Utilities/` | App-level utilities and Swift extensions |
| `Views/` | SwiftUI views (see `Views/AGENTS.md`) |
| `Preview/` | `PreviewContainer.swift` for SwiftUI previews with in-memory SwiftData |
| `Resources/` | `Info.plist`, `.entitlements`, asset catalogs |

## Key Files

| File | Description |
|------|-------------|
| `App/NetMonitorApp.swift` | `@main` entry point, window/scene configuration, menu bar setup |
| `App/SchemaV1.swift` | SwiftData schema: `NetworkTarget`, `LocalDevice`, `SessionRecord`, `TargetMeasurement` |
| `MenuBar/MenuBarController.swift` | `NSStatusItem` lifecycle, popover presentation |

## For AI Agents

### macOS-Specific Capabilities
- **Shell-based ping/ARP**: `ShellCommandRunner` executes `/sbin/ping` and `/usr/sbin/arp`
- **Raw ICMP**: `ICMPSocket` (raw socket) + `ICMPMonitorService` for continuous monitoring
- **SwiftData persistence**: `NetworkTarget`, `LocalDevice`, `SessionRecord` — use `DeviceDiscoveryCoordinator`
- **Companion server**: `CompanionService` advertises `_netmon._tcp` on port 8849 for iOS
- **Menu bar**: `MenuBarController` manages the `NSStatusItem`

### Sandbox Restrictions
The app runs in a sandbox. Entitlements in `NetMonitor-macOS.entitlements` grant raw socket and outgoing network access. Do not remove entitlements without testing the affected feature.

### SwiftData Rules
- All models defined in `App/SchemaV1.swift`
- `DeviceDiscoveryCoordinator` bridges SwiftData and discovery services
- Never access `ModelContext` off the main actor

### Testing
```bash
xcodebuild test -scheme NetMonitor-macOS
```

## Dependencies

### Internal
- `NetMonitorCore` — service protocols, models, shared services
- `NetworkScanKit` — device discovery engine

### External
- `SwiftData` — persistence
- `Network` — `NWConnection`/`NWListener` for companion service
- `dnssd` — Bonjour advertisement

<!-- MANUAL: -->
