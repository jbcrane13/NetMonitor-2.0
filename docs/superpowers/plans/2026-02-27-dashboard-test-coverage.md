# macOS Dashboard Test Coverage Plan

## Project: NetMonitor-2.0
## Date: 2026-02-27
## Focus: macOS dashboard redesign + WiFi Heatmap tool

## Current State
- Total tests: ~1,195 (1,006 functional, 242 shallow, 14 disabled)
- Dashboard unit tests: 0 for all 6 new cards
- WiFiHeatmapToolViewModel tests: 0
- DashboardModels (LatencyStats) tests: 0
- Silent failure paths: 3 locations (ISPHealthCard, ConnectivityCard, WiFiHeatmapToolVM)
- Key gaps: entire new dashboard has zero unit tests for card logic and ViewModels

## Coverage Areas

### Area 1: Fix Silent Failures + Error Surfacing Tests (Priority: P0)
- **Files to modify**: `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`, `NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift`, `NetMonitor-macOS/ViewModels/WiFiHeatmapToolViewModel.swift`
- **Files to create**: `Tests/NetMonitor-macOSTests/DashboardErrorSurfacingTests.swift`
- **Tests to write**:
  1. ISPHealthCard: replace empty `catch {}` with error state; test that error message is set on ISP lookup failure
  2. ConnectivityCard: replace `try? await loadISP()` with proper error handling; test error surfacing
  3. WiFiHeatmapToolVM: test that saveSurveys encode failure sets errorMessage; test that loadSurveys decode failure sets errorMessage
- **Test types**: unit (with MockURLProtocol for ISP service)
- **Estimated test count**: 6

### Area 2: DashboardModels Unit Tests (Priority: P1)
- **Files to create**: `Tests/NetMonitor-macOSTests/DashboardModelsTests.swift`
- **Tests to write**:
  1. LatencyStats init with empty histogram returns zero stats
  2. LatencyStats avg/min/max/jitter computation from known values
  3. LatencyStats packetLoss percentage calculation
  4. LatencyStats histogram bucket distribution
  5. LatencyStats with single sample
  6. LatencyStats with outliers
- **Test types**: unit (pure computation)
- **Estimated test count**: 8

### Area 3: WiFiHeatmapToolViewModel Unit Tests (Priority: P1)
- **Files to create**: `Tests/NetMonitor-macOSTests/WiFiHeatmapToolViewModelTests.swift`
- **Tests to write**:
  1. Initial state (isSurveying=false, surveys empty, colorScheme=thermal, etc.)
  2. startSurvey sets isSurveying=true and currentRSSI tracking
  3. stopSurvey sets isSurveying=false and saves survey to list
  4. recordDataPoint adds point with RSSI value at correct coordinates
  5. selectSurvey updates selectedSurveyID
  6. deleteSurvey removes survey and persists
  7. setCalibration stores CalibrationScale correctly
  8. clearCalibration nullifies calibration
  9. Persistence: saveSurveys round-trips through UserDefaults
  10. Persistence: loadSurveys restores from UserDefaults
  11. colorScheme changes are reflected in state
  12. displayOverlays set operations work correctly
- **Test types**: unit (isolated UserDefaults)
- **Dependencies**: WiFiHeatmapService protocol mock
- **Estimated test count**: 12

### Area 4: Dashboard Card Display Logic Tests (Priority: P1)
- **Files to create**: `Tests/NetMonitor-macOSTests/DashboardCardTests.swift`
- **Tests to write**:
  1. InternetActivityCard: BandwidthRange picker values map to correct date ranges
  2. HealthGaugeCard: score-to-color mapping (green >=80, yellow >=50, red <50)
  3. HealthGaugeCard: score bar widths proportional to component scores
  4. ActiveDevicesCard: devices sorted by latency (lowest first)
  5. ActiveDevicesCard: limited to 5 devices max
  6. ConnectivityCard: anchor ping pill labels match expected names
  7. ISPHealthCard: uptime segments bar reflects status history
- **Test types**: unit (model/computation logic extracted from views)
- **Estimated test count**: 7

### Area 5: WiFi Heatmap UI Tests (Priority: P2)
- **Files to create**: `Tests/NetMonitor-macOSUITests/WiFiHeatmapToolUITests.swift`
- **Tests to write**:
  1. WiFi Heatmap tool card exists in tools grid
  2. Opening WiFi Heatmap shows three-column layout
  3. New Survey button starts survey mode
  4. Stop Survey button stops survey mode
  5. Color scheme picker changes selection
  6. Overlay toggle buttons toggle state
  7. Close/back navigation works
- **Test types**: XCUITest (UI tests require XCTest, not Swift Testing)
- **Estimated test count**: 7

### Area 6: Dashboard Functional UI Tests (Priority: P2)
- **Files to modify**: `Tests/NetMonitor-macOSUITests/DashboardUITests.swift`
- **Tests to write**:
  1. InternetActivityCard: range picker changes chart display
  2. Start monitoring button label changes to "Stop"
  3. Stop monitoring button label changes to "Start"
  4. Add Target button shows AddTargetSheet
  5. AddTargetSheet: filling fields and clicking Add creates target
  6. Target status cards appear after adding target
  7. ISP health card shows ISP name (not dashes) when network available
- **Test types**: XCUITest
- **Estimated test count**: 7

## Execution Strategy
- Worker count: 3 (area 1+2 together, area 3+4 together, area 5+6 together)
- Worker assignments:
  - Worker 1: Areas 1+2 (silent failures + DashboardModels) — most critical
  - Worker 2: Areas 3+4 (WiFiHeatmapToolVM + card logic)
  - Worker 3: Areas 5+6 (UI tests)
- Dependencies: Area 1 (error surfacing fixes) should complete before Area 6 (UI tests that verify errors)

## Verification Criteria
- [ ] All tests build with `xcodebuild test -scheme NetMonitor-macOS`
- [ ] No existing tests broken
- [ ] Every dashboard card has at least one functional test
- [ ] WiFiHeatmapToolViewModel has tests for all 7 public methods
- [ ] Silent catch {} blocks replaced with error surfacing
- [ ] All new tests use Swift Testing (@Test, #expect) except UI tests (XCTest required)
