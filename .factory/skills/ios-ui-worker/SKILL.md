---
name: ios-ui-worker
description: Builds iOS SwiftUI views, ViewModels, platform services, and AR features for the heatmap feature in NetMonitor-iOS.
---

# iOS UI Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Use for features that involve:
- iOS SwiftUI views in `NetMonitor-iOS/Views/Heatmap/` or `NetMonitor-iOS/Views/Tools/`
- iOS ViewModels in `NetMonitor-iOS/ViewModels/`
- iOS platform services in `NetMonitor-iOS/Platform/` (e.g., NEHotspotNetwork, ARKit)
- iOS navigation (Tools tab, ToolDestination)
- AR session management, floor plan generation, Metal rendering
- Unit tests for iOS ViewModels and AR pipeline logic

## Work Procedure

### Step 1: Understand the Feature
- Read the feature description, preconditions, expectedBehavior, and verificationSteps
- Read `AGENTS.md` for coding conventions and boundaries
- Read `.factory/library/architecture.md` for package placement
- Study existing iOS patterns:
  - `NetMonitor-iOS/Views/Tools/` for tool view structure
  - `NetMonitor-iOS/ViewModels/` for ViewModel pattern
  - `NetMonitor-iOS/Views/Tools/ToolsView.swift` for navigation/ToolDestination enum
  - `NetMonitor-iOS/Platform/Theme.swift` and `GlassCard.swift` for liquid glass styling

### Step 2: Write ViewModel/Logic Tests First (TDD — Red Phase)
- Create test file in `Tests/NetMonitor-iOSTests/`
- Use Swift Testing framework
- Test ViewModels with mock services
- For AR pipeline logic: test coordinate transforms, height filtering, rasterization math — these are pure functions that can be tested without AR hardware
- Tests must compile but fail initially

### Step 3: Implement ViewModel (Green Phase)
- `@MainActor @Observable final class` pattern
- `private(set) var` for observable state
- Injected dependencies via protocol
- Production defaults in init
- Error surfaced as `errorMessage: String?`

### Step 4: Implement Views
- SwiftUI views following liquid glass theme
- Use `GlassCard`, `GlassButton`, `Theme` from existing components
- Views contain NO business logic
- For floor plan canvas: SwiftUI Canvas with gesture modifiers
- For AR views: wrap ARView in UIViewRepresentable
- Accessibility identifiers: `{screen}_{element}_{descriptor}`
- For navigation: add ToolDestination case in ToolsView.swift, add tool entry

### Step 5: Implement Platform Services (if needed)
- iOS services in `NetMonitor-iOS/Platform/`
- NEHotspotNetwork: requires precise location + entitlement (already configured)
- ARKit: ARWorldTrackingConfiguration, handle LiDAR vs non-LiDAR
- Metal: compute shaders for Phase 3 rendering pipeline
- Cache NEHotspotNetwork results for >=1s between polls

### Step 6: Verify
- `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` — must succeed
- `xcodebuild -scheme NetMonitor-macOS -configuration Debug build` — must also succeed (no regression)
- `swiftlint lint --quiet` — zero errors
- `swiftformat .` — clean
- Run iOS tests: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests 2>&1 | tail -30"`
- **Build to simulator**: If possible, build and verify the app launches in simulator. AR features won't work in simulator but UI should load without crashes.

### Step 7: Update Shared State
- Update `.factory/library/architecture.md` if you made architectural decisions
- Update `.factory/library/user-testing.md` if you found testing surface details

## AR-Specific Guidelines

### ARKit Configuration
```swift
let config = ARWorldTrackingConfiguration()
if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
    config.sceneReconstruction = .meshWithClassification  // LiDAR
}
config.planeDetection = [.horizontal, .vertical]
config.environmentTexturing = .automatic
```

### Floor Plan Generation Pipeline (Phase 2)
1. Accumulate ARMeshAnchor geometry
2. Height-filter vertices (0.5m to 2.5m above floor)
3. Project to XZ plane (top-down 2D)
4. Rasterize at 10px/m resolution
5. Gaussian blur (sigma=2px) for wall continuity
6. Edge/contour detection for clean wall lines
7. Render as CGImage (black walls on white background)

### Metal Rendering (Phase 3)
- Persistent 2048x2048 RGBA textures (map + heatmap)
- Incremental updates only (new mesh + new measurements)
- Render loop at 10Hz via CADisplayLink or Timer
- Gaussian splat for real-time coloring (radius ~1.5m)

### Testing AR Code
- AR session code cannot run in simulator
- Test all PURE LOGIC separately: coordinate transforms, height filters, rasterization, color mapping, downsampling
- Wrap AR-dependent code behind protocols for testability
- Use mock ARSession data in tests

## Example Handoff

```json
{
  "salientSummary": "Built iOS heatmap blueprint survey: floor plan import (PHPicker + UIDocumentPicker), zoomable canvas with measurement points and heatmap overlay, floating RSSI HUD with liquid glass styling, 3 visualization types (signal/download/latency), project save/load to Documents. Added ToolDestination.wifiHeatmap and dashboard card. Wrote 22 ViewModel tests. iOS and macOS both build. Launched in simulator — dashboard loads, floor plan imports, tap places dots, heatmap renders after 3 points.",
  "whatWasImplemented": "Created: Views/Heatmap/HeatmapDashboardView.swift, Views/Heatmap/HeatmapSurveyView.swift, Views/Heatmap/HeatmapCanvasView.swift, Views/Heatmap/FloatingRSSIHUD.swift, ViewModels/HeatmapSurveyViewModel.swift. Modified: ToolsView.swift (added .wifiHeatmap case + ToolItem), Enums.swift (added ToolType.wifiHeatmap).",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "swiftlint lint --quiet 2>&1 | grep -c 'error'", "exitCode": 0, "observation": "0 errors"}
    ],
    "interactiveChecks": [
      {"action": "Launched iOS simulator, tapped Tools tab", "observed": "Wi-Fi Heatmap card visible with correct icon and liquid glass styling"},
      {"action": "Tapped heatmap card, created new project", "observed": "Project creation view with name field and floor plan import options"},
      {"action": "Imported PNG floor plan, tapped 4 locations", "observed": "Blue markers appeared, heatmap overlay rendered after 3rd tap with correct colors"}
    ]
  },
  "tests": {
    "added": [
      {"file": "Tests/NetMonitor-iOSTests/HeatmapSurveyViewModelTests.swift", "cases": [
        {"name": "testTapPlacesMeasurementPoint", "verifies": "Tap adds point with correct floor plan coordinates"},
        {"name": "testHeatmapRendersAfterThreePoints", "verifies": "Overlay appears when 3+ points exist"},
        {"name": "testVisualizationSwitch", "verifies": "Switching type updates rendered overlay"}
      ]}
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature requires macOS-specific code (wrong worker type)
- Core model changes needed in NetMonitorCore (use swift-core-worker)
- ARKit API has changed or is unavailable (iOS version mismatch)
- Metal shader compilation fails and cannot be debugged
- Feature depends on core services that don't exist yet (check preconditions)
- iOS build is broken due to unrelated issues
