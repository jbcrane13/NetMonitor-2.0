---
name: ui-smoke-test
description: Run the iOS functional smoke test suite on the remote Mac mini. Verifies all tools, dashboard, network map, settings, and timeline produce correct outcomes with screenshot capture at each verification point.
disable-model-invocation: false
---

# iOS Functional Smoke Tests

Run the `FunctionalSmokeTests` suite to verify every major screen and tool produces correct **functional outcomes** — not just element existence. Each test captures a screenshot at the verification point for visual review.

## Quick Run

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
  -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:NetMonitor-iOSUITests/FunctionalSmokeTests \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO 2>&1"
```

**IMPORTANT:** Tests MUST run on the Mac mini via SSH. Never run `xcodebuild test` locally on the gateway host.

## What It Tests

| Test | Screen/Tool | Verifies |
|------|------------|----------|
| `test01` | Dashboard | Health score card, WAN info, anchor latency render; connection status shows MONITORING/OFFLINE |
| `test02` | Dashboard | Local devices card shows device IPs or SEARCHING state |
| `test03` | Dashboard | Settings gear navigates to Settings screen |
| `test04` | Network Map | Summary header shows gateway info; device grid or empty state |
| `test05` | Network Map | Scan button triggers visible scan activity |
| `test06` | Settings | Background refresh toggle changes state on tap |
| `test07` | Settings | Color scheme and accent color pickers exist |
| `test08` | Settings | About section displays a version number |
| `test09` | Timeline | Shows event list or empty state; filter sheet opens |
| `test10` | Ping | `127.0.0.1` returns latency in ms; min/avg/max statistics |
| `test11` | Traceroute | `1.1.1.1` shows hop rows with sequence numbers |
| `test12` | DNS Lookup | `example.com` returns A/AAAA records with IP addresses |
| `test13` | WHOIS | `example.com` shows registrar, dates, name servers |
| `test14` | Port Scanner | `127.0.0.1` shows open/closed/filtered port states |
| `test15` | Bonjour | Discovery shows services, empty state, or discovering indicator |
| `test16` | Subnet Calc | `192.168.1.0/24` returns 192.168.1.0 network, .255 broadcast, 254 hosts |
| `test17` | Speed Test | Runs through latency/download/upload phases; shows Mbps values |
| `test18` | World Ping | `google.com` shows location rows with ms latency |
| `test19` | SSL Monitor | `example.com` shows certificate validity, issuer, expiry days |
| `test20` | Wake on LAN | Invalid MAC rejected; valid MAC accepted; send shows success/error |
| `test21` | Geo Trace | `8.8.8.8` shows map with trace hops |
| `test22` | Web Browser | URL input enables Open button; bookmarks section renders |
| `test23` | Room Scanner | Setup screen shows LiDAR status, project name input, start button |

## Design Principles

- **Outcome verification**: Tests check result *content* (ms, Mbps, IP addresses, port states), not just that UI elements exist
- **Screenshot capture**: Every test calls `captureScreenshot(named:)` at its verification point — screenshots are attached to the Xcode test report as `XCTAttachment` with `.keepAlways` lifetime
- **Network tolerant**: All network-dependent tests accept either valid results OR meaningful error states (timeout, unreachable) so the suite doesn't flake in environments without internet
- **Sequential execution**: Tests are numbered `test01`–`test23` and run in order — this is intentional since some tests share navigation state
- **Happy paths only**: One path per tool, targeting the most common use case

## Reviewing Screenshots

After the test run, screenshots are embedded in the `.xcresult` bundle:

```bash
# Find the xcresult bundle
ssh mac-mini "find ~/Library/Developer/Xcode/DerivedData -name '*.xcresult' -newer /tmp/smoke-marker -maxdepth 5 2>/dev/null | head -1"

# Or open in Xcode for visual review
ssh mac-mini "open <path>.xcresult"
```

Each screenshot is named `NN_ScreenName_Context` (e.g., `10_Ping_Results`, `16_SubnetCalc_Results`) for easy identification in the Xcode test navigator.

## Adding a New Test

1. Add a new method to `Tests/NetMonitor-iOSUITests/FunctionalSmokeTests.swift`
2. Follow the naming pattern: `testNN_ToolNameVerifiesOutcome()`
3. Use `openTool(card:screen:)` to navigate, then assert on result content
4. Call `captureScreenshot(named:)` at the verification point
5. Call `goBackToTools()` at the end if the test opens a tool
6. Update the table above

### Test Pattern Template

```swift
func testNN_ToolNameVerifiesOutcome() {
    openTool(card: "tools_card_tool_name", screen: "screen_toolNameTool")

    // Input
    clearAndTypeText("input", into: app.textFields["toolName_input_field"])
    app.buttons["toolName_button_run"].tap()

    // Wait for outcome
    let gotResults = waitForEither([
        ui("toolName_section_results"),
        ui("toolName_error")
    ], timeout: 20)
    XCTAssertTrue(gotResults, "Tool should show results or error")

    // Verify outcome content
    if ui("toolName_section_results").exists {
        let hasExpected = screenContainsText("expected value")
        XCTAssertTrue(hasExpected, "Results should contain expected value")
    }

    captureScreenshot(named: "NN_ToolName_Results")
    goBackToTools()
}
```

## Infrastructure

- **Base class**: `IOSUITestCase` in `Tests/NetMonitor-iOSUITests/IOSUITestCase.swift`
- **Launch args**: `--uitesting`, `--uitesting-reset` (resets app state between runs)
- **Launch env**: `UITEST_MODE=1`, `XCUITest=1`
- **System alerts**: Auto-dismissed by `IOSUITestCase`'s `addUIInterruptionMonitor`
- **Accessibility IDs**: Follow `{screen}_{element}_{descriptor}` convention (see CLAUDE.md)
