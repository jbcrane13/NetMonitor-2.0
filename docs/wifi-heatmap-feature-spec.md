# WiFi Heatmap Feature — Build Specification

## Overview

The WiFi Heatmap is an iOS-only feature that records WiFi signal strength (RSSI in dBm) at spatial positions throughout a room or building and renders the results as an interpolated color heatmap. There are four scanning modes:

- **Freeform** — blank grid canvas; user taps to drop a signal reading at that position
- **Floorplan** — same tap-to-record flow but with an imported floor plan image underneath
- **AR LiDAR Scan** — use Apple RoomPlan to auto-generate a scaled floor plan, then do a manual tap survey on top of it
- **AR Continuous** — ARKit world-tracking; walks auto-record signal at 30 cm intervals, painted live on a 10 m × 10 m AR floor grid

A separate but related screen, **AR WiFi Signal** (`ARWiFiSignalView`), is a simple camera overlay for real-time signal reading with tap-to-drop 3D signal anchors. It is not part of the heatmap survey flow; it is its own tool.

---

## Repository Structure

```
Packages/NetMonitorCore/Sources/NetMonitorCore/
  Models/HeatmapModels.swift          # Core data types (no platform deps)
  Utilities/HeatmapRenderer.swift     # Pure computation: color mapping, IDW, stats, scale bar
  Services/ServiceProtocols.swift     # HeatmapDataPoint struct, WiFiHeatmapServiceProtocol,
                                      # WiFiInfoServiceProtocol

NetMonitor-iOS/
  Platform/
    WiFiInfoService.swift             # NEHotspotNetwork + CaptiveNetwork fallback
    WiFiSignalSampler.swift           # Protocol + cached sampler wrapping WiFiInfoService
    WiFiHeatmapService.swift          # In-memory survey session service
    ARContinuousHeatmapSession.swift  # ARKit/RealityKit floor grid session
    ARWiFiSession.swift               # ARKit session for AR WiFi signal anchor tool
    AppSettings.swift                 # UserDefaults key constants

  ViewModels/
    WiFiHeatmapSurveyViewModel.swift  # Freeform + floorplan modes
    ARContinuousHeatmapViewModel.swift# AR continuous mode
    ARWiFiViewModel.swift             # AR WiFi signal anchor tool

  Views/Tools/
    HeatmapDashboardView.swift        # Entry screen: saved surveys + new scan button
    FloorPlanSelectionView.swift      # Bottom sheet: choose scan mode
    WiFiHeatmapSurveyView.swift       # Active freeform/floorplan survey
    ARContinuousHeatmapView.swift     # AR continuous scan full-screen
    RoomPlanScanView.swift            # LiDAR room scan (generates floor plan)
    HeatmapResultView.swift           # Read-only saved survey viewer
    HeatmapCanvasView.swift           # Shared rendering canvas (5 layers)
    HeatmapFullScreenView.swift       # Full-screen canvas with orientation-aware controls
    HeatmapControlStrip.swift         # Color scheme picker + overlay toggles
    ARWiFiSignalView.swift            # AR WiFi signal anchor tool view

Tests/
  NetMonitor-iOSTests/
    ARContinuousHeatmapViewModelTests.swift
    WiFiHeatmapSurveyViewModelTests.swift
    WiFiSignalSamplerTests.swift
  NetMonitor-iOSUITests/
    WiFiHeatmapSurveyUITests.swift
    ARWiFiSignalUITests.swift
  NetMonitorCoreTests/
    HeatmapRendererTests.swift
    HeatmapModelsTests.swift
```

---

## Entitlements, Permissions, and Info.plist

### Entitlements (`NetMonitor-iOS.entitlements`)

```xml
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

This entitlement must be checked in Xcode → Signing & Capabilities → Access WiFi Information. It must be present in both the entitlements file AND the provisioning profile (Apple Developer portal capability). Without it, `NEHotspotNetwork.fetchCurrent()` silently returns `nil`.

### Info.plist (`project.yml` → iOS Info.plist properties)

```yaml
NSLocationWhenInUseUsageDescription: "Required to read WiFi signal strength for heatmap surveys"
NSCameraUsageDescription: "Required for AR scanning"
BGTaskSchedulerPermittedIdentifiers:
  - com.netmonitor.refresh
  - com.netmonitor.cleanup
  - com.netmonitor.scan
UIBackgroundModes:
  - fetch
  - processing
```

### Runtime Permission Flow

1. **Location** — `NEHotspotNetwork.fetchCurrent()` requires `CLAuthorizationStatus == .authorizedWhenInUse` or `.authorizedAlways` AND `CLAccuracyAuthorization == .fullAccuracy` (precise location, iOS 14+). If location is `.notDetermined`, request it and begin scanning with estimated signal (`usingEstimatedSignal: true`). If `.denied`, begin scanning with estimated signal. If granted but imprecise, the system returns `nehelper` error code 1 and `fetchCurrent()` returns `nil`.
2. **Camera** — do NOT request it manually. ARKit handles camera permission internally when `session.run()` is called. Any explicit `AVCaptureDevice.requestAccess` check before `session.run()` prevents the AR session from starting.

---

## Core Data Models (`NetMonitorCore`)

### `HeatmapDataPoint` (in `ServiceProtocols.swift`)

```swift
public struct HeatmapDataPoint: Sendable, Codable {
    public let x: Double            // normalized 0.0–1.0 in canvas space
    public let y: Double            // normalized 0.0–1.0 in canvas space
    public let signalStrength: Int  // RSSI in dBm (e.g. -65)
    public let timestamp: Date
}
```

Coordinates are always stored normalized to `[0, 1]`. The canvas view multiplies them by the actual canvas size at render time.

### `HeatmapSurvey` (in `HeatmapModels.swift`)

```swift
public struct HeatmapSurvey: Identifiable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let mode: HeatmapMode
    public let createdAt: Date
    public var dataPoints: [HeatmapDataPoint]
    public var calibration: CalibrationScale?
    public var averageSignal: Int? { ... }   // mean of all dataPoints.signalStrength
    public var signalLevel: SignalLevel? { ... }
}
```

### `HeatmapMode`

```swift
public enum HeatmapMode: String, Codable, CaseIterable, Sendable {
    case freeform      = "freeform"
    case floorplan     = "floorplan"
    case arContinuous  = "ar_continuous"
}
```

`arContinuous` surveys are created by `ARContinuousHeatmapViewModel.buildSurvey()` which normalizes world-space XZ coordinates to `[0, 1]`.

### `CalibrationScale`

```swift
public struct CalibrationScale: Codable, Sendable, Equatable {
    public let pixelDistance: Double   // length of the drawn reference line in pixels
    public let realDistance: Double    // real-world distance the user entered
    public let unit: DistanceUnit      // .feet or .meters
    public var pixelsPerUnit: Double { pixelDistance / realDistance }
}
```

Used by `HeatmapRenderer.scaleBar(...)` to compute the on-canvas ruler widget. For LiDAR scans, `RoomFloorPlanRenderer` derives this automatically from room dimensions.

### `HeatmapColorScheme`

Four schemes, each defined as an array of `(t: Double, hex: String)` color stops where `t=0` = weakest signal (`-100 dBm`) and `t=1` = strongest (`-30 dBm`):

| Scheme    | Description |
|-----------|-------------|
| `thermal` | blue → cyan → green → yellow → red (default) |
| `signal`  | red → orange → yellow → green |
| `nebula`  | navy → violet → magenta → white |
| `arctic`  | navy → teal → ice blue → white |

### `HeatmapDisplayOverlay`

An `OptionSet` controlling which rendering layers are active:

| Bit | Name         | Default |
|-----|--------------|---------|
| 1   | `.gradient`  | ON |
| 2   | `.dots`      | OFF |
| 4   | `.contour`   | OFF |
| 8   | `.deadZones` | OFF |

### `SignalLevel`

```swift
public enum SignalLevel: Sendable {
    case strong  // rssi >= -50 dBm
    case fair    // -70 to -51 dBm
    case weak    // < -70 dBm
}
```

### `DistanceUnit`

```swift
public enum DistanceUnit: String, Codable, CaseIterable, Sendable, Equatable {
    case feet = "ft"
    case meters = "m"
}
```

---

## Rendering Engine (`HeatmapRenderer`)

Pure computation struct in `NetMonitorCore`. No SwiftUI/UIKit dependencies.

### Color Mapping

```swift
public static func colorComponents(rssi: Int, scheme: HeatmapColorScheme) -> RGB
```

Maps RSSI to `[0, 1]` as `t = (rssi - (-100)) / ((-30) - (-100))`, clamps, then linearly interpolates between the scheme's color stops.

### IDW Grid

```swift
public static func idwGrid(
    points: [HeatmapDataPoint],
    gridSize: Int,
    canvasWidth: Double,
    canvasHeight: Double,
    maxRadiusPt: Double = 80   // influence radius in canvas points
) -> [[Double?]]               // [row][col] = interpolated dBm or nil (no nearby point)
```

Inverse Distance Weighting with `1/d²` weights. Cells with no `points` within `maxRadiusPt` canvas points return `nil` (dead zone candidates). Grid is used for contour lines and dead-zone highlighting; NOT for the gradient layer (which uses per-point radial gradients instead).

### Stats

```swift
public static func computeStats(
    points: [HeatmapDataPoint],
    calibration: CalibrationScale?,
    unit: DistanceUnit
) -> SurveyStats
// SurveyStats: count, averageDBm, strongestDBm, weakestDBm,
//              coverageArea (nil; computed in View), strongCoveragePercent, deadZoneCount
```

### Scale Bar

```swift
public static func scaleBar(
    pixelsPerUnit: Double,
    unit: DistanceUnit,
    maxPixels: Double = 120
) -> ScaleBarConfig    // pixels: Double, labelValue: Int, unit: DistanceUnit
```

Picks the largest round number (1, 2, 5, 10, 25, 50, 100) that fits within `maxPixels`.

---

## WiFi Signal Reading Stack

### `WiFiInfoServiceProtocol` / `WiFiInfoService`

`WiFiInfoService` is a `@MainActor @Observable NSObject` that owns a `CLLocationManager` delegate for authorization tracking. It tries two strategies in order:

1. **Modern API (iOS 14+):** `await NEHotspotNetwork.fetchCurrent()` — tried twice with 250 ms gap. Returns `WiFiInfo` with `ssid`, `bssid`, `signalStrength` (0–100 Int), `signalDBm` (approximate), `securityType`.
2. **Legacy API (fallback):** `CNCopySupportedInterfaces()` + `CNCopyCurrentNetworkInfo()` — returns SSID/BSSID only, no signal strength.

`signalStrength` is a 0–100 Int derived from `NEHotspotNetwork.signalStrength` (0.0–1.0) via `Int(clamped * 100)`. It is `nil` when `signalStrength == 0.0` (system can't read). `signalDBm` is derived: `Int(-100 + (percent / 100.0 * 70.0))`, mapping 0% → `-100 dBm`, 100% → `-30 dBm`.

`WiFiInfo` model (from `NetworkModels.swift`):
```swift
public struct WiFiInfo: Sendable, Equatable {
    public let ssid: String
    public let bssid: String?
    public let signalStrength: Int?   // 0–100 percent
    public let signalDBm: Int?        // approximate dBm
    public let channel: Int?
    public let frequency: Int?
    public let band: WiFiBand?
    public let securityType: String?
}
```

### `WiFiSignalSampling` / `WiFiSignalSampler`

```swift
@MainActor
protocol WiFiSignalSampling {
    func currentSample() async -> WiFiSignalSample
}

struct WiFiSignalSample: Sendable, Equatable {
    let dbm: Int?
    let ssid: String?
    let bssid: String?
}
```

`WiFiSignalSampler` wraps `WiFiInfoService` with a fallback chain:
1. `wifiInfo.signalDBm` if non-nil
2. Compute from `wifiInfo.signalStrength` percent if non-nil
3. `lastKnownDBm` (last successful reading)
4. `-70` if connected (SSID present) but no signal readable
5. `-70` unconditionally as last resort

This means `WiFiSignalSampler.currentSample().dbm` is always non-nil. The caller checks whether the value is estimated or real by comparing against last known.

---

## WiFiHeatmapService (Platform Layer)

Simple in-memory survey session:

```swift
final class WiFiHeatmapService: WiFiHeatmapServiceProtocol {
    func startSurvey()                                          // clears dataPoints, sets isActive
    func recordDataPoint(signalStrength: Int, x: Double, y: Double)  // appends to in-memory array
    func getSurveyData() -> [HeatmapDataPoint]
    func stopSurvey()                                           // sets isActive = false
}
```

No persistence — the ViewModel handles persistence separately.

---

## ViewModels

### `WiFiHeatmapSurveyViewModel`

`@MainActor @Observable` — drives freeform and floorplan modes.

**Dependencies injected via init:**
- `service: any WiFiHeatmapServiceProtocol` (default `WiFiHeatmapService()`)
- `signalSampler: any WiFiSignalSampling` (default `WiFiSignalSampler()`)

**State:**
```swift
private(set) var isSurveying = false
private(set) var currentSignalStrength: Int = 0   // dBm, updated every 1s
private(set) var dataPoints: [HeatmapDataPoint] = []
private(set) var surveys: [HeatmapSurvey] = []
private(set) var statusMessage = "Tap 'Start Survey' to begin"
private(set) var locationDenied = false

var selectedMode: HeatmapMode = .freeform
var floorplanImageData: Data?                      // set externally by FloorPlanSelectionView
var colorScheme: HeatmapColorScheme = .thermal     // persisted to UserDefaults
var displayOverlays: HeatmapDisplayOverlay = .gradient  // persisted
var preferredUnit: DistanceUnit = .feet            // persisted
var isCalibrating = false
private(set) var calibration: CalibrationScale?
```

**Key methods:**
- `startSurvey()` — checks location auth; if `.notDetermined`, requests and calls `beginSurvey(usingEstimatedSignal: true)`; if `.denied`, begins with estimated signal; otherwise calls `beginSurvey()`. Skip location check on simulator.
- `beginSurvey(usingEstimatedSignal:)` — starts 1s signal polling task, calls `service.startSurvey()`
- `stopSurvey()` — cancels task, calls `service.stopSurvey()`, reads final data via `service.getSurveyData()`, creates `HeatmapSurvey`, inserts at front of `surveys`, persists
- `recordDataPoint(at:in:)` — normalizes `CGPoint` to `[0,1]` by dividing by canvas size, calls `service.recordDataPoint(...)`
- `setCalibration(pixelDist:realDist:unit:)` / `clearCalibration()`
- `addSurvey(_:)` / `deleteSurvey(_:)` — both persist immediately

**Persistence:**
- `surveys` encoded as JSON into `UserDefaults` under key `"wifiHeatmap_surveys"` (not `AppSettings.Keys` — hard-coded private key)
- `colorScheme`, `preferredUnit`, `displayOverlays` use `AppSettings.Keys.heatmapColorScheme`, `.heatmapPreferredUnit`, `.heatmapDisplayOverlays`

**Location helper:** `HeatmapLocationDelegate` — private `NSObject, CLLocationManagerDelegate` with `onAuthorized`/`onDenied` closures. Cleared after first call.

### `ARContinuousHeatmapViewModel`

`@MainActor @Observable` — drives the AR continuous mode.

**Dependencies injected via init:**
- `session: ARContinuousHeatmapSession` (default new instance)
- `signalSampler: any WiFiSignalSampling` (default `WiFiSignalSampler()`)
  - Note: despite being injected, the current implementation of `refreshSignal()` calls `NEHotspotNetwork.fetchCurrent()` directly rather than through `signalSampler`. The `signalSampler` property is present for testability but not used in the hot path at this time.

**State:**
```swift
var isScanning = false
var floorDetected = false
var signalDBm: Int = -65
var ssid: String?
var bssid: String?
var band: String?
var pointCount: Int = 0
var errorMessage: String?
var statusMessage = "Initializing AR session."
var gridState: [[Int?]]   // 32×32, nil = unvisited, Int = dBm at that cell
private(set) var currentCell: (col: Int, row: Int)?
```

**Key methods:**
- `startScanning()` — checks location auth (same pattern as survey VM, but skip camera permission — ARKit handles it internally). On simulator, skip to `beginScanning()`.
- `beginScanning(usingEstimatedSignal:)` — resets all grid state, sets `session.onFloorDetected`, calls `session.startSession()`, launches 1s polling task
- `stopScanning()` — cancels task, calls `session.stopSession()`
- `sampleTick()` — calls `refreshSignal()`, queries `session.currentWorldPosition`, updates `currentCell`, checks 30 cm distance gate, appends to `worldPoints`, paints `gridState[row][col]`, calls `session.updateGridTexture(renderGridTexture())`
- `refreshSignal()` — directly calls `NEHotspotNetwork.fetchCurrent()` (not through sampler). Maps `signalStrength` (0.0–1.0) to dBm via `Int(-100 + strength * 70)`. If nil/zero, sets `usingEstimatedSignal = true` and keeps last `signalDBm`
- `buildSurvey(name:)` → `HeatmapSurvey?` — normalizes `worldPoints` XZ to `[0,1]` and wraps in a survey with `mode: .arContinuous`
- `renderGridTexture()` → `UIImage` — renders the 32×32 grid as a 1024×1024 image (32 px per cell), using `HeatmapRenderer.colorComponents` for cell colors, with white grid lines at 0.5 opacity and a white ring at `currentCell`
- `distanceExceeded(from:)` — euclidean XZ distance ≥ `ARContinuousHeatmapSession.distanceGate` (0.3 m)

**Constants:** `gridSize = 32`, `texturePx = 1024`, `cellPx = 32`

---

## AR Session Layer

### `ARContinuousHeatmapSession`

`@MainActor NSObject` — manages ARKit world-tracking and the RealityKit floor grid.

**Compile guards:** `#if os(iOS) && !targetEnvironment(simulator)` — a stub with matching API is provided for simulator/macOS.

**Constants:**
- `planeSizeMeters: Float = 10.0` — side length of AR floor grid
- `distanceGate: Float = 0.3` — minimum camera movement in meters before new reading
- `isSupported: Bool` — `ARWorldTrackingConfiguration.isSupported`

**Init:** Creates `ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)`. Sets self as `arView.session.delegate`.

**`startSession()`:** Runs `ARWorldTrackingConfiguration` with `.horizontal` plane detection and `.automatic` environment texturing. Options: `.resetTracking`, `.removeExistingAnchors`. Resets `hasDetectedFloor`, `floorAnchorEntity`, `gridPlaneEntity`, `floorAnchorTransform`.

**`stopSession()`:** `arView.session.pause()`

**`currentWorldPosition: SIMD3<Float>?`:** Reads `arView.session.currentFrame?.camera.transform.columns.3`.

**`worldToGridCell(gridSize:)`:** Transforms camera world position into floor-anchor local space using `anchorTransform.inverse`, then normalizes XZ over `[-planeSizeMeters/2, +planeSizeMeters/2]` to get `normX/normZ` in `[0,1]`, converts to grid indices, and clamps.

**`updateGridTexture(_ image: UIImage)`:** Generates `TextureResource` from `UIImage.cgImage` using `.generate(from:options:)` with `.color` semantic, applies it to `gridPlaneEntity` as `UnlitMaterial` tinted `.white.withAlphaComponent(0.9)`.

**Floor plane creation (on first `ARPlaneAnchor`):**
- Called via `ARSessionDelegate.session(_:didAdd:)` — only first horizontal plane
- Copies `anchor.transform` into `floorAnchorTransform` (value type — CRITICAL: never store the `ARPlaneAnchor` itself)
- Creates `MeshResource.generatePlane(width: 10, depth: 10)`
- Creates `ModelEntity` with `UnlitMaterial` tinted nearly transparent (`.black.withAlphaComponent(0.01)`)
- Rotates entity `-π/2` around X axis (planes are vertical by default in RealityKit)
- Creates `AnchorEntity(world: capturedTransform)` — NOT `AnchorEntity(anchor:)` (avoids strong reference to ARPlaneAnchor which would retain ARFrames)
- Fires `onFloorDetected` callback on main actor

**ARFrame retention warning:** The ARPlaneAnchor is updated every frame and holds back-references to recent ARFrames. Storing it on the session delegate retains up to 11 ARFrames, causing GPU memory exhaustion (`CAMetalLayer nextDrawable timeout` → black camera feed). Always copy only the `simd_float4x4` transform.

### `RoomPlanScanView` + `RoomFloorPlanRenderer`

Uses Apple's `RoomPlan` framework. Compile guard: `import RoomPlan`.

`RoomScanController` (`@Observable @MainActor NSObject`): creates `RoomCaptureView`, runs session, stores `capturedRoom: CapturedRoom?` when delegate fires.

`RoomFloorPlanRenderer.render(_ room: CapturedRoom) -> Result?`:
- Collects all wall corners via `float4x4 * SIMD4<Float>` local-to-world transform
- Computes bounding box in world XZ plane
- Renders to `1400 px` max dimension `UIGraphicsImageRenderer`, with 80 px padding
- Draws walls (dark fill, light stroke), doors (green), openings (blue)
- Computes `CalibrationScale` from the longest real dimension and its pixel length

---

## Canvas View (`HeatmapCanvasView`)

`GeometryReader` → `ZStack` with 7 layers rendered in order:

| Layer | Condition | Description |
|-------|-----------|-------------|
| 1. Background | always | Floor plan image (opacity 0.55) or subtle grid (40 px cells, white 6% opacity) |
| 2. Gradient | `overlays.contains(.gradient)` | Per-point radial gradients with `.screen` blend mode |
| 3. Dead Zones | `overlays.contains(.deadZones)` | IDW grid (40×40), cells < -75 dBm get pulsing red overlay (0.15↔0.45 opacity, 2s repeat) |
| 4. Contour lines | `overlays.contains(.contour)` | IDW grid (40×40), edge-detect transitions at -50/-65/-80 thresholds |
| 5. Dots | `overlays.contains(.dots)` | 9 px colored circle per point, white stroke, dBm label below |
| 6. Scale bar | calibration != nil | HeatmapRenderer.scaleBar → rendered at bottom-left |
| 7. Tap capture | isSurveying | `Color.clear` + `onTapGesture` calling `onTap?(loc, geo.size)` |

**Gradient layer detail:** Each point gets a radial gradient from the point's RSSI color (at center) to transparent (at `adaptiveRadius`). Radius is adaptive: `max(40, min(100, sqrt(canvasArea / pointCount) * 0.9))`. Blend mode `.screen` makes overlapping gradients additive.

**Input/Output:** The view is driven entirely by arguments (no `@State` for the data itself). `onTap` is optional — passing `nil` disables tap recording.

---

## Navigation Flow

```
App Tab → Wi-Fi Heatmap
  └─ HeatmapDashboardView                   (NavigationStack root)
       ├─ "New Scan" button
       │   └─ FloorPlanSelectionView         (.sheet, .medium/.large detents)
       │       ├─ AR Continuous Scan
       │       │   └─ ARContinuousHeatmapView (.fullScreenCover)
       │       │       └─ [Done] → onARSurveyComplete(HeatmapSurvey) → HeatmapResultView
       │       ├─ AR LiDAR Scan
       │       │   └─ RoomPlanScanView        (.fullScreenCover)
       │       │       └─ completion → set floorplanImageData → WiFiHeatmapSurveyView
       │       ├─ Import Floor Plan
       │       │   └─ PhotosPicker → CalibrationView (.sheet) → WiFiHeatmapSurveyView
       │       └─ Freeform Grid
       │           └─ WiFiHeatmapSurveyView   (.navigationDestination push)
       │
       └─ Saved survey row tap
           └─ HeatmapResultView              (.navigationDestination push)
               └─ fullscreen expand button
                   └─ HeatmapFullScreenView  (.fullScreenCover)
```

`FloorPlanSelectionView` has two completion callbacks:
- `onProceed()` — dismiss sheet, then navigate to `WiFiHeatmapSurveyView` (with 350 ms delay to let sheet dismiss)
- `onARSurveyComplete(HeatmapSurvey)` — dismiss sheet, call `viewModel.addSurvey(survey)`, navigate to `HeatmapResultView`

`WiFiHeatmapSurveyView` auto-starts survey in `.onAppear` if not already surveying, auto-stops in `.onDisappear`.

---

## Active Survey View (`WiFiHeatmapSurveyView`)

- `HeatmapCanvasView` fills the full content area with `onTap` callback
- Navigation bar: `xmark.circle.fill` (stop + dismiss), pulsing red dot (recording indicator, `.repeatForever`)
- Bottom HUD: glass-morphic card with two stat cells — SIGNAL (`viewModel.signalText`) and NODES (`viewModel.dataPoints.count`)
- "Tap to drop survey points" ghost label shown when `dataPoints.isEmpty`

---

## AR Continuous Heatmap View (`ARContinuousHeatmapView`)

Full-screen, `statusBarHidden`, `ignoresSafeArea`.

Uses `ARViewRepresentable: UIViewRepresentable` wrapping `session.arView`.

Layout:
- **Camera feed** fills entire screen
- **Top bar** (overlay, `padding(.top, 56)`): dismiss (✕), "Signal Strength" title, Done button
  - SSID shown below title when `viewModel.ssid != nil`
- **Status overlay** (center): shown while `!floorDetected` — spinner + `viewModel.statusMessage`
- **Color scale strip** (bottom, above AP info bar): horizontal strip with `-80 -70 -60 -50 -40 -30` labels over red→green gradient
- **AP info bar** (bottom): icon circle, SSID + BSSID, signal dBm + band

`Done` button calls `viewModel.stopScanning()` then `onComplete(viewModel.buildSurvey())`. Dismiss (✕) button passes `onComplete(nil)`.

Unsupported fallback (no ARKit world tracking): dark screen with explanatory text and "Go Back" button.

---

## Result View (`HeatmapResultView`)

Read-only. Shows:
1. **Summary card** — mode badge, calibration badge, point count, avg dBm, signal level, date
2. **Canvas** (height 300) — non-interactive `HeatmapCanvasView`. Expand button launches `HeatmapFullScreenView` as `.fullScreenCover`
3. **HeatmapControlStrip** — color scheme + overlay toggles (changes live-preview immediately)
4. **MeasurementsPanel** — list of data points with per-unit distance conversion
5. Trash button in toolbar — confirmation dialog → `viewModel.deleteSurvey(survey)` → dismiss

---

## Full-Screen View (`HeatmapFullScreenView`)

Landscape-aware: detects `geo.size.width > geo.size.height`.

- **Portrait:** canvas on top, `HeatmapControlStrip` at bottom
- **Landscape:** 160 px sidebar on leading edge with scheme picker (radio buttons) + overlay checkboxes + optional Stop Survey button; canvas fills remainder

Both orientations: `xmark.circle.fill` dismiss button overlaid on canvas top-right.

---

## Control Strip (`HeatmapControlStrip`)

Horizontal strip with `ultraThinMaterial` background:
- Color scheme `Menu` showing all `HeatmapColorScheme.allCases` with checkmark on active
- Divider
- Three overlay toggles: Dots / Contour / Zones — each is a rounded-rectangle button that toggles the bit in `displayOverlays`
- `Spacer()`
- Optional Stop Survey button (shown only when `isSurveying`)

---

## Calibration Flow

After importing a floor plan image, `CalibrationView` is presented. The user draws a line between two known points by dragging, then types the real-world distance and selects feet/meters. On confirm, calls `viewModel.setCalibration(pixelDist:realDist:unit:)`. This is optional — surveys without calibration work fine but have no scale bar.

LiDAR scans bypass the calibration UI — `RoomFloorPlanRenderer` computes calibration automatically.

---

## Persistence

All surveys are serialized as `[HeatmapSurvey]` JSON and stored in `UserDefaults`:

```swift
private static let surveysKey = "wifiHeatmap_surveys"
```

User preferences (color scheme, overlays, distance unit) are stored separately:

```swift
AppSettings.Keys.heatmapColorScheme     = "heatmapColorScheme"    // String (rawValue)
AppSettings.Keys.heatmapDisplayOverlays = "heatmapDisplayOverlays" // Int (rawValue)
AppSettings.Keys.heatmapPreferredUnit   = "heatmapPreferredUnit"   // String (rawValue)
```

Defaults: `.thermal`, `.gradient` only, `.feet`.

---

## Simulator Behavior

All WiFi reading paths have `#if targetEnvironment(simulator)` guards:
- `WiFiInfoService.fetchCurrentWiFi()` → mock `WiFiInfo(ssid: "Simulator WiFi", bssid: "00:00:00:00:00:00", signalDBm: -45, band: .band2_4GHz, securityType: "WPA3")`
- `ARContinuousHeatmapViewModel.refreshSignal()` → `signalDBm = -55`, fixed SSID/BSSID
- `ARContinuousHeatmapViewModel.startScanning()` → skip location check, call `beginScanning()` directly
- `WiFiHeatmapSurveyViewModel.startSurvey()` → skip location check, call `beginSurvey()` directly
- `ARContinuousHeatmapSession` → stub (all methods no-op, `isSupported = false`, no ARKit imports)
- `ARContinuousHeatmapView` → shows black screen with "AR not available in Simulator" text

---

## AR WiFi Signal Anchor Tool (Separate Feature)

`ARWiFiSignalView` + `ARWiFiViewModel` + `ARWiFiSession` — a distinct feature from the heatmap survey. Accessed from a separate navigation path.

`ARWiFiSession` starts `ARWorldTrackingConfiguration` with `planeDetection: []` (no plane detection needed). When `placeAnchor()` is called, reads current camera position, creates a `ModelEntity` sphere with radius 0.05 m, color-coded by signal strength (green/yellow/red), places it in world space at camera position.

`ARWiFiViewModel` polls signal every 2 s, exposes `signalDBm`, `signalLabel`, `signalColor`, `signalQuality` (0.0–1.0 for ProgressView), `ssid`, `bssid`, `errorMessage`.

---

## Service Protocols in `NetMonitorCore`

```swift
// ServiceProtocols.swift

public protocol WiFiInfoServiceProtocol {
    @MainActor var currentWiFi: WiFiInfo? { get }
    @MainActor var isLocationAuthorized: Bool { get }
    @MainActor func requestLocationPermission()
    @MainActor func refreshWiFiInfo()
    @MainActor func fetchCurrentWiFi() async -> WiFiInfo?
}

public protocol WiFiHeatmapServiceProtocol: AnyObject, Sendable {
    func startSurvey()
    func recordDataPoint(signalStrength: Int, x: Double, y: Double)
    func getSurveyData() -> [HeatmapDataPoint]
    func stopSurvey()
}
```

---

## Test Coverage

All tests must run on the mac-mini via SSH (not locally). The test command for iOS unit tests:

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && \
  xcodebuild test -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
```

### What must be tested

**`ARContinuousHeatmapViewModelTests` (iOS):**
- `startScanning()` sets `isScanning = true`
- `stopScanning()` sets `isScanning = false`
- `distanceExceeded(from:)` returns `true` when > 0.3 m, `false` when < 0.3 m
- `sampleTick()` appends to `worldPoints` and paints `gridState` correctly
- `buildSurvey()` normalizes coordinates to `[0, 1]`
- `renderGridTexture()` returns a non-nil `UIImage`
- Signal stays at default when `NEHotspotNetwork` returns nil (inject mock `WiFiSignalSampling`)
- `gridState` updated at correct cell when position changes

**`WiFiHeatmapSurveyViewModelTests` (iOS):**
- `startSurvey()` / `stopSurvey()` state transitions
- `recordDataPoint(at:in:)` normalizes correctly to `[0, 1]`
- Surveys saved and reloaded from UserDefaults
- `deleteSurvey()` removes from surveys and persists
- `colorScheme` persisted to UserDefaults via `didSet`

**`WiFiSignalSamplerTests` (iOS):**
- Returns `lastKnownDBm` when service returns `nil`
- Uses signalDBm over signalStrength when both available
- Converts percent to approximate dBm correctly

**`HeatmapRendererTests` (NetMonitorCoreTests):**
- `colorComponents` returns correct RGB for boundary values (-100, -30, -65)
- `idwGrid` returns `nil` cells when no points within radius
- `idwGrid` returns correct IDW value with known points
- `scaleBar` picks the largest fitting round number

**`HeatmapModelsTests` (NetMonitorCoreTests):**
- `HeatmapSurvey.averageSignal` computes correctly
- `CalibrationScale.pixelsPerUnit` math
- `SignalLevel.from(rssi:)` boundary values exactly at -50 and -70

---

## Accessibility Identifiers

| Identifier | Element |
|-----------|---------|
| `screen_heatmapDashboard` | `HeatmapDashboardView` |
| `heatmap_dashboard_network_card` | Network status card |
| `heatmap_dashboard_button_new_scan` | "New Scan" button |
| `heatmap_survey_row_\(index)` | Each saved survey row |
| `heatmap_dashboard_saved_surveys` | Saved surveys section |
| `screen_floorPlanSelection` | `FloorPlanSelectionView` |
| `floorplan_button_cancel` | Cancel button in floor plan selection |
| `floorplan_option_ar_continuous` | AR Continuous option card |
| `floorplan_option_ar` | AR LiDAR option card |
| `floorplan_option_import` | Import floor plan option |
| `floorplan_option_freeform` | Freeform grid option |
| `screen_activeMappingSurvey` | `WiFiHeatmapSurveyView` |
| `heatmap_survey_button_close` | Close button in active survey |
| `screen_arContinuousHeatmap` | `ARContinuousHeatmapView` |
| `ar_continuous_button_close` | Dismiss (✕) button |
| `ar_continuous_button_done` | Done button |
| `ar_continuous_status_overlay` | Scanning status overlay |
| `ar_continuous_color_scale` | dBm color scale strip |
| `ar_continuous_ap_info_bar` | AP info bar |
| `screen_roomPlanScan` | `RoomPlanScanView` |
| `roomplan_button_finish` | Finish Scan button |
| `roomplan_button_close` | Close button |
| `roomplan_button_unsupported_back` | Go Back (no LiDAR) |
| `screen_heatmapResult` | `HeatmapResultView` |
| `heatmap_result_summary_card` | Summary stats card |
| `heatmap_result_button_delete` | Trash button |
| `heatmap_result_button_fullscreen` | Expand to full screen |
| `heatmap_fullscreen_button_close` | Full-screen dismiss |
| `heatmap_fullscreen_button_stop` | Full-screen stop survey |
| `heatmap_menu_scheme` | Color scheme picker |
| `heatmap_toggle_dots` | Dots overlay toggle |
| `heatmap_toggle_contour` | Contour overlay toggle |
| `heatmap_toggle_zones` | Dead zones overlay toggle |
| `heatmap_button_strip_stop` | Stop survey in control strip |
| `heatmap_section_measurements` | Measurements panel |

---

## Key Gotchas

1. **Never store `ARPlaneAnchor` on the session delegate.** It is updated every frame and holds strong back-references to recent `ARFrame` objects. Storing even a single `ARPlaneAnchor?` property on the delegate causes `ARSession is retaining N ARFrames` warnings and eventual GPU memory exhaustion (`CAMetalLayer nextDrawable` returns `nil` → black screen). Always copy only the `simd_float4x4` transform.

2. **Never request camera permission before calling `session.run()`.** ARKit handles camera permission internally. An explicit `AVCaptureDevice.requestAccess` check before `session.run()` causes the AR session to never start (waits for an async callback, returns early, `session.run()` is never called).

3. **`NEHotspotNetwork.fetchCurrent()` requires precise location.** `CLAccuracyAuthorization.fullAccuracy` is required (iOS 14+). If the user grants location but disables "Precise Location" in Settings, the system rejects with `nehelper` error code 1 and returns `nil`. Handle this as `usingEstimatedSignal = true` — do not show an error that blocks the UI.

4. **The `Access WiFi Information` capability must be in the provisioning profile**, not just the entitlements file. The signed binary can show the entitlement via `codesign -d --entitlements - <app.ipa>` but if the provisioning profile doesn't include it, nehelper rejects with error code 1 at runtime.

5. **Use `AnchorEntity(world:)` not `AnchorEntity(anchor:)`.** The latter holds a strong reference to the `ARPlaneAnchor`, which is the second path to ARFrame retention.

6. **`HeatmapDataPoint.x/y` are always normalized to `[0, 1]`**, not pixel coordinates. The canvas view multiplies by canvas size at draw time. The AR continuous mode converts world XZ to `[0, 1]` in `buildSurvey()` via `normalisePoints()`.

7. **`WiFiSignalSampler` always returns a non-nil `dbm`.** Use `usingEstimatedSignal: Bool` tracking in the ViewModel to distinguish live from fallback, not by checking nil.
