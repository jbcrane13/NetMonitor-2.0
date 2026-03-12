# WiFi Heatmap -- Current Implementation Specification

**Date:** 2026-03-12
**Status:** Implemented (macOS only)
**Codebase snapshot:** commit `61ef6d9` on `main`

---

## 1. Architecture Overview

The WiFi Heatmap feature is split across three layers: shared models and services in `NetMonitorCore`, platform-specific WiFi access in the macOS target, and the view layer in `NetMonitor-macOS/Views/Heatmap/`.

### Component Map

| Component | Location | Responsibility |
|---|---|---|
| `HeatmapModels.swift` | `NetMonitorCore/Models/Heatmap/` | All data types: `SurveyProject`, `FloorPlan`, `MeasurementPoint`, `CalibrationPoint`, `WallSegment`, `HeatmapVisualization`, `HeatmapColorScheme`, enums |
| `HeatmapRenderer` | `NetMonitorCore/Services/Heatmap/` | IDW interpolation grid, color mapping, CGImage generation with distance-based alpha falloff |
| `WiFiMeasurementEngine` | `NetMonitorCore/Services/Heatmap/` | Actor that takes passive or active measurements by composing WiFi info, speed test, and ping services |
| `ProjectSaveLoadManager` | `NetMonitorCore/Services/Heatmap/` | Serializes/deserializes `.netmonsurvey` directory bundles |
| `WiFiHeatmapService` | `NetMonitor-macOS/Platform/` | CoreWLAN wrapper for live RSSI polling and nearby AP scanning |
| `WiFiHeatmapViewModel` | `NetMonitor-macOS/ViewModels/` | `@MainActor @Observable` ViewModel owning all survey state, measurement orchestration, heatmap generation, undo stack |
| `WiFiHeatmapView` | `NetMonitor-macOS/Views/Heatmap/` | Top-level SwiftUI view: HSplitView layout, toolbar, file import/export, calibration sheet |
| `HeatmapSidebarView` | `NetMonitor-macOS/Views/Heatmap/` | Left sidebar with Survey and Analyze tabs |
| `HeatmapCanvasNSView` | `NetMonitor-macOS/Views/Heatmap/` | `NSView` subclass (via `NSViewRepresentable`) for floor plan rendering, heatmap overlay, measurement dots, tooltips, calibration overlay |

### Dependency Chain

```
WiFiHeatmapView / HeatmapSidebarView / HeatmapCanvasNSView
        |
  WiFiHeatmapViewModel
        |
   +---------+---------+-------------------+
   |         |         |                   |
WiFiHeatmap  Heatmap   WiFiMeasurement     ProjectSave
Service      Renderer  Engine              LoadManager
(CoreWLAN)   (IDW)     (actor: WiFi+       (.netmonsurvey)
                        Speed+Ping)
```

### Routing

`ContentView.swift` routes `.tool(.wifiHeatmap)` to `WiFiHeatmapView()`. Opening a `.netmonsurvey` file from Finder sets `selectedSection = .tool(.wifiHeatmap)` and passes the URL.

---

## 2. Data Flow

The end-to-end workflow follows five stages:

### Stage 1: Import

1. User clicks "Import Floor Plan" (toolbar or empty state).
2. A confirmation dialog offers "Choose File..." (file importer: PNG, JPEG, PDF, HEIC) or "Choose from Photos..." (PhotosPicker).
3. `viewModel.importFloorPlan(from:)` or `importFloorPlan(imageData:name:)` reads the image, creates a `FloorPlan` struct (with placeholder 10x10m dimensions), wraps it in a `SurveyProject`, and clears any existing measurement data.
4. Calibration starts immediately after import (mandatory).

### Stage 2: Calibrate

1. `startCalibration()` sets `isCalibrating = true` and clears prior calibration points.
2. The canvas draws a semi-transparent overlay with an instruction banner ("Click 2 points with a known distance between them").
3. Each tap on the canvas calls `addCalibrationPoint(at:)`, storing normalized (0..1) coordinates as `CalibrationPoint`.
4. After two points are placed, a `CalibrationSheet` is presented modally.
5. The user enters the known real-world distance (meters or feet; feet are converted to meters).
6. `completeCalibration(withDistance:)` computes `metersPerPixel` via `CalibrationPoint.metersPerPixel(pointA:pointB:knownDistanceMeters:)` (Euclidean distance in normalized space), updates the `FloorPlan` with correct `widthMeters`/`heightMeters`, saves calibration points into the floor plan, sets `isCalibrated = true`, and dismisses the sheet.

The "Start Survey" button is disabled until calibration is complete.

### Stage 3: Survey

1. User clicks "Start Survey" in the sidebar (requires `isCalibrated`).
2. `isSurveying = true`; any existing heatmap overlay is cleared.
3. Each canvas tap calls `viewModel.takeMeasurement(at:)`.
4. The ViewModel saves an undo snapshot, sets `isMeasuring = true` and `pendingMeasurementLocation`, then delegates to `WiFiMeasurementEngine`.
5. In passive mode: engine calls `wifiService.fetchCurrentWiFi()` and builds a `MeasurementPoint` with RSSI, noise, SNR, SSID, BSSID, channel, band, link speed, frequency.
6. In active mode: additionally runs a speed test (`speedTestService.startTest()`) for download/upload Mbps and pings the gateway (3 pings, averaged) for latency.
7. The point is appended to `measurementPoints`. The canvas shows a pulsing blue indicator while measuring.
8. "Stop Survey" ends surveying and auto-generates the heatmap.

### Stage 4: Analyze

1. Switch the sidebar to the "Analyze" tab.
2. Choose a visualization type, color scheme, opacity, AP filter, and optional coverage threshold.
3. Click "Generate Heatmap" (or it auto-generates on parameter changes if already generated).
4. `generateHeatmap()` filters points by BSSID if an AP filter is set, creates a `HeatmapRenderer` with the current opacity, and dispatches rendering to `Task.detached`.
5. The renderer builds a 200x200 IDW grid, maps values to colors, applies distance-based alpha falloff, and returns a `CGImage`.
6. The CGImage is drawn as an overlay on the floor plan at the configured opacity.

### Stage 5: Export

- **PNG:** `exportPNG(canvasSize:)` converts the heatmap CGImage to PNG via `NSBitmapImageRep`. Presented via `NSSavePanel`.
- **PDF:** Currently reuses the PNG path (renders at 1600x1200 and writes to a `.pdf` URL). A proper PDF export with vector elements is not yet implemented.
- **Project save:** See Section 9.

---

## 3. UI Layout

### Top Level: `WiFiHeatmapView`

```
+-----------------------------------------------------+
|  Toolbar: [Project Name] [Viz Picker] [Pts] | Import |
|           Calibrate | Save | Open | Export | Undo    |
|           Sidebar Toggle                              |
+------------+----------------------------------------+
|            |                                        |
|  Sidebar   |              Canvas                    |
|  (220pt)   |  (HeatmapCanvasNSView)                |
|            |                                        |
|  Survey /  |  Floor plan + heatmap overlay          |
|  Analyze   |  + measurement dots + tooltips         |
|  tabs      |  + calibration overlay                 |
|            |  + pending indicator                   |
+------------+----------------------------------------+
```

Layout uses `HSplitView`. The sidebar is conditionally shown based on `isSidebarCollapsed`.

### Toolbar Items (all in `.primaryAction` placement)

- Project name (text, caption)
- Visualization picker (140pt width, all `HeatmapVisualization` cases with "(no data)" suffix when inapplicable)
- Point count badge ("{n} pts")
- Divider
- Import button
- Calibrate / Cancel Calibration toggle
- Save (Cmd+S)
- Open project
- Export menu (PNG, PDF)
- Undo (Cmd+Z, disabled when undo stack empty)
- Sidebar toggle

### Sidebar Modes (`HeatmapSidebarView`)

**Survey tab:**
- Live signal card (large RSSI number, quality label, 5-bar indicator)
- Network info (SSID, BSSID truncated, channel + band, link speed)
- Signal quality (noise floor, SNR)
- Measurement mode picker (passive / active segmented control)
- Nearby APs disclosure group (scan button, list with SSID/channel/RSSI, tap to filter)
- Start/Stop Survey button (borderedProminent, red for stop)

**Analyze tab:**
- Visualization type picker
- Opacity slider (10%--100%)
- Color scheme picker (Thermal, Stoplight, Plasma)
- AP filter picker (All APs + unique BSSIDs from measurement data)
- Coverage threshold toggle + slider (-90 to -30 dBm)
- Statistics (point count, avg/min/max RSSI)
- Generate Heatmap button (shown when points exist but heatmap not yet generated)

### Empty State

Centered icon (map), title, subtitle, and two buttons: "Import Floor Plan" and "Open Project".

---

## 4. Signal Polling

### `WiFiHeatmapService` (macOS platform layer)

- Wraps CoreWLAN via `CWWiFiClient`.
- Captures `interfaceName` once at init from `CWWiFiClient.shared().interface()?.interfaceName`.
- **Fresh `CWInterface` per poll:** The computed property `iface` creates `CWInterface(name:)` on every access. This avoids cached/stale RSSI values that `CWWiFiClient.shared().interface()` returns.
- `currentSignal() -> SignalSnapshot?`: Reads RSSI, noise, SNR (rssi - noise), SSID, BSSID, channel number, band (mapped from `CWChannel.channelBand`), transmit rate, and derived frequency.
- `scanForNearbyAPs() -> [NearbyAP]`: Calls `iface.scanForNetworks(withName: nil)`, returns sorted by RSSI descending. Each AP includes BSSID, SSID (or "(Hidden)"), RSSI, channel, band, noise.

### Polling Loop

`WiFiHeatmapViewModel.startSignalPolling()` starts a `Task` that loops every 1 second, calling `heatmapService.currentSignal()` and assigning the result to `currentSignal`. The task is cancelled on `onDisappear`.

### Channel-to-Frequency Mapping

Static helper `channelToFrequencyMHz(_:)`:
- Channels 1--13: `2412 + (channel - 1) * 5`
- Channel 14: 2484
- Channels 36--177: `5000 + channel * 5`

---

## 5. Measurement Modes

### Passive Mode

Calls `WiFiMeasurementEngine.takeMeasurement(at:floorPlanY:)`:
1. Fetches `WiFiInfo` from `wifiService.fetchCurrentWiFi()` on MainActor.
2. Builds `MeasurementPoint` with: RSSI, noise floor, SNR, SSID, BSSID, channel, frequency, band, link speed.
3. Speed fields (`downloadSpeed`, `uploadSpeed`, `latency`) are left nil.
4. Fast -- completes in under 100ms typically.

### Active Mode

Calls `WiFiMeasurementEngine.takeActiveMeasurement(at:floorPlanY:)`:
1. Same WiFi info fetch as passive.
2. Runs `speedTestService.startTest()` for download and upload speeds (Mbps).
3. Pings the gateway host (default `192.168.1.1`) 3 times with 5s timeout, averages non-timeout results for latency.
4. Significantly slower (5--30 seconds per point depending on speed test duration).

### Continuous Mode (available in engine, not wired to UI)

`startContinuousMeasurement(interval:)` returns an `AsyncStream<MeasurementPoint>` that yields passive measurements at the given interval. Can be stopped with `stopContinuousMeasurement()`. Currently unused by the heatmap UI.

### MainActor Bridge

`WiFiMeasurementEngine` is an `actor`. `WiFiInfoServiceProtocol` and `SpeedTestServiceProtocol` are `@MainActor`-isolated. The engine uses `nonisolated(unsafe)` stored properties with `nonisolated` bridge methods (`fetchWiFiOnMain()`, `runSpeedTestOnMain()`) to call across actor boundaries without sending issues.

---

## 6. Heatmap Rendering

### `HeatmapRenderer`

A `Sendable` struct with a `Configuration`:
- `powerParameter`: IDW exponent (default `2.0`)
- `gridWidth` / `gridHeight`: Interpolation resolution (default `200 x 200`)
- `opacity`: Alpha multiplier (default `0.7`)

### IDW Interpolation

`interpolateGrid(points:visualization:)` produces a `[[Double]]` grid:
1. Extracts valid `(x, y, value)` tuples from points using `visualization.extractValue(from:)`.
2. For each grid cell at normalized position `(nx, ny)`:
   - Computes inverse-distance-weighted average: `weight = 1 / dist^power`.
   - If a point is within `1e-10` distance, returns that point's value exactly (avoids division by zero).

### Distance-Based Alpha Falloff

In `render(points:visualization:colorScheme:)`:
- `falloffRadius = 0.15` (in normalized 0..1 coordinates).
- For each pixel, computes distance to the nearest measurement point.
- If `distance > falloffRadius`: pixel is fully transparent (`alpha = 0`).
- If `distance > falloffRadius * 0.5` (but <= falloffRadius): alpha fades linearly from full to zero.
- If `distance <= falloffRadius * 0.5`: full alpha from color mapping.

This creates a natural "cloud" effect around measurement points rather than painting the entire floor plan.

### Color Mapping

`colorForValue(_:visualization:colorScheme:)`:
1. Clamps the value to the visualization's `valueRange`.
2. Normalizes to 0..1. If `isHigherBetter`, maps directly; otherwise inverts (so "good" is always high `t`).
3. Applies the selected gradient function.

### Color Schemes

**Thermal** (default): Blue -> Cyan -> Green -> Yellow -> Red. Standard network heatmap gradient. Four piecewise-linear segments at 0.25 boundaries.

**Stoplight**: Red -> Orange -> Yellow -> Green. Traffic-light intuition. Three segments at 0.33/0.66 boundaries.

**Plasma**: Dark Indigo -> Purple -> Red -> Orange -> Yellow. Scientific color map with high perceptual contrast. Four segments at 0.25 boundaries.

### CGImage Output

The renderer writes RGBA pixel data into a flat `[UInt8]` array, creates a `CGContext` with `premultipliedLast` alpha info, and calls `makeImage()`. The resulting `CGImage` is assigned to `viewModel.heatmapCGImage` on `MainActor` and drawn by the canvas.

---

## 7. Visualization Options

All cases of `HeatmapVisualization`:

| Case | Display Name | Unit | Value Range | Higher = Better | Requires Active Scan |
|---|---|---|---|---|---|
| `.signalStrength` | Signal Strength | dBm | -100...0 | Yes | No |
| `.signalToNoise` | Signal-to-Noise | dB | 0...50 | Yes | No |
| `.noiseFloor` | Noise Floor | dBm | -100...-60 | No | No |
| `.downloadSpeed` | Download Speed | Mbps | 0...500 | Yes | Yes |
| `.uploadSpeed` | Upload Speed | Mbps | 0...500 | Yes | Yes |
| `.latency` | Latency | ms | 0...200 | No | Yes |
| `.frequencyBand` | Frequency Band | GHz | 0...4 | Yes | No |

Each visualization has:
- `extractValue(from:)` to pull the relevant field from a `MeasurementPoint` (returns `nil` if data absent).
- `hasData(in:)` to check if any point in the set has a value for this metric.
- `requiresActiveScan` to indicate whether the user needs active measurement mode.

The toolbar picker appends "(no data)" to visualizations that have no data in the current filtered point set.

**Frequency band mapping:** 2.4 GHz -> 1.0, 5 GHz -> 2.0, 6 GHz -> 3.0. This produces a discrete/categorical heatmap.

---

## 8. Calibration Flow

### Trigger

Calibration starts automatically after every floor plan import. It can also be triggered manually via the toolbar "Calibrate" button. Surveying is blocked (`startSurvey` guard) until `isCalibrated == true`.

### Two-Point Process

1. `startCalibration()` sets `isCalibrating = true`, clears `calibrationPoints`, sets `isCalibrated = false`.
2. Canvas taps during calibration call `addCalibrationPoint(at:)` instead of `takeMeasurement`.
3. Points are stored as `CalibrationPoint(pixelX:pixelY:)` where values are normalized 0..1 coordinates.
4. After 2 points are placed, `showCalibrationSheet = true` presents `CalibrationSheet`.

### CalibrationSheet

- Text field for distance (default "5.0").
- Unit picker: meters or feet (feet converted via `* 0.3048`).
- Preview of floor plan dimensions in meters once both points are set.
- "Save Calibration" button (disabled until 2 points placed and valid distance entered).
- "Cancel" button cancels calibration entirely.

### Meters-per-Pixel Calculation

```
CalibrationPoint.metersPerPixel(pointA:, pointB:, knownDistanceMeters:)
  pixelDistance = sqrt((a.pixelX - b.pixelX)^2 + (a.pixelY - b.pixelY)^2)
  return knownDistanceMeters / pixelDistance
```

Note: `pixelX`/`pixelY` are normalized coordinates (0..1), not actual pixel coordinates, despite the property names.

### Post-Calibration

`completeCalibration(withDistance:)`:
- Recomputes `FloorPlan.widthMeters = pixelWidth * metersPerPixel` and `heightMeters = pixelHeight * metersPerPixel`.
- Stores the calibration points into `floorPlan.calibrationPoints`.
- Sets `isCalibrated = true`, clears calibration UI state.

---

## 9. Project Persistence

### Format: `.netmonsurvey`

A directory bundle (not a zip). UTType registered by filename extension.

```
project.netmonsurvey/
  survey.json          -- SurveyProject encoded as JSON (floor plan imageData replaced with empty Data)
  floorplan.png        -- Floor plan image stored separately to avoid JSON bloat
  heatmap-cache/       -- Directory for pre-rendered heatmap images (optional)
```

### `ProjectSaveLoadManager`

**Save (`save(project:to:)`):**
1. Removes any existing bundle at the URL.
2. Creates the bundle directory.
3. Writes `floorplan.png` from `project.floorPlan.imageData`.
4. Strips image data from a copy of the project (`imageData = Data()`).
5. Encodes with `JSONEncoder` (pretty-printed, sorted keys, ISO 8601 dates).
6. Writes `survey.json`.
7. Creates `heatmap-cache/` directory.

**Load (`load(from:)`):**
1. Validates bundle directory exists.
2. Reads and decodes `survey.json` with `JSONDecoder` (ISO 8601 dates).
3. Reads `floorplan.png` and restores `project.floorPlan.imageData`.
4. Returns the fully hydrated `SurveyProject`.

**Heatmap Cache API (available but not currently used by the UI):**
- `saveHeatmapCache(imageData:named:in:)`
- `loadHeatmapCache(named:from:)`
- `clearHeatmapCache(in:)`

### ViewModel Integration

- `saveProject(to:)`: Copies `measurementPoints` into `surveyProject.measurementPoints`, then delegates to `ProjectSaveLoadManager.save`.
- `loadProject(from:)`: Loads via manager, restores `measurementPoints` from the project, sets `isCalibrated` based on whether calibration points exist, auto-generates heatmap if points are present.

### File Dialogs

- Save: `NSSavePanel` with `.netmonsurvey` UTType, default name from project name.
- Open: `NSOpenPanel` with `canChooseDirectories: true` (since bundles are directories).

### Error Types (`SurveyFileError`)

`bundleNotFound`, `surveyJSONMissing`, `floorPlanImageMissing`, `corruptedJSON`, `writeFailed` -- all with descriptive messages.

---

## 10. Export Capabilities

### PNG Export

1. Toolbar Export menu -> "Export PNG".
2. `viewModel.exportPNG(canvasSize:)` converts the heatmap `CGImage` to PNG data via `NSBitmapImageRep`.
3. `NSSavePanel` with `.png` type. Default filename: `{projectName}-export.png`.
4. Only the heatmap overlay image is exported -- **not** the composited floor plan + overlay.

### PDF Export

1. Toolbar Export menu -> "Export PDF".
2. Currently renders a PNG at 1600x1200 and writes it to a `.pdf` URL.
3. This is a stub -- the output is a PNG file with a `.pdf` extension, not a proper PDF document.

---

## 11. Canvas Features (`HeatmapCanvasNSView`)

### NSView Subclass

Uses `NSViewRepresentable` (`HeatmapCanvasRepresentable`) to bridge into SwiftUI. The view is `isFlipped = false` (standard macOS coordinate system, origin bottom-left).

### Floor Plan Rendering

- Calculates an aspect-fit rect (`calculateImageRect`) to center the floor plan within the view bounds.
- Draws the CGImage directly via `context.draw(cgImage, in: imageRect)`.
- Dark background (`white: 0.08`) fills the entire canvas.

### Heatmap Overlay

- If `heatmapCGImage` is set, draws it into the same `imageRect` as the floor plan with `context.setAlpha(overlayOpacity)`.

### Measurement Point Dots (Halo Mode)

When surveying or when no heatmap is generated:
- Each point draws a colored halo ring (fill at 0.3 alpha + 2pt stroke) based on RSSI:
  - >= -50 dBm: green (Excellent)
  - -60 to -50: yellow (Good)
  - -70 to -60: orange (Fair)
  - < -70: red (Weak)
- Hovered points expand from radius 10 to 14.
- All points draw a white center dot (radius 4, expands to 5 on hover) with black outline.

### Pending Measurement Spinner

While `isMeasuring == true`:
- A pulsing blue ring animates at 30fps via `Timer` (phase increments by 0.08 per frame).
- Ring radius oscillates with `sin(pulsePhase)` between 1.0x and 1.3x of base 14pt radius.
- Inner blue fill at 0.15 alpha, center blue dot at 3pt radius.
- "Measuring..." label drawn below in a dark rounded-rect badge.
- Animation stops when `isMeasuring` becomes false.

### Calibration Overlay

When `isCalibrating`:
- Semi-transparent black overlay (0.4 alpha) over the floor plan.
- Centered instruction banner (400x60pt dark rounded rect) with title and subtitle.
- Calibration points drawn as blue circles (24pt diameter, numbered "1" and "2").
- Dashed blue line connecting two calibration points (6/4 dash pattern).

### Tooltips

On hover within 12pt of a measurement point:
- Dark tooltip (160pt wide, rounded, 0.95 alpha background).
- Header: RSSI + quality label in bold, colored by RSSI.
- Detail lines: SNR, SSID, channel + band, link speed, download/upload speeds, latency, timestamp.
- Tooltip repositions to stay within view bounds.

### Color Legend

When a heatmap is displayed:
- Centered at top of canvas, 200pt wide gradient bar.
- Dark pill background (0.7 alpha).
- Five-stop gradient: blue -> cyan -> green -> yellow -> red.
- Labels: "-90" on left, "-30 dBm" on right.
- Note: Legend is hardcoded for signal strength; does not adapt to other visualization types.

### Mouse Tracking

- `NSTrackingArea` with `.activeInKeyWindow`, `.mouseMoved`, `.mouseEnteredAndExited`.
- `updateHoveredPoint()` finds the nearest point within 12pt hit radius.
- `mouseDown` converts click to normalized coordinates via `calculateImageRect` inversion.

### Coordinate System

All positions stored as normalized (0..1) coordinates relative to the floor plan image. The Y axis is inverted when drawing: `screenY = imageRect.minY + (1 - normalizedY) * imageRect.height`.

### Undo

- `undoStack` stores up to 50 snapshots of `[MeasurementPoint]`.
- Snapshots are saved before each measurement and each deletion.
- Cmd+Z in toolbar pops the last state and regenerates the heatmap if one was showing.

---

## 12. Known Limitations

### Not Implemented

- **No channel overlap visualization.** The frequency band visualization maps 2.4/5/6 GHz as discrete values but does not show co-channel interference or channel overlap between APs.
- **No AP coverage radius visualization.** Individual AP coverage areas are not drawn; the heatmap shows signal from whatever AP the Mac is connected to at each point.
- **No zoom or pan.** `scrollWheel(with:)` and `magnify(with:)` are stubbed as empty methods with "Future" comments.
- **No wall attenuation modeling.** `WallSegment` is defined in the model but walls cannot be drawn or used in interpolation.
- **Continuous measurement mode not wired.** `WiFiMeasurementEngine.startContinuousMeasurement(interval:)` exists but is not accessible from the UI.
- **Heatmap cache not used.** `ProjectSaveLoadManager` has cache save/load/clear methods, but the ViewModel never calls them.
- **PDF export is a stub.** Writes PNG data with a `.pdf` extension rather than generating a real PDF document.
- **PNG export excludes floor plan.** Only the heatmap overlay CGImage is exported, not the composite of floor plan + overlay + dots.
- **Color legend is static.** Always shows "-90" to "-30 dBm" regardless of the selected visualization type or its actual value range/unit.
- **No multi-floor support.** A single `SurveyProject` contains exactly one `FloorPlan`.

### Model Stubs Present but Unused

- `SurveyMode` enum: `.blueprint`, `.arAssisted`, `.arContinuous` -- only `.blueprint` is used.
- `SurveyMetadata`: `buildingName`, `floorNumber`, `notes` -- no UI to set these.
- `FloorPlanOrigin`: `.arGenerated`, `.drawn` -- only `.imported` is used.
- `WallSegment`: Fully defined struct with start/end points and thickness -- no drawing or simulation support.
- `CalibrationPoint.realWorldX`/`realWorldY`: Always default to 0, never populated.

### Technical Debt

- `CalibrationPoint.pixelX`/`pixelY` are actually normalized (0..1) coordinates, not pixel coordinates. The naming is misleading.
- The `exportPDF()` function in `WiFiHeatmapView` writes PNG data to a PDF URL without proper PDF rendering.
- `WiFiHeatmapService.channelToFrequencyMHz` does not handle 6 GHz channels (UNII-5 through UNII-8).
- The RSSI color thresholds in `HeatmapCanvasNSView` (-50/-60/-70) and `HeatmapSidebarView` (-50/-60/-70) are duplicated rather than shared.
- Undo stack stores full copies of the measurement array (potentially large for surveys with many points).
