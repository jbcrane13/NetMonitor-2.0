<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Views/Settings

## Purpose
Seven settings panels presented in the macOS Settings window (`Settings` scene). Each panel covers a distinct configuration area.

## Key Files

| File | Description |
|------|-------------|
| `GeneralSettingsView.swift` | Launch at login, startup behavior, general preferences |
| `MonitoringSettingsView.swift` | Check intervals, failure thresholds, retry counts |
| `NetworkSettingsView.swift` | DNS server override, scan timeout, TCP probe ports |
| `NotificationSettingsView.swift` | Alert rules for target down, high latency, new devices |
| `AppearanceSettingsView.swift` | Theme (system/light/dark), accent color |
| `CompanionSettingsView.swift` | iOS companion service toggle, port config, paired devices |
| `DataSettingsView.swift` | Retention period, export format, clear history |

## For AI Agents

### macOS Settings Pattern
- Use `Form` + `Section` (not `List`) for macOS settings layout
- Use `LabeledContent` for key-value rows
- Persist settings via `UserDefaults` or `AppSettings` observable — not SwiftData
- Each view is a standalone `View` struct with `@AppStorage` or injected settings

### Dependencies
- `../Platform/CompanionService.swift` — companion toggle
- `NetMonitorCore` — shared model types

<!-- MANUAL: -->
