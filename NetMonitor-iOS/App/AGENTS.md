<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitor-iOS/App

## Purpose
iOS app entry point. Contains the `@main` App struct that bootstraps the SwiftUI scene, configures SwiftData, and initializes app-wide services on first appearance.

## Key Files
| File | Description |
|------|-------------|
| `NetmonitorApp.swift` | `@main` `NetmonitorApp: App` — configures `ModelContainer`, forces dark color scheme, starts `NetworkMonitorService`, registers background tasks, requests notification authorization, and prunes expired data |

## For AI Agents

### Working In This Directory
- The app is locked to dark mode (`resolvedColorScheme` always returns `.dark`). Do not add light-mode theming here without a broader UI audit.
- SwiftData schema registered here: `PairedMac`, `LocalDevice`, `MonitoringTarget`, `ToolResult`, `SpeedTestResult`. Adding a new persistent model requires updating the `Schema` array in `sharedModelContainer`.
- UI testing detection (`isUITesting`) checks both launch arguments (`--uitesting`, `--uitesting-reset`) and environment variables (`UITEST_MODE`, `XCUITest`, `XCTestConfigurationFilePath`). When UI testing, the model container is in-memory only. Do not bypass this guard.
- `UITestBootstrap.configureIfNeeded()` is called unconditionally in `onAppear` before the UI-testing early return — this is intentional.
- Service startup order in `onAppear` is significant: `NetworkMonitorService.shared` first (so the initial dashboard render sees real connectivity), then background task registration, then notification authorization, then data pruning.
- Background tasks are registered and scheduled here via `BackgroundTaskService.shared`. Background task identifiers must also be declared in the app's `Info.plist`.

<!-- MANUAL: -->
