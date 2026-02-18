<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Views

## Purpose
SwiftUI views for the macOS app. The main window uses `NavigationSplitView` with a sidebar for section navigation. Views do not contain business logic — state comes from `@Environment` services or `@Query` SwiftData.

## Key Files

| File | Description |
|------|-------------|
| `ContentView.swift` | Root `NavigationSplitView` — sidebar + detail routing |
| `SidebarView.swift` | Navigation sidebar with section list |
| `DashboardView.swift` | Network status overview (connectivity, gateway, ISP) |
| `DevicesView.swift` | Discovered LAN devices list with scan controls |
| `DeviceRowView.swift` | Single device row component |
| `DeviceDetailView.swift` | Per-device detail panel |
| `TargetsView.swift` | Monitored targets list with status indicators |
| `AddTargetSheet.swift` | Sheet for adding a new monitoring target |
| `TargetStatisticsView.swift` | Historical statistics for a monitoring target |
| `ToolsView.swift` | Network tool launcher grid |
| `SettingsView.swift` | Settings entry point |
| `ConnectionInfoCard.swift` | Reusable card showing connection type and quality |
| `GatewayInfoCard.swift` | Gateway IP, latency, and status card |
| `ISPInfoCard.swift` | Public IP and ISP info card |
| `QuickStatsBar.swift` | Horizontal bar with key metrics |
| `LiveDurationView.swift` | Formatted live duration display (e.g., "2h 14m") |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Settings/` | 7 settings panels (see `Settings/AGENTS.md`) |
| `Tools/` | Network tool views — ping, port scan, DNS, traceroute, etc. (see `Tools/AGENTS.md`) |

## For AI Agents

### macOS View Conventions
- Use `NavigationSplitView` for main navigation — do not replace with `TabView`
- Service dependencies injected via `@Environment` (set up in `NetMonitorApp.swift`)
- SwiftData: use `@Query` for reactive fetching; `@Environment(\.modelContext)` for writes
- macOS uses standard system appearance — no liquid glass theme; use `List`, `GroupBox`, `Form`
- Tool sheets presented via `.sheet(isPresented:)` from `ToolsView`

### Testing
```bash
xcodebuild test -scheme NetMonitor-macOS
```

<!-- MANUAL: -->
