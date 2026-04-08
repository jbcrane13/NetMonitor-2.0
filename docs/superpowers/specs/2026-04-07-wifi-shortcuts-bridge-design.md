# WiFi Shortcuts Bridge — Complete Implementation (GH-131)

**Date:** 2026-04-07
**Status:** Approved
**Ref:** iOS-WiFi-Heatmap-Spec.md, ADR-020

---

## Context

The Shortcuts WiFi bridge code (`ShortcutsWiFiProvider`, `IOSHeatmapService`, `DeepLinkRouter`) is fully implemented but non-functional due to missing entitlements and Info.plist configuration. There is also no user-facing setup flow for installing the companion Shortcut.

## Scope

1. Fix infrastructure gaps so the existing bridge code actually works
2. Add a guided setup UI for first-time Shortcut installation
3. Add fallback-mode indicators so users know when signal data is unavailable
4. Unit tests for the new setup flow

## 1. Infrastructure Fixes

### 1a. App Group Entitlement

Add to `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements` and `project.yml`:

```
com.apple.security.application-groups: ["group.com.blakemiller.netmonitor"]
```

Without this, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` — all shared container reads/writes silently fail.

### 1b. LSApplicationQueriesSchemes

Add to Info.plist properties in `project.yml`:

```yaml
LSApplicationQueriesSchemes:
  - shortcuts
```

Without this, `UIApplication.shared.canOpenURL(shortcuts://...)` always returns `false` on iOS 9+ — `checkAvailability()` never reports the shortcut as available.

### 1c. Regenerate xcodeproj

Run `xcodegen generate` after project.yml changes.

## 2. WiFi Shortcut Setup View

New file: `NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift`

### States

```
enum SetupState {
    case install      // Explain feature + install button + manual instructions
    case testing      // Running a test measurement
    case success      // Green checkmark, shortcut works
    case failed       // Test failed, retry or skip
}
```

### Layout (install state)

- WiFi icon + "Wi-Fi Signal Setup" title
- Brief explanation: "Install a companion Shortcut to get accurate Wi-Fi signal readings (RSSI, noise, channel)"
- **"Add Shortcut" button** — opens iCloud link (stored in `AppSettings.shortcutInstallURL`, placeholder until Blake creates the shortcut)
- **Expandable "Build It Yourself"** — step-by-step: (1) Open Shortcuts app, (2) Create new shortcut named "Wi-Fi to NetMonitor", (3) Add "Get Network Details" action, (4) Add "Save File" action to App Group, (5) Add "Open URL" action with `netmonitor://wifi-result`
- **"Test Connection" button** — runs one `ShortcutsWiFiProvider.fetchWiFiSignal()` cycle
- **"Skip" link** — dismisses, continues with NEHotspotNetwork fallback

### Layout (success state)

- Green checkmark + "Wi-Fi Signal Ready!"
- Shows test reading: SSID, RSSI (dBm), Channel, Band
- "Start Surveying" button dismisses sheet

### Presentation

- Sheet presented from `HeatmapSurveyView` when starting a survey and `ShortcutsWiFiProvider.isAvailable == false`
- Also accessible from sidebar sheet via "Wi-Fi Setup" button
- Remembers dismissal via `AppSettings` key `hasSeenShortcutSetup` so it doesn't nag

### Accessibility Identifiers

- `shortcutSetup_button_addShortcut`
- `shortcutSetup_button_buildYourself`
- `shortcutSetup_button_test`
- `shortcutSetup_button_skip`
- `shortcutSetup_button_startSurveying`
- `shortcutSetup_label_result`
- `shortcutSetup_screen`

## 3. Fallback Mode Indicators

### Signal HUD enhancement

When `ShortcutsWiFiProvider.isAvailable == false`:
- Show grey wifi.slash icon instead of colored signal icon
- Display "No Signal Data" instead of dBm value

### Sidebar sheet banner

When using NEHotspotNetwork fallback:
- Persistent banner: "Install Wi-Fi Shortcut for signal data" with tap-to-setup action

## 4. Tests

Unit tests in `Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift`:

- Setup state transitions: install -> testing -> success / failed
- Skip flow saves `hasSeenShortcutSetup` preference
- Fallback mode indicator logic (isAvailable == false shows correct HUD state)
- ShortcutsWiFiProvider: verify `checkAvailability()` returns false when URL scheme unavailable (existing behavior, confirm with test)

## Files Changed

| File | Change |
|------|--------|
| `project.yml` | Add App Group entitlement, LSApplicationQueriesSchemes |
| `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements` | Add application-groups array |
| `NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift` | **New** — setup sheet |
| `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift` | Present setup sheet, fallback HUD |
| `NetMonitor-iOS/Views/Heatmap/HeatmapSidebarSheet.swift` | Add "Wi-Fi Setup" button + fallback banner |
| `NetMonitor-iOS/Platform/AppSettings.swift` | Add `shortcutInstallURL`, `hasSeenShortcutSetup` keys |
| `Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift` | **New** — setup flow tests |

## Out of Scope

- Creating the actual companion Shortcut file (requires Shortcuts.app on device)
- Background measurement mode
- Visible network scanning (macOS-only, no iOS API)
