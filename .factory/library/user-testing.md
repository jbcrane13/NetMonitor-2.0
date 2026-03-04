# User Testing

Testing surface: tools, URLs, setup steps, isolation notes, known quirks.

**What belongs here:** How to test the heatmap feature manually, testing tools, surfaces, known limitations.

---

## Testing Tools
- **macOS app**: Build locally with `xcodebuild -scheme NetMonitor-macOS`, launch from build dir or Xcode
- **iOS simulator**: Build with `xcodebuild -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'`
- **Unit tests**: Run via SSH on mac-mini (see services.yaml commands)

## Testing Surfaces

### macOS Heatmap
- Launch app → sidebar → Heatmap
- Import floor plan (any PNG/JPEG/PDF/HEIC image works as test floor plan)
- Click on canvas to place measurement points
- Verify heatmap overlay appears after 3+ points
- Test visualization type switching in toolbar dropdown
- Test save/load via File menu
- Test PDF export

### iOS Heatmap
- Launch in simulator → Tools tab → Wi-Fi Heatmap card
- Create new project → import floor plan from photo library
- Tap canvas to place measurement points
- Verify floating HUD and heatmap overlay

### AR Features (Phase 2/3) — SIMULATOR LIMITATIONS
- AR camera feed does NOT work in simulator
- ARKit world tracking does NOT function in simulator
- These features can only be fully tested on physical device
- For simulator: verify views load without crash, verify data model/serialization paths
- Unit tests are the primary verification method for AR pipeline logic

## Flow Validator Guidance: Foundation Unit Tests

The foundation milestone has no UI surface — all assertions are verified through:
1. **Unit tests** — Run via `cd Packages/NetMonitorCore && swift test --no-parallel`
2. **Build verification** — `xcodebuild -scheme NetMonitor-macOS -configuration Debug build` and same for iOS
3. **Structural inspection** — File system checks, grep for clean slate, project.yml inspection

**Isolation:** No isolation needed — all tests are deterministic, read-only, and independent. No shared mutable state, no network, no accounts.

**Test mapping:** Each VAL-FOUND assertion maps to specific test functions in:
- `HeatmapModelsTests.swift` — serialization round-trips (VAL-FOUND-001 to -014, -047, -049, -050)
- `HeatmapRendererTests.swift` — IDW, color mapping, performance (VAL-FOUND-015 to -030, -045, -046, -051)
- `WiFiMeasurementEngineTests.swift` — engine actor tests (VAL-FOUND-031 to -035)
- `SurveyFileManagerTests.swift` — bundle format tests (VAL-FOUND-036 to -042)

**Build assertions (VAL-FOUND-013, -034, -050, VAL-CROSS-007, -009):** Verified by successful build under `SWIFT_STRICT_CONCURRENCY: complete`.

**Clean slate (VAL-FOUND-044, VAL-CROSS-010):** Verified by grep for stale heatmap references outside new directories.

## Flow Validator Guidance: macOS Heatmap (phase1-macos)

This milestone tests the macOS heatmap feature through **code review + build verification + limited AppleScript automation**.

### Testing Approach
- **Primary: Code review** — Read the source files and verify the implementation matches each assertion's requirements.
- **Secondary: Build verification** — The macOS app builds successfully under `SWIFT_STRICT_CONCURRENCY: complete`.
- **Tertiary: AppleScript** — The app is running (PID confirmed). Use `osascript` to verify UI elements via System Events accessibility.

### App State
- The macOS app (NetMonitor-macOS) is running on this machine with a GUI session.
- Sidebar has 8 rows: [header], blakes-iphone-2.local (device), Network 192.168.3.0/24, Iphone, [separator], HEATMAP, TOOLS, SETTINGS.
- Navigate to Heatmap by selecting row 6: `osascript -e 'tell application "System Events" to tell process "NetMonitor-macOS" to tell outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 to select row 6'`
- The Heatmap view shows empty state with "Start a WiFi Survey" text and Import/New Project/Open Project buttons.

### Key Source Files
| File | Contents |
|------|----------|
| `NetMonitor-macOS/Views/Heatmap/HeatmapSurveyView.swift` | Main survey view, toolbar, empty state, keyboard shortcuts |
| `NetMonitor-macOS/Views/Heatmap/HeatmapCanvasView.swift` | Canvas with zoom/pan, measurement dots, coverage circles, heatmap overlay |
| `NetMonitor-macOS/Views/Heatmap/MeasurementSidebarView.swift` | Right sidebar: summary stats + point list |
| `NetMonitor-macOS/Views/Heatmap/CalibrationSheet.swift` | Two-point scale calibration modal |
| `NetMonitor-macOS/Views/Heatmap/MeasurementDetailPopover.swift` | Point inspection popover |
| `NetMonitor-macOS/Views/Heatmap/DrawFloorPlanView.swift` | Draw floor plan tool |
| `NetMonitor-macOS/Views/Heatmap/HeatmapProjectListView.swift` | Entry point wrapping HeatmapSurveyView |
| `NetMonitor-macOS/ViewModels/HeatmapSurveyViewModel.swift` | ViewModel (955 lines) — all business logic |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift` | IDW interpolation + color mapping |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/SurveyFileManager.swift` | .netmonsurvey bundle save/load |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/FloorPlanImporter.swift` | Floor plan import (NSOpenPanel, format support) |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/` | All shared model types |

### Sidebar Navigation (VAL-MAC-001)
The sidebar item is in the macOS app's NavigationSection enum. Check `NetMonitor-macOS/` for the NavigationSection or sidebar configuration. The Heatmap row is confirmed present at row 6 via AppleScript.

### Isolation Rules
- Flow validators access the same running app — avoid conflicting actions.
- All code review work is read-only and safe to parallelize.
- Do NOT modify source code, build products, or app state.
- Each flow writes its report to a separate `.json` file.

### Assertion Evidence Standards
For each assertion, provide:
1. **status**: "pass", "fail", or "blocked"
2. **evidence**: Specific code references (file:line) or AppleScript output showing the assertion is met.
3. **notes**: Any caveats about what couldn't be fully verified.

## Flow Validator Guidance: iOS Heatmap (phase1-ios)

This milestone tests the iOS heatmap feature through **code review + build verification + unit tests**.

### Testing Approach
- **Primary: Code review** — Read the source files and verify the implementation matches each assertion's requirements.
- **Secondary: Build verification** — The iOS target builds successfully under `SWIFT_STRICT_CONCURRENCY: complete` (verified: `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` succeeded).
- **Tertiary: Unit tests** — 1031 NetMonitorCore tests pass, covering shared heatmap models, renderer, measurement engine, and file format.
- **No simulator interaction** — This machine has no display session; iOS simulator cannot be launched interactively.

### Key Source Files — iOS
| File | Contents |
|------|----------|
| `NetMonitor-iOS/Views/Heatmap/HeatmapDashboardView.swift` | Dashboard: project list, empty state, new project |
| `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift` | Main survey view with canvas, HUD, toolbar |
| `NetMonitor-iOS/Views/Heatmap/FloorPlanCanvasView.swift` | Zoomable/pannable canvas with measurement markers |
| `NetMonitor-iOS/Views/Heatmap/FloorPlanImportView.swift` | PHPicker + UIDocumentPicker import |
| `NetMonitor-iOS/Views/Heatmap/CalibrationView.swift` | Two-point scale calibration |
| `NetMonitor-iOS/Views/Heatmap/VisualizationPickerView.swift` | Bottom sheet picker for viz types |
| `NetMonitor-iOS/Views/Heatmap/MeasurementDetailView.swift` | Tap-to-inspect popover |
| `NetMonitor-iOS/ViewModels/HeatmapDashboardViewModel.swift` | Dashboard VM — project list, create/delete |
| `NetMonitor-iOS/ViewModels/HeatmapSurveyViewModel.swift` | Survey VM — measurements, heatmap, save/load |
| `NetMonitor-iOS/ViewModels/FloorPlanImportViewModel.swift` | Import VM — PHPicker, doc picker, PDF rasterization |
| `NetMonitor-iOS/Views/Tools/ToolsView.swift` | Tools tab with heatmap card |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Enums.swift` | ToolType.wifiHeatmap enum case |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/` | Shared engine, renderer, file manager |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/` | Shared model types |

### Isolation Rules
- All code review work is read-only and safe to parallelize.
- Do NOT modify source code, build products, or app state.
- Each flow writes its report to a separate `.json` file in `.factory/validation/phase1-ios/user-testing/flows/`.

### Assertion Evidence Standards
For each assertion, provide:
1. **status**: "pass", "fail", or "blocked"
2. **evidence**: Specific code references (file:line or quoted code snippets) showing the assertion is met.
3. **notes**: Any caveats about what couldn't be fully verified (e.g., "requires physical device").

## Flow Validator Guidance: Phase 2 iOS — AR-Assisted Map Creation

This milestone tests the Phase 2 iOS AR-Assisted Map Creation feature through **code review + build verification + unit tests**.

### Testing Approach
- **Primary: Code review** — Read the source files and verify the implementation matches each assertion's requirements. This is the main verification method since AR features cannot run in simulator.
- **Secondary: Build verification** — The iOS target builds successfully under `SWIFT_STRICT_CONCURRENCY: complete` (verified: `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` succeeded).
- **Tertiary: Unit tests** — 1032 NetMonitorCore tests pass. iOS-specific tests include `FloorPlanGenerationPipelineTests` (40+ tests) and `ARCoordinateTransformTests` (12+ tests).
- **No simulator interaction** — AR camera/LiDAR do NOT work in simulator. AR features require physical device.

### Key Source Files — Phase 2 iOS
| File | Contents |
|------|----------|
| `NetMonitor-iOS/Services/AR/ARSessionManager.swift` | AR session lifecycle: config, start, stop, mesh/plane handling |
| `NetMonitor-iOS/Services/AR/ARCoordinateTransform.swift` | AR world → floor plan coordinate transform |
| `NetMonitor-iOS/Services/AR/FloorPlanGenerationPipeline.swift` | Mesh → floor plan: height filter, XZ projection, rasterize, blur, contour |
| `NetMonitor-iOS/Platform/ARWiFiSession.swift` | AR + WiFi combined session, LiDAR detection |
| `NetMonitor-iOS/Views/Heatmap/ARScanView.swift` | AR scan UI with camera feed, overlays, controls |
| `NetMonitor-iOS/Views/Heatmap/ARSurveyView.swift` | AR survey view with position tracking, measure button |
| `NetMonitor-iOS/Views/Heatmap/FloorPlanPreviewView.swift` | Real-time floor plan preview during scan |
| `NetMonitor-iOS/Views/Heatmap/HeatmapDashboardView.swift` | Dashboard with AR scan entry point |
| `NetMonitor-iOS/ViewModels/ARScanViewModel.swift` | AR scan ViewModel: session management, mesh accumulation |
| `NetMonitor-iOS/ViewModels/ARSurveyViewModel.swift` | AR survey ViewModel: position tracking, measure, tracking state |
| `NetMonitor-iOS/ViewModels/FloorPlanGenerationViewModel.swift` | Floor plan generation: pipeline control, coverage, preview |
| `Tests/NetMonitor-iOSTests/FloorPlanGenerationPipelineTests.swift` | Pipeline unit tests (40+ tests) |
| `Tests/NetMonitor-iOSTests/ARCoordinateTransformTests.swift` | Coordinate transform unit tests (12+ tests) |

### Isolation Rules
- All code review work is read-only and safe to parallelize.
- Do NOT modify source code, build products, or app state.
- Each flow writes its report to a separate `.json` file in `.factory/validation/phase2-ios/user-testing/flows/`.

### Assertion Evidence Standards
For each assertion, provide:
1. **status**: "pass", "fail", or "blocked"
2. **evidence**: Specific code references (file:line or quoted code snippets) showing the assertion is met. For unit test assertions, reference the test name.
3. **notes**: Any caveats about what couldn't be fully verified (all AR features require physical device for full verification).

### Assertion-to-File Mapping

**Group A: AR Session & Surface Detection**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR2-001 (entry point) | HeatmapDashboardView.swift, ARScanView.swift |
| VAL-AR2-002 (session startup) | ARSessionManager.swift, ARScanViewModel.swift |
| VAL-AR2-003 (LiDAR config) | ARSessionManager.swift |
| VAL-AR2-004 (non-LiDAR fallback) | ARSessionManager.swift |
| VAL-AR2-005 (walls blue) | ARScanView.swift, ARScanViewModel.swift |
| VAL-AR2-006 (floor green) | ARScanView.swift, ARScanViewModel.swift |
| VAL-AR2-028 (LiDAR detection) | ARWiFiSession.swift, ARSessionManager.swift |
| VAL-AR2-029 (non-LiDAR guidance) | ARScanView.swift |
| VAL-AR2-032 (camera permission) | ARScanView.swift, ARScanViewModel.swift |
| VAL-AR2-033 (ARKit unsupported) | ARScanView.swift, ARScanViewModel.swift |
| VAL-AR2-037 (scan instructions) | ARScanView.swift |

**Group B: Floor Plan Generation Pipeline**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR2-007 (real-time preview) | FloorPlanPreviewView.swift, FloorPlanGenerationViewModel.swift |
| VAL-AR2-008 (wall detection) | FloorPlanGenerationPipeline.swift |
| VAL-AR2-009 (room boundaries) | FloorPlanGenerationPipeline.swift |
| VAL-AR2-010 (LiDAR accuracy) | FloorPlanGenerationPipeline.swift |
| VAL-AR2-011 (non-LiDAR accuracy) | FloorPlanGenerationPipeline.swift |
| VAL-AR2-012 (completes <5s) | FloorPlanGenerationViewModel.swift |
| VAL-AR2-013 (correct dimensions) | FloorPlanGenerationPipeline.swift, FloorPlanGenerationPipelineTests.swift |
| VAL-AR2-014 (10px/m resolution) | FloorPlanGenerationPipeline.swift, FloorPlanGenerationPipelineTests.swift |
| VAL-AR2-015 (coverage progress) | FloorPlanGenerationViewModel.swift, ARScanView.swift |
| VAL-AR2-016 (missed area guidance) | FloorPlanGenerationPipeline.swift, ARScanView.swift |
| VAL-AR2-030 (memory <500MB) | FloorPlanGenerationPipeline.swift, FloorPlanGenerationViewModel.swift |
| VAL-AR2-031 (mesh lifecycle) | FloorPlanGenerationViewModel.swift |
| VAL-AR2-034 (AR session failure) | ARScanViewModel.swift |
| VAL-AR2-035 (AR cleanup) | ARSessionManager.swift, ARScanViewModel.swift |
| VAL-AR2-038 (position 20cm) | ARCoordinateTransform.swift, ARCoordinateTransformTests.swift |
| VAL-AR2-039 (Gaussian blur) | FloorPlanGenerationPipeline.swift, FloorPlanGenerationPipelineTests.swift |

**Group C: Survey Transition, Tracking & Editing**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR2-017 (done → survey) | ARScanViewModel.swift, ARSurveyView.swift |
| VAL-AR2-018 (Phase 1 compatible) | ARSurveyView.swift, HeatmapSurveyView.swift |
| VAL-AR2-019 (blue pulsing dot) | ARSurveyView.swift |
| VAL-AR2-020 (auto-placement) | ARSurveyViewModel.swift |
| VAL-AR2-021 (coordinate transform) | ARCoordinateTransform.swift, ARCoordinateTransformTests.swift |
| VAL-AR2-022 (tracking loss) | ARSurveyViewModel.swift |
| VAL-AR2-023 (manual fallback) | ARSurveyView.swift, ARSurveyViewModel.swift |
| VAL-AR2-024 (tracking recovery) | ARSurveyViewModel.swift |
| VAL-AR2-025 (drag walls P1) | ARSurveyView.swift |
| VAL-AR2-026 (delete walls P1) | ARSurveyView.swift |
| VAL-AR2-027 (room labels P1) | ARSurveyView.swift |
| VAL-AR2-036 (AR floor plan saved) | FloorPlanGenerationViewModel.swift, SurveyFileManagerTests |
| VAL-AR2-040 (multi-room P1) | ARSessionManager.swift |
| VAL-AR2-041 (mesh classification P1) | ARSessionManager.swift |

## Flow Validator Guidance: Phase 3 iOS — AR Continuous Scan

This milestone tests the Phase 3 iOS AR Continuous Scan feature through **code review + build verification + unit tests**.

### Testing Approach
- **Primary: Code review** — Read the source files and verify the implementation matches each assertion's requirements. This is the main verification method since AR features cannot run in simulator.
- **Secondary: Build verification** — The iOS target builds successfully under `SWIFT_STRICT_CONCURRENCY: complete` (verified: `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` succeeded with BUILD SUCCEEDED).
- **Tertiary: Unit tests** — 1032 NetMonitorCore tests pass. iOS-specific tests include `ContinuousCapturePipelineTests`, `ContinuousScanViewModelTests`, and `HeatmapMetalRendererTests`.
- **No simulator interaction** — AR camera/LiDAR/Metal GPU do NOT work in simulator. AR features require physical device.

### Key Source Files — Phase 3 iOS
| File | Contents |
|------|----------|
| `NetMonitor-iOS/Services/AR/ContinuousCapturePipeline.swift` | Concurrent AR + WiFi capture, 2Hz measurement, adaptive rate, downsampling |
| `NetMonitor-iOS/Services/AR/HeatmapMetalRenderer.swift` | Metal persistent textures, map/heatmap rendering, Gaussian splats, 10Hz |
| `NetMonitor-iOS/Services/AR/ScanThermalManager.swift` | Thermal monitoring, auto-pause at .serious/.critical |
| `NetMonitor-iOS/Services/AR/ARSessionManager.swift` | AR session lifecycle (shared with Phase 2) |
| `NetMonitor-iOS/Services/AR/ARCoordinateTransform.swift` | Coordinate transforms (shared with Phase 2) |
| `NetMonitor-iOS/Services/AR/FloorPlanGenerationPipeline.swift` | Floor plan generation (shared with Phase 2) |
| `NetMonitor-iOS/Platform/ARWiFiSession.swift` | AR + WiFi combined session, LiDAR detection |
| `NetMonitor-iOS/Views/Heatmap/ContinuousScanView.swift` | Main continuous scan UI: split-screen, controls |
| `NetMonitor-iOS/Views/Heatmap/ContinuousScanView+Subviews.swift` | Subviews: AR camera, 2D map, floating controls |
| `NetMonitor-iOS/Views/Heatmap/PostScanReviewView.swift` | Post-scan review: full-screen map, viz switching, export |
| `NetMonitor-iOS/Views/Heatmap/HeatmapDashboardView.swift` | Dashboard with continuous scan entry point |
| `NetMonitor-iOS/ViewModels/ContinuousScanViewModel.swift` | ViewModel: pipeline orchestration, pause/resume, finish |
| `Tests/NetMonitor-iOSTests/ContinuousCapturePipelineTests.swift` | Pipeline unit tests |
| `Tests/NetMonitor-iOSTests/ContinuousScanViewModelTests.swift` | ViewModel unit tests |
| `Tests/NetMonitor-iOSTests/HeatmapMetalRendererTests.swift` | Metal renderer unit tests |

### Isolation Rules
- All code review work is read-only and safe to parallelize.
- Do NOT modify source code, build products, or app state.
- Each flow writes its report to a separate `.json` file in `.factory/validation/phase3-ios/user-testing/flows/`.

### Assertion Evidence Standards
For each assertion, provide:
1. **status**: "pass", "fail", or "blocked"
2. **evidence**: Specific code references (file:line or quoted code snippets) showing the assertion is met. For unit test assertions, reference the test name.
3. **notes**: Any caveats about what couldn't be fully verified (all AR features require physical device for full verification).

### Assertion-to-File Mapping

**Group A: Capture Pipeline & Entry (VAL-AR3-001 to 005, 031, 042, 045)**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR3-001 (entry point) | HeatmapDashboardView.swift, ContinuousScanView.swift |
| VAL-AR3-002 (LiDAR requirement) | ContinuousScanViewModel.swift, HeatmapDashboardView.swift |
| VAL-AR3-003 (concurrent AR+WiFi) | ContinuousCapturePipeline.swift, ContinuousScanViewModel.swift |
| VAL-AR3-004 (2Hz measurement) | ContinuousCapturePipeline.swift |
| VAL-AR3-005 (adaptive rate) | ContinuousCapturePipeline.swift |
| VAL-AR3-031 (downsampling) | ContinuousCapturePipeline.swift |
| VAL-AR3-042 (pipeline sync) | ContinuousCapturePipeline.swift |
| VAL-AR3-045 (cleanup) | ContinuousScanViewModel.swift, ContinuousCapturePipeline.swift |

**Group B: Metal Rendering & Display (VAL-AR3-006 to 016, 032-035, 037, 043, 044)**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR3-006 (real-time map) | HeatmapMetalRenderer.swift, ContinuousScanView.swift |
| VAL-AR3-007 (incremental growth) | HeatmapMetalRenderer.swift |
| VAL-AR3-008 (heatmap splats) | HeatmapMetalRenderer.swift |
| VAL-AR3-009 (WiFiman colors) | HeatmapMetalRenderer.swift, HeatmapRenderer.swift |
| VAL-AR3-010 (split-screen AR top) | ContinuousScanView.swift |
| VAL-AR3-011 (split-screen map bottom) | ContinuousScanView.swift, ContinuousScanView+Subviews.swift |
| VAL-AR3-012 (map zoom/pan) | ContinuousScanView+Subviews.swift |
| VAL-AR3-013 (pause/resume control) | ContinuousScanView+Subviews.swift, ContinuousScanViewModel.swift |
| VAL-AR3-014 (signal badge) | ContinuousScanView+Subviews.swift |
| VAL-AR3-015 (point count/coverage) | ContinuousScanView+Subviews.swift |
| VAL-AR3-016 (finish scan button) | ContinuousScanView+Subviews.swift |
| VAL-AR3-032 (Metal textures) | HeatmapMetalRenderer.swift |
| VAL-AR3-033 (map texture) | HeatmapMetalRenderer.swift |
| VAL-AR3-034 (heatmap texture) | HeatmapMetalRenderer.swift |
| VAL-AR3-035 (10Hz render) | HeatmapMetalRenderer.swift |
| VAL-AR3-037 (walking path) | ContinuousScanView+Subviews.swift, ContinuousScanViewModel.swift |
| VAL-AR3-043 (position dot both views) | ContinuousScanView.swift, ContinuousScanView+Subviews.swift |
| VAL-AR3-044 (viewport auto-center) | ContinuousScanView+Subviews.swift |

**Group C: Pause/Resume, Finish, Performance & Errors (VAL-AR3-017 to 030, 036, 038-041, 046-048)**
| Assertion | Primary Files |
|-----------|--------------|
| VAL-AR3-017 (pause stops all) | ContinuousScanViewModel.swift |
| VAL-AR3-018 (resume relocalization) | ContinuousScanViewModel.swift |
| VAL-AR3-019 (data continuity) | ContinuousScanViewModel.swift |
| VAL-AR3-020 (IDW refinement) | ContinuousScanViewModel.swift, HeatmapRenderer.swift |
| VAL-AR3-021 (progress indicator) | ContinuousScanViewModel.swift, PostScanReviewView.swift |
| VAL-AR3-022 (floor plan cleanup) | ContinuousScanViewModel.swift, FloorPlanGenerationPipeline.swift |
| VAL-AR3-023 (saves as SurveyProject) | ContinuousScanViewModel.swift |
| VAL-AR3-024 (post-scan viz switching) | PostScanReviewView.swift |
| VAL-AR3-025 (full-screen review) | PostScanReviewView.swift |
| VAL-AR3-026 (CPU <60%) | ContinuousCapturePipeline.swift, HeatmapMetalRenderer.swift |
| VAL-AR3-027 (GPU <40%) | HeatmapMetalRenderer.swift |
| VAL-AR3-028 (memory <600MB) | ContinuousCapturePipeline.swift |
| VAL-AR3-029 (battery <15%/30min) | ContinuousCapturePipeline.swift, HeatmapMetalRenderer.swift |
| VAL-AR3-030 (thermal management) | ScanThermalManager.swift, ContinuousScanViewModel.swift |
| VAL-AR3-036 (AP roaming overlay) | ContinuousScanViewModel.swift, ContinuousScanView+Subviews.swift |
| VAL-AR3-038 (coverage completeness) | ContinuousScanView+Subviews.swift, ContinuousScanViewModel.swift |
| VAL-AR3-039 (AR session failure) | ContinuousScanViewModel.swift |
| VAL-AR3-040 (WiFi pipeline failure) | ContinuousScanViewModel.swift |
| VAL-AR3-041 (memory pressure) | ContinuousScanViewModel.swift, ContinuousCapturePipeline.swift |
| VAL-AR3-046 (wall accuracy 15cm) | FloorPlanGenerationPipeline.swift, HeatmapMetalRenderer.swift |
| VAL-AR3-047 (real-time vs post-scan 5dBm) | HeatmapMetalRendererTests.swift, HeatmapRenderer.swift |
| VAL-AR3-048 (AP boundary 2m) | ContinuousScanViewModel.swift |

## Known Limitations
- iOS NEHotspotNetwork requires precise location permission + Wi-Fi connection — returns nil in simulator
- macOS CoreWLAN requires actual Wi-Fi hardware — works on mac-mini but values may vary
- AR features require physical device with camera/LiDAR
- Speed test (active scan) requires network access — mock for unit tests

## Test Floor Plan Images
- Use any PNG/JPEG image as a test floor plan (e.g., a simple rectangle drawing)
- For calibration testing: use an image with known dimensions
