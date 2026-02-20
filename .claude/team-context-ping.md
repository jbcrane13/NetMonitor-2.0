# Enhanced Ping — Team Context

## Project
NetMonitor 2.0 monorepo — xcodebuild project: `NetMonitor-2.0.xcodeproj`
- iOS scheme: `NetMonitor-iOS` (destination: `platform=iOS Simulator,name=iPhone 17 Pro`)
- macOS scheme: `NetMonitor-macOS`

## Beads (issue tracker)
- NM2-3pd: Enhanced ping with 20-count default and latency graph (parent feature)
- NM2-3pd.1: ✅ Initial implementation (done)
- NM2-3pd.2: Review and harden ping implementation
- NM2-3pd.3: Unit tests for enhanced ping
- NM2-3pd.4: UI tests for enhanced ping experience

## Key Files
### iOS
- `NetMonitor-iOS/Views/Tools/PingToolView.swift` — SwiftUI view with Charts (LineMark + AreaMark), stats cards, count picker
- `NetMonitor-iOS/ViewModels/PingToolViewModel.swift` — @Observable VM with live stats, chartYAxisMax P95 scaling
- `Tests/NetMonitor-iOSTests/PingToolViewModelTests.swift` — existing unit tests (99 lines)
- `Tests/NetMonitor-iOSUITests/PingToolUITests.swift` — existing UI tests (119 lines)

### macOS
- `NetMonitor-macOS/Views/Tools/PingToolView.swift` — inline state management (no separate VM), Charts, ToolSheetContainer
- `Tests/NetMonitor-macOSTests/ShellPingParserTests.swift` — parser tests (182 lines)
- `Tests/NetMonitor-macOSUITests/PingToolUITests.swift` — existing UI tests (82 lines)

### Shared
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/PingService.swift` — PingServiceProtocol, async stream
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/PingResult.swift` — PingResult, PingStatistics

## Testing Framework
- Unit tests: Swift Testing (`@Test`, `#expect`, `@Suite`)
- UI tests: XCTest (`XCTestCase`, `XCUIApplication`)
- Mock: `MockPingService` conforming to `PingServiceProtocol`

## Build Commands
```
xcodebuild -project NetMonitor-2.0.xcodeproj -scheme NetMonitor-macOS -configuration Debug build
xcodebuild -project NetMonitor-2.0.xcodeproj -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project NetMonitor-2.0.xcodeproj -scheme NetMonitor-macOS test
xcodebuild -project NetMonitor-2.0.xcodeproj -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Accessibility IDs (existing)
### iOS
- `pingTool_input_host`, `pingTool_picker_count`, `pingTool_button_run`
- `pingTool_section_results`, `pingTool_card_statistics`, `pingTool_button_clear`
- Chart: `pingTool_chart_latency` (add if missing)
- Stats: `pingTool_stat_min`, `pingTool_stat_avg`, `pingTool_stat_max` (add if missing)

### macOS
- `ping_textfield_host`, `ping_picker_count`, `ping_button_run`, `ping_button_close`
- Chart: `ping_chart_latency` (add if missing)

## Close beads when done
```
bd close NM2-3pd.2 -m "Implementation reviewed and hardened"
bd close NM2-3pd.3 -m "Unit tests added"  
bd close NM2-3pd.4 -m "UI tests added"
bd close NM2-3pd -m "Enhanced ping feature complete with tests"
```
