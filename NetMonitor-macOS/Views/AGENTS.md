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
- Tools open in the detail pane (`selection = .tool(tool)` from `ToolsView`); Close and Back return to the Tools grid

### Testing
```bash
xcodebuild test -scheme NetMonitor-macOS
```

<!-- MANUAL: -->

### Which network is this? (#628 PR B, #645)
`Devices/NetworkIdentityCard.swift` holds the question card, shown at the top of `DevicesView`, and `NetworkIdentityBanner`, a one-line pointer to it in the dashboard's device panel (`NetworkDevicesPanel`) and the menu bar popover. While a network is held, its rows read "Not checked: which network is this?" (Core `PresenceSnapshot.heldLabel`). Options are named by the controller's `optionSummaries` (saved devices, last scan, a name the user gave), never by the generated network name alone.

| Control | Accessibility ID |
|---|---|
| Card (its own container keeps the children's IDs on macOS 27); title; detail | `devices_identity_card`; `devices_identity_title`; `devices_identity_detail` |
| Same as / Yes / a no-hint option | `devices_identity_same_<network UUID>` |
| "Not this network?" (identified with no IPv6 router; clears the no-hint answer and asks again) | `devices_identity_button_reidentify` |
| New network | `devices_identity_new` |
| "Checking the network…" (an answer clicked during a failed routing read) | `devices_identity_checking` |
| Try again (a failed save); Start over (a damaged store) | `devices_identity_retry`; `devices_identity_startOver` |
| Banner on the dashboard panel / in the menu bar popover; its text; its Answer button | `dashboard_identity_banner` / `menubar_identity_banner`; `…_identity_text`; `…_identity_button_answer` |

### Device groups (#594)
One device can be several saved rows (its interfaces). Both detail views (`DeviceDetailView`, `Devices/ProDeviceDetailView`) show:
- `Devices/DeviceInterfacesCard.swift`: the Interfaces section;
- `Devices/DeviceGroupingViews.swift`: the suggestion banner, the "Same device as…" picker sheet, and the override confirmation and undo toast (`deviceGroupingFeedback()`).

The logic, the reads and the toast state are in `ViewModels/DeviceGroupingViewModel.swift`. `DevicesView` owns it, above detail, because grouping changes a device's ID and so recreates the detail view. Choices and wording are Core's `DeviceGroupingChoices`, shared with iOS.

| Control | Accessibility ID |
|---|---|
| Suggestion banner (one per suggested device); its Same device / Not the same device | `deviceDetail_banner_suggestion_<device UUID>` (Core `AccessibilityID.suggestionBanner`); `deviceDetail_button_suggestionSameDevice_<device UUID>` / `deviceDetail_button_suggestionNotSameDevice_<device UUID>` |
| Open the picker; the sheet; its empty state; a row | `deviceDetail_button_sameDeviceAs`; `screen_sameDeviceAs`; `sameDeviceAs_label_empty`; `sameDeviceAs_row_<ip, dots as underscores>` (Core `AccessibilityID.sameDeviceAsRow`, as on iOS) |
| Override confirm / cancel | `deviceDetail_button_confirmGroupOverride` / `deviceDetail_button_cancelGroupOverride` |
| Toast; its message, Undo, close | `deviceDetail_toast_undo` (not exposed on macOS 27); `deviceDetail_label_toastMessage`, `deviceDetail_button_undo`, `deviceDetail_button_dismissToast` |
| Interface row: Not the same device; Bonjour label; Remove | `deviceDetail_button_notSameDevice_<ip>`; `deviceDetail_label_groupedByBonjour_<ip>`; `deviceDetail_button_removeInterface_<ip>` |

User flows: `scripts/ax/594-device-group.sh` and `scripts/ax/594-pr2-grouping.sh`, run under `lockf -t 3600 /tmp/nm-mini1-ax.lock`.
