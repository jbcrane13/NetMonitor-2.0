# Architecture

Architectural decisions, patterns discovered, and design rationale.

**What belongs here:** Key architectural decisions, discovered patterns, cross-cutting concerns.

---

## Heatmap Feature Architecture (from PRD)

### Package Placement
| Component | Location |
|-----------|----------|
| HeatmapSurveyModels | `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/` |
| HeatmapServiceProtocol | `Packages/NetMonitorCore/.../Services/ServiceProtocols.swift` |
| WiFiMeasurementEngine | `Packages/NetMonitorCore/.../Services/Heatmap/` |
| HeatmapRenderer | `Packages/NetMonitorCore/.../Services/Heatmap/` |
| macOS Heatmap UI | `NetMonitor-macOS/Views/Heatmap/` |
| iOS Heatmap UI | `NetMonitor-iOS/Views/Heatmap/` |
| iOS AR Services | `NetMonitor-iOS/Services/AR/` (canonical — not Platform/AR/) |

### Data Flow
1. Platform WiFiInfoService → WiFiMeasurementEngine → MeasurementPoint
2. [MeasurementPoint] → HeatmapRenderer → CGImage overlay
3. CGImage → SwiftUI Canvas (macOS/iOS Phase 1/2) or Metal texture (iOS Phase 3)

### Color Schemes
- **Phase 1/2 (default)**: green (>=-50 dBm) → yellow (-50 to -70) → red (<=-70)
- **Phase 3 (WiFiman)**: Supports all 5 visualization types with per-visualization normalization ranges:
  - signalStrength: -30 to -90 dBm
  - signalToNoise: 0 to 50 dB
  - downloadSpeed: 0 to 200 Mbps
  - uploadSpeed: 0 to 200 Mbps
  - latency: 0 to 100 ms (inverted — low is good)
  - Color gradient: blue → cyan → green → yellow → orange → red

### File Format (.netmonsurvey)
- Directory bundle (UTI: com.netmonitor.survey)
- Contains: survey.json, floorplan.png, heatmap-cache/ (optional)
- Conforms to: com.apple.package

### macOS Navigation
- Heatmap is a top-level sidebar item via NavigationSection enum in NetMonitorCore
- Case added to NavigationSection.allCases → automatically appears in sidebar

### iOS Navigation
- Heatmap entry in Tools tab via ToolType enum + ToolDestination
- Accessible from ToolsView grid

### IDW Interpolation
- Power parameter: p = 2.0 (Shepard's method)
- Default grid: 200x200
- Default opacity: 70%
- Minimum points: 3
- Performance: <500ms for 50 points, <2s for 200 points

### WiFiInfo.linkSpeed (Resolved)

WiFiInfo model now includes `linkSpeed: Double?`. MacWiFiInfoService populates it from `CWInterface.transmitRate()`. WiFiMeasurementEngine.buildMeasurementPoint() maps it through to MeasurementPoint.linkSpeed. Fixed in milestone phase1-macos (fix-macos-usertesting-failures).

### macOS ViewModel Extensions (Resolved)

HeatmapSurveyViewModel.swift was split into focused extensions in milestone misc-macos-cleanup (misc-macos-code-quality):
- `HeatmapSurveyViewModel+Undo.swift` — undo/redo stack management
- `HeatmapSurveyViewModel+Export.swift` — save, load, PDF export, new project creation
- `HeatmapSurveyViewModel+Calibration.swift` — calibration workflow and math

**Access control pattern:** Properties accessed by extension files use `var` (internal setter) instead of `private(set)`, with inline comments documenting the rationale. This is the standard Swift pattern for same-module extensions across files.

### FloorPlanLayoutHelper

`FloorPlanLayoutHelper` (enum with static methods) in `NetMonitor-macOS/Views/Heatmap/FloorPlanLayoutHelper.swift` is the canonical helper for floor plan coordinate math:
- `aspectFitSize(imageSize:containerSize:)` — compute aspect-fit display dimensions
- `imageOrigin(imageSize:containerSize:)` — compute centered image origin
- `normalizedPosition(screenPosition:imageOrigin:imageSize:)` — screen → 0-1 coords
- `absolutePosition(normalizedPosition:imageOrigin:imageSize:)` — 0-1 coords → screen

Used by CalibrationSheet. HeatmapCanvasView has duplicated private methods that should be migrated to use this helper.

### Logger Category: Heatmap

A `Logger.heatmap` category exists in `NetMonitor-macOS/Platform/Logging.swift` for heatmap feature logging. Some early features used `Logger.app` instead — new code should use `Logger.heatmap`.

### Concurrency Pattern: nonisolated(unsafe) for Non-Sendable Protocol Storage

When an `actor` needs to store a reference to a `@MainActor`-isolated protocol that isn't `Sendable` (e.g., `WiFiInfoServiceProtocol`, `SpeedTestServiceProtocol`), use `nonisolated(unsafe) let` for the stored property. This bypasses actor-isolation checking and is the Swift 6 equivalent of `@unchecked Sendable` for stored properties.

**When to use:** Only when the stored protocol is `@MainActor`-isolated and all accesses go through `await` (ensuring proper isolation at call sites).

**Example (from WiFiMeasurementEngine):**
```swift
public actor WiFiMeasurementEngine: HeatmapServiceProtocol {
    nonisolated(unsafe) let wifiService: any WiFiInfoServiceProtocol
    nonisolated(unsafe) let speedTestService: any SpeedTestServiceProtocol
    let pingService: any PingServiceProtocol // already Sendable — no workaround needed
}
```

**Preferred long-term fix:** Make the protocol itself `Sendable` (add `Sendable` requirement). This eliminates the need for `nonisolated(unsafe)`. The workaround is acceptable when modifying the protocol is outside the current feature scope.

### Phase 2 AR Architecture

#### AR Session Manager
`ARSessionManager` in `NetMonitor-iOS/Services/AR/ARSessionManager.swift` handles ARKit lifecycle. It contains model types colocated in the same file: `ARDeviceCapability`, `ARSessionState`, `ARSurfaceType`, `DetectedSurface`, `CameraPermissionStatus`. No protocol abstraction exists — ViewModel depends directly on concrete class.

#### Floor/Ceiling Classification Heuristic
AR surface classification uses `anchor.center.y < 0.3` to distinguish floor from ceiling. This is relative to the AR session origin (typically chest/hand height). A real floor is at y ≈ -0.8 to -1.2, so this threshold may need tuning on real devices. Located in `ARSessionManager.swift` line ~253.

#### MeshClassification RawValues vs ARKit
`MeshClassification` enum in `FloorPlanGenerationPipeline.swift` has rawValues **intentionally swapped** for door and window compared to Apple's `ARMeshClassification`:
- Our enum: `window = 6`, `door = 7`
- Apple's: `door = 6`, `window = 7`
The `mapARMeshClassification()` function handles the correct mapping. **Do NOT use `MeshClassification(rawValue:)` directly with ARKit values** — always use the mapper function.

#### Floor Plan Generation Pipeline
7-step pipeline in `FloorPlanGenerationPipeline.swift` (pure-function enum with static methods):
1. Height-filter vertices (0.5–2.5m above floor)
2. XZ projection to 2D
3. Compute bounds
4. Rasterize at 10px/m
5. Gaussian blur (sigma=2px) for wall continuity
6. Edge/contour detection for clean wall lines
7. Render as CGImage (black walls on white)

Non-LiDAR fallback uses ARPlaneAnchor vertical planes with point sampling along plane edges.

#### AR Coordinate Transform
`ARCoordinateTransform` (struct in `NetMonitor-iOS/Services/AR/ARCoordinateTransform.swift`) converts AR world coordinates to floor plan normalized coordinates:
```
floorPlanX = clamp((arX - mapMinX) / mapWidth, 0...1)
floorPlanY = clamp((arZ - mapMinZ) / mapHeight, 0...1)
```
Note: AR Y axis is up, so XZ plane maps to floor plan XY.

### Phase 3 Rendering: CPU-Based Pixel Manipulation

The Phase 3 real-time renderer (`HeatmapMetalRenderer`) uses CPU-based pixel arrays for all rendering (map rasterization, Gaussian splat heatmap, alpha compositing) despite its Metal-sounding name. Metal GPU objects are allocated but unused — all work happens on `[UInt8]` pixel buffers composited at 10Hz.

**Rationale:** CPU rendering was chosen over Metal compute shaders because 2D incremental pixel updates at 10Hz are well within CPU capability on modern iOS devices, and avoids the complexity of .metal shader files and GPU buffer management.

**Performance consideration:** The compositing loop iterates all 4,194,304 pixels (2048²) per frame on the main thread. For future optimization, consider moving compositing to a background queue.

### Phase 3 Thermal Management Policy

`ScanThermalManager` in `NetMonitor-iOS/Services/AR/ScanThermalManager.swift` maps `ProcessInfo.ThermalState` to scan-specific actions:

| Thermal State | Action | Detail |
|---------------|--------|--------|
| `.nominal` | Continue normally | All pipelines at full rate |
| `.fair` | Continue normally | No changes |
| `.serious` | Reduce mesh processing | Skip every other mesh update tick |
| `.critical` | Auto-pause scan | Pause all pipelines, notify user |

The manager observes `ProcessInfo.thermalStateDidChangeNotification` and publishes recommended actions. The ViewModel applies throttling by checking `shouldSkipMeshUpdate()` on each render tick.
