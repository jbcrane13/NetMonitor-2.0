# AR Continuous Heatmap — Redesign

**Date:** 2026-03-02
**Status:** Approved — ready for implementation

## Goal

Replace the existing AR heatmap mode (3D spheres in mid-air) with a WiFi Man-style continuous scanning mode: a colored grid projected flat onto the detected floor, filling in cell-by-cell as the user walks, with a bottom AP info bar and dBm color scale legend. NetMonitor's existing liquid glass visual style is preserved throughout.

---

## What Changes

| File | Action |
|------|--------|
| `NetMonitor-iOS/Platform/ARHeatmapSession.swift` | Delete → replace with `ARContinuousHeatmapSession.swift` |
| `NetMonitor-iOS/ViewModels/ARHeatmapSurveyViewModel.swift` | Delete → replace with `ARContinuousHeatmapViewModel.swift` |
| `NetMonitor-iOS/Views/Tools/ARHeatmapSurveyView.swift` | Delete → replace with `ARContinuousHeatmapView.swift` |
| `Tests/NetMonitor-iOSTests/ARHeatmapSurveyViewModelTests.swift` | Delete → replace with `ARContinuousHeatmapViewModelTests.swift` |
| `NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift` | Update: swap `ARHeatmapSurveyView` reference to `ARContinuousHeatmapView` |
| `project.yml` | Update file list |

Floor plan mode (`WiFiHeatmapSurveyView`), freeform mode, and all other heatmap infrastructure are untouched.

---

## AR Grid Mechanics

### Grid specification

- **Size:** 32 × 32 cells
- **Cell real-world size:** ~30 cm × 30 cm → total coverage area ~9.6 m × 9.6 m
- **Texture resolution:** 1024 × 1024 px (32 px per cell)
- **Anchor:** first detected ARKit horizontal plane (`.horizontal`)

### Startup sequence

1. ARKit world-tracking session starts with `planeDetection: [.horizontal]`
2. UI shows "Detecting floor..." with a subtle spinner
3. On first `ARSessionDelegate.session(_:didAdd:)` with a horizontal plane anchor:
   - A `ModelEntity` flat plane (10 m × 10 m) is anchored to the plane
   - Grid texture initializes to transparent/black
   - Status changes to "Walk around to map coverage"
4. Scanning begins: 1-second poll loop with 30 cm distance gate

### Cell painting (per scan tick)

1. Read camera `transform.columns.3` (world XZ position)
2. Convert world position to plane-local coordinates using the anchor's inverse transform
3. Map local coords to a grid cell index `(col, row)` — clamp to `[0, 31]`
4. Call `HeatmapRenderer.colorComponents(rssi:scheme:)` to get the cell color
5. Draw the cell into a `CGContext` (1024 × 1024): fill 32 × 32 px rect with the signal color at 0.85 opacity
6. Draw a white ring (8 px radius, 2 px stroke) at the current cell position
7. Generate `UIImage` from context → wrap in `TextureResource` → assign to the plane entity's `UnlitMaterial`

### Distance gating

Same logic as the existing implementation: minimum 30 cm movement required before a new cell is painted. Prevents duplicate readings when standing still.

### Grid texture rendering

- `UIGraphicsImageRenderer` with a persistent `CGContext`-backed buffer
- On each new cell: draw into buffer (don't recreate the full image each time — only update the changed rect)
- Convert buffer to `CGImage` → `TextureResource.generate(from:options:)` → `UnlitMaterial` with no lighting
- Target: < 5 ms per texture update on A15+

---

## UI Layout

```
┌────────────────────────────────┐
│ ×   Signal Strength    [Done]  │  ← top bar (matches WiFi Man exactly)
│     WiFi: Winding Brook        │
├────────────────────────────────┤
│                                │
│    [AR camera feed — full      │
│     screen, dimmed 40%]        │
│                                │
│    [Floor grid rendered        │
│     flat in AR space]          │
│                                │
├────────────────────────────────┤
│ dBm  -80  -70  -60  -50  -40  -30 │  ← color scale (GlassCard)
├────────────────────────────────┤
│ [AP icon]  SSID name    -61 dBm│
│            28:70:4E:...  6 GHz │  ← AP info bar (GlassCard)
└────────────────────────────────┘
```

### Top bar

- Title: "Signal Strength" (center)
- SSID with WiFi icon (below title, small, secondary)
- X button: top-left — stops scan, dismisses with `nil` survey
- Done button: top-right — stops scan, builds survey, dismisses with result

### Color scale strip

Bottom `GlassCard` with a linear gradient (red → orange → yellow → green) and dBm tick labels matching WiFi Man: `dBm  -80  -70  -60  -50  -40  -30`. Uses `HeatmapColorScheme.signal` stops.

### AP info bar

Below the color scale, another `GlassCard`:

```
[circle AP icon]  SSID                     -61 dBm (color-coded)
                  28:70:4E:31:1B:20         6 GHz
```

- SSID + dBm from `NEHotspotNetwork.fetchCurrent()`
- BSSID (MAC) from `NEHotspotNetwork.bssid`
- Band derived from channel: 1–13 → "2.4 GHz", 36–165 → "5 GHz", 1–233 (unambiguous 6 GHz channels) → "6 GHz"
- dBm color: green > −50, yellow > −70, red ≤ −70 (uses `Theme.Colors.success/warning/error`)

### Status states

| State | UI |
|-------|----|
| Initializing | "Initializing AR session." spinner (matches WiFi Man copy exactly) |
| Detecting floor | "Detecting floor..." spinner |
| Scanning | Status hidden — grid fills in |
| No WiFi | Red badge "WiFi signal unavailable" |
| No AR support | Fallback screen with message + back button |

---

## New Files

### `ARContinuousHeatmapSession`

Responsibilities:
- Owns the `ARView` and `ARSession`
- Starts/stops `ARWorldTrackingConfiguration` with `planeDetection: [.horizontal]`
- Exposes `floorAnchor: ARAnchor?` (set on first horizontal plane detection)
- Exposes `currentWorldPosition: SIMD3<Float>?` (camera XZ + Y from current frame)
- Exposes `placeGridPlane(size: Float) -> ModelEntity` — creates and anchors the flat plane entity
- Exposes `updateGridTexture(_ image: UIImage)` — assigns new texture to the plane entity's material
- `ARSessionDelegate` implementation notifies ViewModel of plane detection via closure

### `ARContinuousHeatmapViewModel`

`@MainActor @Observable final class`

State:
- `isScanning: Bool`
- `floorDetected: Bool`
- `signalDBm: Int`
- `ssid: String?`
- `bssid: String?`
- `band: String?`
- `pointCount: Int`
- `statusMessage: String`
- `errorMessage: String?`
- `gridState: [[Int?]]` — 32×32 array of RSSI values (nil = unvisited)
- `currentCell: (col: Int, row: Int)?`
- Recorded world points for final `HeatmapSurvey`

Key methods:
- `startScanning()` — location auth check → `beginScanning()`
- `beginScanning()` — starts AR session, starts poll task
- `stopScanning()`
- `buildSurvey() -> HeatmapSurvey?` — normalizes world XZ to 0–1 range (same logic as current `ARHeatmapSurveyViewModel`)
- `renderGridTexture() -> UIImage` — draws `gridState` into a `UIGraphicsImageRenderer` context

### `ARContinuousHeatmapView`

Full-screen SwiftUI view. Callback: `(HeatmapSurvey?) -> Void`.

- `ARViewRepresentable` wraps `arSession.arView`
- Top bar overlay: title, SSID, X, Done
- Status overlay (centered, `GlassCard`) shown during init/detection states
- Color scale strip (`GlassCard`) — bottom
- AP info bar (`GlassCard`) — above color scale
- On each ViewModel update to `gridState`: calls `arSession.updateGridTexture(viewModel.renderGridTexture())`

---

## Tests

Replace `ARHeatmapSurveyViewModelTests.swift` with `ARContinuousHeatmapViewModelTests.swift`:

- `startScanning_setsIsScanningTrue`
- `stopScanning_afterStart_setsIsScanningFalse`
- `buildSurvey_noPoints_returnsNil`
- `buildSurvey_withPoints_normalizesCoordinates` (same test as current `normalizePoints` test)
- `renderGridTexture_emptyGrid_returnsBlackImage`
- `renderGridTexture_withCell_returnsColoredPixel`
- `worldPositionToGridCell_mapsCorrectly` (unit test for the coord→cell mapping math)
- `distanceGate_preventsNearbyDuplicates`

---

## Out of Scope

- Saving the AR floor grid image as the survey's floor plan (future enhancement)
- Multi-floor / vertical plane scanning
- Real-time IDW interpolation across the grid (cells are colored directly by observed RSSI, not interpolated — IDW is still used in the result view after the scan)
- Adjustable grid cell size or scan area
