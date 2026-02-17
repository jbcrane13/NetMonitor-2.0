<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-15 -->

# Settings

## Purpose
App settings and configuration including Mac companion pairing, network tool defaults, monitoring preferences, notifications, appearance customization, data export, and privacy controls.

## Key Files
| File | Description |
|------|-------------|
| `SettingsView.swift` | Main settings screen with all configuration sections |
| `ConnectionSettingsSection.swift` | Mac companion connection status and pairing controls |
| `MacPairingView.swift` | Mac pairing flow with QR code/manual entry |
| `AcknowledgementsView.swift` | Open source acknowledgements and credits |

## For AI Agents

### Working In This Directory
- `SettingsView` uses `SettingsViewModel` for state management
- Uses SwiftUI `List` with `Section` for grouped settings
- Settings persist via UserDefaults (handled by ViewModel)
- Accessibility prefix: `settings_`
- Mac connection state managed by `MacConnectionService.shared`

### Testing Requirements
- Verify all settings persist correctly when changed
- Test data export for all formats (JSON, CSV)
- Ensure clear history/cache alerts show correct warnings
- Test theme and accent color changes update UI reactively
- Verify Mac pairing sheet presentation
- Ensure all accessibility identifiers follow naming convention

### Common Patterns
- Settings use `@State private var viewModel = SettingsViewModel()`
- Bindings to ViewModel properties via `$viewModel.propertyName`
- `ThemeManager.shared` observed for accent color reactivity
- SwiftData queries for data counts: `@Query private var toolResults: [ToolResult]`
- Sections use `.listRowBackground(Theme.Colors.glassBackground)` for glass effect
- Destructive actions (clear history/cache) show confirmation alerts

### Settings Sections
1. **Mac Companion**: Connection status, pair/unpair controls
2. **Network Tools**: Ping count, ping timeout, port scan timeout, DNS server
3. **Monitoring**: Auto-refresh interval, background refresh toggle
4. **Notifications**: Target down alerts, high latency threshold, new device alerts
5. **Appearance**: Theme selection (system/dark/light), accent color picker
6. **Data Export**: Export tool results, speed tests, devices as JSON/CSV
7. **Data & Privacy**: Data retention days, show detailed results, clear history, clear cache
8. **About**: App version, build number, iOS version, acknowledgements, support, rate app

### Key Features
- Mac pairing presented as sheet via `$showingPairingSheet`
- Data export uses `ShareSheet` (UIActivityViewController wrapper)
- Cache size calculated and displayed
- All Theme.Colors references ensure reactivity when accent color changes
- Steppers for numeric values with appropriate ranges
- Pickers for enum-like selections (theme, accent color, intervals)

### Dependencies
- ViewModels: `../../ViewModels/SettingsViewModel.swift`
- Services: `../../Services/MacConnectionService.swift`, `../../Services/DataExportService.swift`
- Models: `../../Models/ToolResult.swift`, `../../Models/SpeedTestResult.swift`, `../../Models/LocalDevice.swift`, `../../Models/PairedMac.swift`
- Utilities: `../../Utilities/Theme.swift`, `../../Utilities/ThemeManager.swift`
- Sub-views: `ConnectionSettingsSection.swift`, `MacPairingView.swift`, `AcknowledgementsView.swift`

<!-- MANUAL: -->
