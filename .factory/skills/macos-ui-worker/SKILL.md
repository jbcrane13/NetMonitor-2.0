---
name: macos-ui-worker
description: Builds macOS SwiftUI views, ViewModels, and platform services for the heatmap feature in NetMonitor-macOS.
---

# macOS UI Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Use for features that involve:
- macOS SwiftUI views in `NetMonitor-macOS/Views/Heatmap/`
- macOS ViewModels in `NetMonitor-macOS/ViewModels/`
- macOS platform services in `NetMonitor-macOS/Platform/` (e.g., CoreWLAN integration)
- macOS navigation (sidebar, toolbar)
- macOS-specific UI (NSSavePanel, NSOpenPanel, drag-and-drop)
- PDF export
- Unit tests for macOS ViewModels

## Work Procedure

### Step 1: Understand the Feature
- Read the feature description, preconditions, expectedBehavior, and verificationSteps
- Read `AGENTS.md` for coding conventions and boundaries
- Read `.factory/library/architecture.md` for package placement
- Study 1-2 existing macOS Views and ViewModels for patterns:
  - Check `NetMonitor-macOS/Views/` for SwiftUI patterns
  - Check `NetMonitor-macOS/ViewModels/` for ViewModel pattern
  - Check `NetMonitor-macOS/Views/SidebarView.swift` for navigation pattern

### Step 2: Write ViewModel Tests First (TDD — Red Phase)
- Create test file in `Tests/NetMonitor-macOSTests/`
- Use Swift Testing framework
- Test ViewModel with mock services:
  ```swift
  @Suite("HeatmapSurveyViewModel") @MainActor
  struct HeatmapSurveyViewModelTests {
      func makeVM() -> HeatmapSurveyViewModel {
          HeatmapSurveyViewModel(measurementEngine: MockWiFiMeasurementEngine())
      }
      @Test func addMeasurementPointUpdatesState() async { ... }
  }
  ```
- Cover all expectedBehavior items from the feature
- Tests must compile but fail initially

### Step 3: Implement ViewModel (Green Phase)
- `@MainActor @Observable final class` pattern
- `private(set) var` for observable state
- Injected dependencies via protocol (`any WiFiMeasurementEngineProtocol`)
- Production defaults in init
- `func` methods are `async` where appropriate
- Error surfaced as `errorMessage: String?`

### Step 4: Implement Views
- SwiftUI views in `NetMonitor-macOS/Views/Heatmap/`
- Views contain NO business logic — delegate to ViewModel
- Use SwiftUI Canvas for heatmap rendering (NOT NSView/CALayer)
- Follow existing app patterns for:
  - NavigationSplitView / sidebar integration
  - Toolbar items
  - Sheet presentations
  - Accessibility identifiers: `{screen}_{element}_{descriptor}`
- For floor plan canvas: use `Canvas { context, size in ... }` with `MagnifyGesture` and `DragGesture` for zoom/pan
- For drag-and-drop: use `.onDrop(of:)` modifier with UTType.image

### Step 5: Implement Platform Services (if needed)
- macOS services in `NetMonitor-macOS/Platform/`
- CoreWLAN usage: `import CoreWLAN`, `CWWiFiClient.shared().interface()`
- Follow existing `NetworkInfoService.swift` patterns

### Step 6: Verify
- `xcodebuild -scheme NetMonitor-macOS -configuration Debug build` — must succeed
- `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` — must also succeed (no regression)
- `swiftlint lint --quiet` — zero errors
- `swiftformat .` — clean
- Run macOS tests: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:NetMonitor-macOSTests 2>&1 | tail -30"`
- **Manual verification**: Build and launch the macOS app. Navigate to the heatmap feature. Verify the UI renders correctly, interactions work, and there are no layout issues. Record what you tested in `interactiveChecks`.

### Step 7: Update Shared State
- Update `.factory/library/architecture.md` if you made architectural decisions
- Update `.factory/library/user-testing.md` if you found testing surface details

## Example Handoff

```json
{
  "salientSummary": "Built the macOS heatmap survey view with floor plan import (PNG/JPEG/PDF/HEIC + drag-and-drop), SwiftUI Canvas for zoomable/pannable floor plan + heatmap overlay, measurement sidebar with point list and summary stats, and toolbar controls (mode toggle, RSSI badge, visualization picker). Added HeatmapSurveyViewModel with undo/redo stack. Wrote 28 ViewModel tests, all passing. Built and launched the macOS app — sidebar shows Heatmap item, floor plan imports and renders, clicking places measurement dots.",
  "whatWasImplemented": "Created: Views/Heatmap/HeatmapSurveyView.swift (split view with canvas + sidebar), Views/Heatmap/HeatmapCanvasView.swift (SwiftUI Canvas with zoom/pan + measurement dots + heatmap overlay), Views/Heatmap/MeasurementSidebarView.swift, Views/Heatmap/CalibrationSheet.swift, ViewModels/HeatmapSurveyViewModel.swift. Modified: SidebarView.swift (added .heatmap case), NavigationSection.swift (added case).",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "swiftlint lint --quiet 2>&1 | grep -c 'error'", "exitCode": 0, "observation": "0 errors"}
    ],
    "interactiveChecks": [
      {"action": "Launched macOS app, clicked Heatmap in sidebar", "observed": "Heatmap survey view loaded with empty state prompting floor plan import"},
      {"action": "Imported test PNG floor plan via NSOpenPanel", "observed": "Floor plan rendered on canvas at correct aspect ratio, zoomable via trackpad pinch"},
      {"action": "Clicked 5 locations on floor plan", "observed": "5 blue dots appeared, measurement sidebar populated with RSSI/SSID/timestamp for each, heatmap overlay appeared after 3rd point with green/yellow/red gradient"}
    ]
  },
  "tests": {
    "added": [
      {"file": "Tests/NetMonitor-macOSTests/HeatmapSurveyViewModelTests.swift", "cases": [
        {"name": "testAddMeasurementPoint", "verifies": "Click adds point to project and triggers re-render"},
        {"name": "testUndoRemovesLastPoint", "verifies": "Cmd+Z removes last point"},
        {"name": "testVisualizationTypeSwitch", "verifies": "Changing type updates rendered overlay"}
      ]}
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature requires iOS-specific code (wrong worker type)
- Core model changes needed in NetMonitorCore (use swift-core-worker)
- macOS build is broken due to unrelated issues
- NSOpenPanel or NSSavePanel crashes in headless environment (may need workaround)
- Feature depends on core services that don't exist yet (check preconditions)
