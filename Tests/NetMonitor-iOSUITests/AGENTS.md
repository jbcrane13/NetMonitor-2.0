<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetMonitor-iOSUITests

## Purpose
XCUITest suite for the iOS app target. Covers all tools, tabs, settings, device detail, network map, and multi-step interaction flows against a running app instance. `IOSUITestCase.swift` is the shared base class that provides a deterministic test harness.

## Key Files

| File | Description |
|------|-------------|
| `IOSUITestCase.swift` | Base class: launches app with `--uitesting --uitesting-reset` flags, installs system alert handler, provides `requireExists`, `waitForDisappearance`, `clearAndTypeText`, `scrollToElement`, `tapTrailingEdge` helpers |
| `ToolOutcomeUITests.swift` | Most comprehensive tool test (~400 lines): validates run/stop/clear outcome for Ping, Traceroute, PortScanner, DNS, WHOIS, WakeOnLAN, SpeedTest, Bonjour, WebBrowser; tests Set Target prefill across all target-aware tools |
| `InteractionFlowUITests.swift` | End-to-end interaction flows (~400 lines): tab switching, Set Target persistence, device detail navigation, settings round-trips |
| `DashboardUITests.swift` | Dashboard screen: device list visibility, scan button, status indicators |
| `DeviceDetailUITests.swift` | Device detail screen: field display, action buttons |
| `NetworkMapUITests.swift` | Network map: scan button, device node rendering |
| `TabNavigationUITests.swift` | Tab bar: all tabs reachable, selection state updates |
| `SettingsUITests.swift` | Settings screen: preference controls visible and interactive |
| `PingToolUITests.swift` | Ping tool screen: input validation, run/stop |
| `TracerouteToolUITests.swift` | Traceroute tool screen: input validation, hop list |
| `PortScannerToolUITests.swift` | Port scanner screen: preset picker, run/stop, progress |
| `DNSLookupToolUITests.swift` | DNS lookup screen: record type picker, result display |
| `WHOISToolUITests.swift` | WHOIS screen: domain input, result display |
| `WakeOnLANToolUITests.swift` | Wake-on-LAN screen: MAC validation inline feedback |
| `SpeedTestToolUITests.swift` | Speed test screen: duration picker, phase display |
| `BonjourDiscoveryToolUITests.swift` | Bonjour tool screen: discovery start/stop, service list |
| `SSLCertificateMonitorUITests.swift` | SSL monitor screen |
| `SubnetCalculatorToolUITests.swift` | Subnet calculator screen |
| `WebBrowserToolUITests.swift` | Web browser screen: URL validation, bookmarks visible |
| `WiFiHeatmapSurveyUITests.swift` | Wi-Fi heatmap survey screen |
| `GeoFenceSettingsUITests.swift` | Geo-fence settings screen |
| `MacPairingUITests.swift` | Mac pairing screen: discovered Mac list, connection flow |
| `TimelineUITests.swift` | Timeline/history screen |
| `ComponentsUITests.swift` | Shared UI components: glass cards, buttons, status indicators |
| `NetMonitorIOSUITests.swift` | Suite entry point / smoke test |

## For AI Agents

### Working In This Directory
- All test classes inherit from `IOSUITestCase`, not directly from `XCTestCase`.
- `IOSUITestCase` sets `continueAfterFailure = false` — a single failure stops the test immediately.
- The app launches with `--uitesting` and `--uitesting-reset` to disable auto-scan and monitoring. Tests that require clean state rely on this reset flag.
- Use `requireExists(_:timeout:message:)` instead of `XCTAssertTrue(element.waitForExistence(...))` — it returns the element for chaining.
- Use `waitForEither(_:timeout:)` when an action can produce multiple valid outcomes (e.g. a loading state OR a result state).
- Query elements by accessibility identifier using `app.descendants(matching: .any)[id]` (available as the `ui(_:)` helper in `ToolOutcomeUITests`).
- Accessibility IDs follow `{screen}_{element}_{descriptor}` (e.g. `pingTool_button_run`, `tools_card_ping`, `screen_pingTool`).

### Testing Requirements
```bash
xcodebuild test -scheme NetMonitor-iOS -only-testing:NetMonitor-iOSUITests
```
UI tests require a running simulator. They do not use mocks — they exercise the live app with real networking disabled via launch flags.

### Common Patterns

**Open a tool and assert screen:**
```swift
let card = ui("tools_card_ping")
scrollToElement(card)
card.tap()
requireExists(ui("screen_pingTool"), timeout: 8, message: "Ping screen should appear")
```

**Validate input then run:**
```swift
let runButton = requireExists(app.buttons["pingTool_button_run"], message: "Run button should exist")
XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")
clearAndTypeText("1.1.1.1", into: app.textFields["pingTool_input_host"])
XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")
```

**Wait for any valid outcome:**
```swift
XCTAssertTrue(
    waitForEither([app.buttons["Stop Ping"], app.otherElements["pingTool_section_results"]], timeout: 15),
    "Ping should transition to running or show results"
)
```

## Dependencies

### Internal
- iOS app target (under test) — must be built before running UI tests
- `IOSUITestCase` — all test classes in this directory extend it

<!-- MANUAL: -->
