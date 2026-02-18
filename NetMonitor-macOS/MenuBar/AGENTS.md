<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/MenuBar

## Purpose
Menu bar integration: status bar icon, quick-access popover, and app menu commands.

## Key Files

| File | Description |
|------|-------------|
| `MenuBarController.swift` | Manages `NSStatusItem` lifecycle, icon updates, and popover presentation |
| `MenuBarPopoverView.swift` | SwiftUI popover showing network status summary and quick actions |
| `MenuBarCommands.swift` | `Commands` conformance adding app-level menu items |

## For AI Agents

### Working In This Directory
- `MenuBarController` owns the `NSStatusItem` — do not create additional status items
- The popover is a lightweight summary — do not add complex stateful UI here
- Icon tint reflects connection status: green (connected), yellow (degraded), red (offline)
- `MenuBarPopoverView` receives environment objects from the main app container
- Menu commands in `MenuBarCommands.swift` use `@FocusedBinding` and `@Environment` for context

### Dependencies
- `Platform/MacNetworkMonitor.swift` — status data for icon tinting
- `NetMonitorCore` — `NetworkStatus`, `StatusType`

<!-- MANUAL: -->
