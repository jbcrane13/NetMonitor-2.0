<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitor-macOSUITests

## Purpose
XCUITest suite for the macOS app target. Covers sidebar navigation, all tool sheets, settings (all 7 tabs), targets, devices, dashboard, menu bar, and multi-step interaction flows. `MacOSUITestCase.swift` is the shared base class.

## Key Files

| File | Description |
|------|-------------|
| `MacOSUITestCase.swift` | Base class: launches app with `--uitesting` flag, waits for main window, provides `requireExists`, `waitForDisappearance`, `clearAndTypeText` (uses Cmd+A), `waitForEither`, `ui(_:)`, `navigateToSidebar(_:)`, `openTool(cardID:sheetElement:)`, `closeTool(closeButtonID:cardID:)` helpers |
| `MacOSToolOutcomeUITests.swift` | Most comprehensive tool test: run/stop/clear outcome for all macOS tools; validates input, state transitions, and result display |
| `MacOSInteractionFlowUITests.swift` | End-to-end flows: sidebar navigation sequences, target CRUD, settings persistence, network switching |
| `SettingsUITests.swift` | All 7 settings tabs (General, Monitoring, Notifications, Network, Data, Appearance, Companion): control visibility, toggle interaction, picker interaction, tab persistence, clear-data confirmation sheet |
| `ToolsViewUITests.swift` | All 8 tool cards in the Tools detail pane: card existence, open/close sheet lifecycle |
| `SidebarNavigationUITests.swift` | Sidebar: all sections reachable, selection updates detail pane, keyboard navigation |
| `DashboardUITests.swift` | Dashboard: status summary, target list, monitoring controls |
| `TargetsUITests.swift` | Targets list: add, delete, enable/disable targets |
| `DevicesUITests.swift` | Devices list: scan trigger, device rows, detail navigation |
| `NetworkSwitchingUITests.swift` | Network profile switching: profile picker, scan scoping |
| `MenuBarUITests.swift` | Menu bar: documents XCUITest popover limitation; tests app launch, main window, and menu bar item existence only |
| `PingToolUITests.swift` | Ping tool sheet |
| `TracerouteToolUITests.swift` | Traceroute tool sheet |
| `PortScannerToolUITests.swift` | Port scanner tool sheet |
| `DNSLookupToolUITests.swift` | DNS lookup tool sheet |
| `WHOISToolUITests.swift` | WHOIS tool sheet |
| `SpeedTestToolUITests.swift` | Speed test tool sheet |
| `WakeOnLanToolUITests.swift` | Wake-on-LAN tool sheet |
| `BonjourBrowserToolUITests.swift` | Bonjour browser tool sheet |
| `NetMonitorMacOSUITests.swift` | Suite entry point / smoke test |

## For AI Agents

### Working In This Directory
- All test classes inherit from `MacOSUITestCase` except `MenuBarUITests`, which extends `XCTestCase` directly (it does not use `--uitesting` flags).
- `MacOSUITestCase` sets `continueAfterFailure = false`.
- Sidebar navigation uses `navigateToSidebar(_:)` which taps `app.staticTexts["sidebar_{section}"]` and asserts `app.otherElements["detail_{section}"]` appears.
- Tool sheets are opened with `openTool(cardID:sheetElement:)` and closed with `closeTool(closeButtonID:cardID:)`.
- Use `ui(_:)` (wraps `app.descendants(matching: .any)[id]`) for elements that may be inside sheets or nested containers.
- `clearAndTypeText` on macOS uses Cmd+A to select all before typing — unlike iOS which counts delete keypresses.
- `MenuBarUITests` documents a known XCUITest limitation: the menu bar status item popover is outside the main window hierarchy and cannot be directly interacted with via XCUITest. Those tests verify app launch and macOS menu bar items only.

### Testing Requirements
```bash
xcodebuild test -scheme NetMonitor-macOS -only-testing:NetMonitor-macOSUITests
```
UI tests run against a built macOS app. They do not use mocks.

### Common Patterns

**Navigate to a sidebar section:**
```swift
navigateToSidebar("settings")
// asserts sidebar_settings tapped and detail_settings visible
```

**Open and close a tool sheet:**
```swift
openTool(cardID: "tools_card_ping", sheetElement: "pingTool_input_host")
closeTool(closeButtonID: "pingTool_button_close", cardID: "tools_card_ping")
```

**Wait for either of multiple valid outcomes:**
```swift
XCTAssertTrue(
    waitForEither([app.otherElements["pingTool_section_results"], app.buttons["Stop Ping"]], timeout: 15),
    "Ping should show results or running state"
)
```

**Settings tab navigation (all 7 tabs):**
```swift
// tabs: general, monitoring, notifications, network, data, appearance, companion
app.staticTexts["settings_tab_monitoring"].tap()
requireExists(app.popUpButtons["settings_picker_defaultInterval"], timeout: 3, message: "...")
```

## Dependencies

### Internal
- macOS app target (under test) — must be built before running UI tests
- `MacOSUITestCase` — all test classes in this directory extend it (except `MenuBarUITests`)

<!-- MANUAL: -->
