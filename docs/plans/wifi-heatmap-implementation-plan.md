# WiFi Heatmap — Implementation Plan

> **Reference spec:** `docs/wifi-heatmap-feature-spec.md`
>
> Build the WiFi Heatmap feature from scratch in a fresh iOS project that already has the
> NetMonitorCore package, SwiftUI liquid glass theme system (`Theme`, `GlassCard`, `GlassButton`),
> and standard project scaffolding (AppSettings, entitlements file, project.yml / XcodeGen).
>
> **Stack:** Swift 6, strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`), iOS 18+,
> `@MainActor @Observable` ViewModels, Swift Testing (`@Suite`/`@Test`/`#expect`).
>
> Work through the chunks in order. Each chunk ends with a build/lint gate before moving on.
> Never skip a gate. Run `xcodebuild build` (not test) locally after each chunk;
> run the full test suite on the mac-mini via SSH only after the final chunk.

---

## Chunk 1 — Core models in NetMonitorCore

All types here live in `Packages/NetMonitorCore/Sources/NetMonitorCore/`. They have zero platform
dependencies (no UIKit, no ARKit, no SwiftUI).

### Task 1.1 — `HeatmapDataPoint` in `ServiceProtocols.swift`

Add the struct to the existing `ServiceProtocols.swift` file alongside other protocol definitions.
Do not create a new file.

```swift
/// A recorded signal strength data point for WiFi heatmapping.
public struct HeatmapDataPoint: Sendable, Codable {
    public let x: Double            // normalized 0.0–1.0 in canvas space
    public let y: Double            // normalized 0.0–1.0 in canvas space
    public let signalStrength: Int  // RSSI in dBm (e.g. -65)
    public let timestamp: Date

    public init(x: Double, y: Double, signalStrength: Int, timestamp: Date = Date()) {
        self.x = x; self.y = y
        self.signalStrength = signalStrength; self.timestamp = timestamp
    }
}
```

### Task 1.2 — `WiFiHeatmapServiceProtocol` in `ServiceProtocols.swift`

Add immediately after `HeatmapDataPoint`:

```swift
/// Protocol for WiFi signal heatmap surveys.
public protocol WiFiHeatmapServiceProtocol: AnyObject, Sendable {
    func startSurvey()
    func recordDataPoint(signalStrength: Int, x: Double, y: Double)
    func getSurveyData() -> [HeatmapDataPoint]
    func stopSurvey()
}
```

### Task 1.3 — `Models/HeatmapModels.swift` (new file)

Create `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/HeatmapModels.swift`.

Implement in this order (each depends on the previous):

1. `HeatmapMode: String, Codable, CaseIterable, Sendable` — cases `freeform`, `floorplan`,
   `arContinuous`; computed `displayName: String`, `systemImage: String`, `description: String`
2. `DistanceUnit: String, Codable, CaseIterable, Sendable, Equatable` — cases `feet = "ft"`,
   `meters = "m"`; `func convert(_ value: Double, to target: DistanceUnit) -> Double`
3. `CalibrationScale: Codable, Sendable, Equatable` — fields `pixelDistance`, `realDistance`,
   `unit: DistanceUnit`; computed `pixelsPerUnit` and `func realDistance(pixels:) -> Double`
4. `HeatmapColorScheme: String, Codable, CaseIterable, Sendable, Equatable` — cases `thermal`,
   `signal`, `nebula`, `arctic`; `displayName: String`; `colorStops: [(t: Double, hex: String)]`
   with exact values from spec
5. `HeatmapDisplayOverlay: OptionSet, Codable, Sendable, Equatable` — `rawValue: Int`;
   static members `.gradient = 1<<0`, `.dots = 1<<1`, `.contour = 1<<2`, `.deadZones = 1<<3`
6. `SignalLevel: Sendable` — cases `strong`, `fair`, `weak`;
   `static func from(rssi: Int) -> SignalLevel` using thresholds -50 and -70;
   `hexColor: String`; `label: String`
7. `HeatmapSurvey: Identifiable, Sendable, Codable` — fields `id: UUID`, `name`, `mode`,
   `createdAt`, `dataPoints: [HeatmapDataPoint]`, `calibration: CalibrationScale?`;
   computed `averageSignal: Int?`, `signalLevel: SignalLevel?`

### Task 1.4 — `Utilities/HeatmapRenderer.swift` (new file)

Create `Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/HeatmapRenderer.swift`.

Implement as a `public enum HeatmapRenderer` (namespace, no instances):

1. `struct RGB: Sendable { let r, g, b: Int }` — public
2. `static func colorComponents(rssi: Int, scheme: HeatmapColorScheme) -> RGB`
   — maps rssi to t via `(rssi - -100) / (-30 - -100)`, clamps to [0,1], interpolates stops
3. Private `interpolate(t:stops:) -> RGB` — find bracketing stops, linear interpolation
4. Private `hexToRGB(_ hex: String) -> RGB` — handles optional `#` prefix, parses UInt32
5. `static func idwGrid(points:gridSize:canvasWidth:canvasHeight:maxRadiusPt:) -> [[Double?]]`
   — 1/d² IDW; return nil for cells with no point within maxRadiusPt
6. `struct SurveyStats: Sendable` — fields: count, averageDBm, strongestDBm, weakestDBm,
   coverageArea, strongCoveragePercent, deadZoneCount (all optional where appropriate)
7. `static func computeStats(points:calibration:unit:) -> SurveyStats`
8. `struct ScaleBarConfig: Sendable { let pixels: Double; let labelValue: Int; let unit: DistanceUnit }`
9. `static func scaleBar(pixelsPerUnit:unit:maxPixels:) -> ScaleBarConfig`
   — round numbers `[1, 2, 5, 10, 25, 50, 100]`; pick largest that fits in maxPixels

### Task 1.5 — Register new files in `project.yml` if needed

If `project.yml` uses explicit file lists for NetMonitorCore sources, add:
- `Models/HeatmapModels.swift`
- `Utilities/HeatmapRenderer.swift`

If it uses glob patterns, no change needed.

Run `xcodegen generate` after any `project.yml` edit.

### Gate 1

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet Packages/NetMonitorCore/Sources/NetMonitorCore/
```

Both must pass with zero errors before proceeding.

---

## Chunk 2 — Platform services (iOS)

All files in this chunk live in `NetMonitor-iOS/Platform/`.

### Task 2.1 — `AppSettings.swift` — add heatmap keys

Open the existing `AppSettings.swift`. Find the `Keys` struct and add:

```swift
// MARK: Heatmap
static let heatmapColorScheme     = "heatmapColorScheme"
static let heatmapDisplayOverlays = "heatmapDisplayOverlays"
static let heatmapPreferredUnit   = "heatmapPreferredUnit"
```

### Task 2.2 — `WiFiInfoService.swift` (new file)

`@MainActor @Observable final class WiFiInfoService: NSObject, WiFiInfoServiceProtocol`

Requires at top: `import NetworkExtension`, `import SystemConfiguration.CaptiveNetwork`,
`import CoreLocation`

Fields:
- `private(set) var currentWiFi: WiFiInfo?`
- `private(set) var isLocationAuthorized: Bool = false`
- `private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined`
- `private let locationManager = CLLocationManager()`
- `private var retryTask: Task<Void, Never>?`

`override init()` — sets `locationManager.delegate = self`, calls `checkAuthorizationStatus()`

Methods:
- `func requestLocationPermission()` — `locationManager.requestWhenInUseAuthorization()`
- `func refreshWiFiInfo()` — cancel retryTask, create new Task calling `fetchCurrentWiFi()`
- `func fetchCurrentWiFi() async -> WiFiInfo?`:
  - simulator guard: return `mockWiFiInfo()`
  - re-check live auth status every call
  - try `fetchWiFiInfoModern()` twice with 250 ms sleep between attempts
  - fall back to `fetchWiFiInfoLegacy()`
- `private func fetchWiFiInfoModern() async -> WiFiInfo?`:
  - `await NEHotspotNetwork.fetchCurrent()`
  - `signalStrength == 0.0` → treat as nil (transient failure)
  - convert: `signalStrength: Int? = strength > 0 ? Int(clamped * 100) : nil`
  - `signalDBm = signalStrength.map { Int(-100 + Double($0) / 100.0 * 70.0) }`
  - Map `network.securityType.rawValue` to string: 0=Open, 1=WEP, 2=WPA/WPA2/WPA3,
    3=WPA Enterprise, default=Secured
- `private func fetchWiFiInfoLegacy() -> WiFiInfo?`:
  - `CNCopySupportedInterfaces()` → `CNCopyCurrentNetworkInfo()` → return ssid+bssid only
- `private func checkAuthorizationStatus()` — update fields, call `refreshWiFiInfo()` if authorized
- `private func mockWiFiInfo() -> WiFiInfo` — fixed mock values

Conform to `CLLocationManagerDelegate` in a `nonisolated` extension, calling
`checkAuthorizationStatus()` via `Task { @MainActor in ... }`.

`WiFiInfoServiceProtocol` conformance is declared in `ServiceProtocols.swift` — do not re-declare.

### Task 2.3 — `WiFiSignalSampler.swift` (new file)

```swift
struct WiFiSignalSample: Sendable, Equatable {
    let dbm: Int?
    let ssid: String?
    let bssid: String?
}

@MainActor
protocol WiFiSignalSampling {
    func currentSample() async -> WiFiSignalSample
}

@MainActor
final class WiFiSignalSampler: WiFiSignalSampling { ... }
```

`WiFiSignalSampler` init takes `wifiService: any WiFiInfoServiceProtocol` (default
`WiFiInfoService()`). Stores `lastKnownDBm`, `lastKnownSSID`, `lastKnownBSSID`.

`currentSample()` fallback chain (in order):
1. `wifiInfo.signalDBm`
2. Derive from `wifiInfo.signalStrength` percent: `Int(-100 + Double(pct) / 100.0 * 70.0)`
3. `lastKnownDBm`
4. `-70` if `wifiInfo?.ssid != nil`
5. `-70` unconditionally

Always update `lastKnownDBm/SSID/BSSID` from fresh info. Return `WiFiSignalSample` — `dbm` is
always non-nil.

### Task 2.4 — `WiFiHeatmapService.swift` (new file)

```swift
final class WiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {
    private var dataPoints: [HeatmapDataPoint] = []
    private var isActive = false
    // implement all four protocol methods
}
```

`startSurvey()` sets `isActive = true` and clears `dataPoints`.
`recordDataPoint(...)` appends only when `isActive`.
`getSurveyData()` returns current array.
`stopSurvey()` sets `isActive = false`.

### Task 2.5 — Register in `project.yml` if using explicit file lists

Add the three new Platform files. Run `xcodegen generate`.

### Gate 2

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/Platform/
```

---

## Chunk 3 — ViewModels

Files live in `NetMonitor-iOS/ViewModels/`.

### Task 3.1 — `WiFiHeatmapSurveyViewModel.swift` (new file)

`@MainActor @Observable final class WiFiHeatmapSurveyViewModel`

**Init params (with defaults):**
```swift
init(
    service: any WiFiHeatmapServiceProtocol = WiFiHeatmapService(),
    signalSampler: any WiFiSignalSampling = WiFiSignalSampler()
)
```

**State (implement exactly as spec — `private(set)` vs `var` as specified):**
- `private(set) var isSurveying`, `currentSignalStrength`, `dataPoints`, `surveys`,
  `statusMessage`, `locationDenied`
- `var selectedMode`, `floorplanImageData`, `colorScheme`, `displayOverlays`,
  `preferredUnit`, `isCalibrating`
- `private(set) var calibration`

**`init` body:** call `loadSurveys()`, restore colorScheme/preferredUnit/displayOverlays from
`UserDefaults` using `AppSettings.Keys`.

**`startSurvey()`:**
```
simulator guard → beginSurvey(), return
check locationDelegate.manager.authorizationStatus
  .notDetermined → requestWhenInUseAuthorization(), beginSurvey(usingEstimatedSignal: true),
                   set onAuthorized/onDenied closures, return
  .denied/.restricted → locationDenied=true, beginSurvey(usingEstimatedSignal:true), return
  else → beginSurvey()
```

**`beginSurvey(usingEstimatedSignal:)`:** sets state, calls `service.startSurvey()`, launches
1 s polling Task using `signalSampler.currentSample()`.

**`stopSurvey()`:** cancels task, `service.stopSurvey()`, reads data, creates survey, inserts at
index 0, calls `saveSurveys()`.

**`recordDataPoint(at:in:)`:** normalize point, forward to `service.recordDataPoint(...)`,
refresh `dataPoints = service.getSurveyData()`, update `statusMessage` with dBm + level.

**`refreshSignalStrength()` private async:** gets `sample.dbm`, updates `currentSignalStrength`,
manages `usingEstimatedSignal` state.

**Persistence:** surveys key `"wifiHeatmap_surveys"` (hard-coded private constant, NOT
`AppSettings.Keys`). `JSONEncoder/Decoder` round-trip.

**`HeatmapLocationDelegate` (private class at bottom of file):** `NSObject,
CLLocationManagerDelegate` with `onAuthorized: (() -> Void)?` and `onDenied: (() -> Void)?`.
Clear both closures after first call.

**Computed helpers:** `signalLevel`, `signalText`, `signalColor`, `colorFor(point:)`.

### Task 3.2 — `ARContinuousHeatmapViewModel.swift` (new file)

`@MainActor @Observable final class ARContinuousHeatmapViewModel`

**Constants (static let):** `gridSize = 32`, `texturePx = 1024`, `cellPx = 32`

**State:**
- `var isScanning = false`
- `var floorDetected = false`
- `var signalDBm: Int = -65`
- `var ssid: String?`, `bssid: String?`, `band: String?`
- `var pointCount: Int = 0`
- `var errorMessage: String?`
- `var statusMessage = "Initializing AR session."`
- `var gridState: [[Int?]]` — 32×32 all nil on init
- `private(set) var currentCell: (col: Int, row: Int)?`
- Private: `worldPoints: [(x:Float, z:Float, signalStrength:Int, timestamp:Date)]`,
  `lastRecordedPosition: SIMD3<Float>?`, `scanTask: Task<Void, Never>?`,
  `usingEstimatedSignal = false`, `locationDelegate: ARHeatmapLocationDelegate`

**`startScanning()`:** simulator guard (skip location check) → location auth check (same
pattern as survey VM) → `beginScanning()`. Do NOT check camera permission.

**`beginScanning(usingEstimatedSignal:)`:** resets all grid/point state, sets
`session.onFloorDetected`, calls `session.startSession()`, launches 1 s polling task
calling `sampleTick()`.

**`stopScanning()`:** cancel task, `session.stopSession()`, update statusMessage.

**`sampleTick()` private async:**
1. `await refreshSignal()`
2. Guard `session.currentWorldPosition != nil` else update status and return
3. Update `currentCell = session.worldToGridCell(gridSize: Self.gridSize)`
4. Guard `distanceExceeded(from: pos)` else return
5. Record `worldPoints`, increment `pointCount`
6. Paint `gridState[cell.row][cell.col] = signalDBm`
7. `session.updateGridTexture(renderGridTexture())`

**`refreshSignal()` private async:**
```swift
#if targetEnvironment(simulator)
// fixed mock values
#elseif os(iOS)
let network = await NEHotspotNetwork.fetchCurrent()
// map signalStrength 0…1 → dBm via Int(-100 + strength * 70)
// if nil/zero → usingEstimatedSignal = true, keep last signalDBm
#endif
```
Note: call `NEHotspotNetwork.fetchCurrent()` directly here, not through `signalSampler`.

**`renderGridTexture() -> UIImage`:**
- `UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))`
- Clear background
- For each non-nil cell: `HeatmapRenderer.colorComponents(rssi:scheme:.signal)` → fill rect
  at `col * 32, row * 32` with alpha 0.85
- Draw grid lines: white 0.12 opacity, lineWidth 0.5
- Draw position ring at `currentCell`: white stroke ellipse + white fill inner dot

**`buildSurvey(name:) -> HeatmapSurvey?`:** calls `normalisePoints()`, returns nil if empty.

**`normalisePoints() -> [HeatmapDataPoint]` private:** find xMin/xMax/zMin/zMax of worldPoints,
normalize each (x-xMin)/(xMax-xMin) for both axes; use 0.5 if range < 0.001.

**`distanceExceeded(from:) -> Bool`:** XZ euclidean distance ≥ `ARContinuousHeatmapSession.distanceGate`.

**`injectWorldPoint(x:z:rssi:)` and `setLastPosition(_:)`:** public test helpers.

**`signalColor: Color`:** green if > -50, yellow if > -70, else red.

**`signalText: String`:** `"\(signalDBm) dBm"` if scanning, else `"--"`.

**`ARHeatmapLocationDelegate` (private class at bottom):** same structure as `HeatmapLocationDelegate`.

### Task 3.3 — `ARWiFiViewModel.swift` (new file — for the separate AR signal anchor tool)

`@MainActor @Observable final class ARWiFiViewModel`

Fields: `signalDBm: Int = -70`, `ssid: String?`, `bssid: String?`, `errorMessage: String?`,
`isARSupported: Bool`, `let arSession: ARWiFiSession`

`init(arSession: ARWiFiSession? = nil)` — creates `ARWiFiSession()` if nil.

`startSession()` — starts arSession, launches 2 s polling Task using
`NEHotspotNetwork.fetchCurrent()` directly.

`stopSession()` — cancels task, stops arSession.

`placeAnchor()` — tells arSession to place a sphere at current camera position, color from
`signalDBm`.

Computed: `signalLabel: String`, `signalColor: Color`, `signalQuality: Double` (0.0–1.0).

### Task 3.4 — Register new ViewModel files in `project.yml` if needed

Run `xcodegen generate`.

### Gate 3

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/ViewModels/
```

---

## Chunk 4 — AR session layer

Files live in `NetMonitor-iOS/Platform/`.

### Task 4.1 — `ARContinuousHeatmapSession.swift` (new file)

Use a compile guard to provide two implementations:

```swift
#if os(iOS) && !targetEnvironment(simulator)
// real device implementation — imports ARKit, RealityKit
#else
// simulator stub — matching public API, no ARKit
#endif
```

**Real device implementation** (`@MainActor final class ARContinuousHeatmapSession: NSObject,
@unchecked Sendable`):

- Constants: `planeSizeMeters: Float = 10.0`, `distanceGate: Float = 0.3`,
  `isSupported: Bool { ARWorldTrackingConfiguration.isSupported }`
- Fields: `let arView: ARView`, `var onFloorDetected: (() -> Void)?`,
  `private var floorAnchorEntity: AnchorEntity?`,
  `private var gridPlaneEntity: ModelEntity?`,
  `private var floorAnchorTransform: simd_float4x4?`,  ← value type ONLY, never ARPlaneAnchor
  `private var hasDetectedFloor = false`
- `override init()` — `arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)`;
  `arView.session.delegate = self`
- `startSession()` — `ARWorldTrackingConfiguration` with `.horizontal` planeDetection +
  `.automatic` environmentTexturing; run with `.resetTracking`, `.removeExistingAnchors`;
  reset all state
- `stopSession()` — `arView.session.pause()`
- `currentWorldPosition: SIMD3<Float>?` — read from `currentFrame?.camera.transform.columns.3`
- `worldToGridCell(gridSize:) -> (col:Int, row:Int)?` — requires both `floorAnchorTransform`
  and `currentFrame`; invert anchor transform, project camera world pos to local XZ,
  normalize over `[-half, +half]`, multiply by gridSize, clamp to `[0, gridSize-1]`
- `updateGridTexture(_ image: UIImage)` — `TextureResource.generate(from: cgImage, options:
  .init(semantic: .color))`, create `UnlitMaterial`, set on `gridPlaneEntity.model?.materials`
- `createFloorPlane(for anchor: ARPlaneAnchor)` private:
  - Guard `!hasDetectedFloor`; set `hasDetectedFloor = true`
  - `let capturedTransform = anchor.transform` — copy value, never store anchor
  - `floorAnchorTransform = capturedTransform`
  - `MeshResource.generatePlane(width: 10, depth: 10)`
  - `UnlitMaterial` tinted `.black.withAlphaComponent(0.01)`
  - Rotate entity `-π/2` around X axis
  - `AnchorEntity(world: capturedTransform)` ← NOT `AnchorEntity(anchor:)`
  - `arView.scene.addAnchor(anchorEntity)`
  - Fire `onFloorDetected` via `Task { @MainActor in ... }`

**ARSessionDelegate extension** (`nonisolated`):
- `session(_:didAdd:)` — find first `.horizontal` plane, dispatch to `createFloorPlane` on
  MainActor, return after first match
- `session(_:didFailWithError:)`, `sessionWasInterrupted(_:)`, `sessionInterruptionEnded(_:)` — empty

**Private extension:** `Int.clamped(to: ClosedRange<Int>) -> Int`

**Simulator stub:** empty implementations of all public methods/properties; `isSupported = false`.

### Task 4.2 — `ARWiFiSession.swift` (new file)

Same compile guard pattern.

**Real device:** `@MainActor final class ARWiFiSession: NSObject` — starts
`ARWorldTrackingConfiguration` with no plane detection; `placeAnchor()` creates 0.05 m radius
`ModelEntity` sphere at current camera world position, color-coded by signal strength
(pass signal dBm as parameter). Conform to `ARSessionDelegate` with empty required methods.

**Simulator stub:** `isSupported = false`, all methods no-op.

### Task 4.3 — `RoomPlanScanView.swift` (new file in `Views/Tools/`)

Requires `import RoomPlan`. Use compile guard only for `RoomCaptureView` — the outer
`SwiftUI.View` can exist on all targets but guard the RoomPlan types.

Three parts in the same file:

1. `struct RoomPlanScanView: View` — public entry point with `onComplete: (UIImage?, CalibrationScale?) -> Void`
   - `@State private var controller = RoomScanController()`
   - `static var isSupported: Bool { RoomCaptureSession.isSupported }`
   - Body: if supported → live capture ZStack; else unsupported VStack
   - Live capture: `RoomCaptureLiveView(captureView: controller.captureView)` + control strip
   - Control strip: instruction text + "Finish Scan" button + processing label
   - Close button top-right
   - `.onChange(of: controller.captureFinished)` → call `handleCompletion()`
   - `handleCompletion()`: `RoomFloorPlanRenderer.render(room)` → pass result to `onComplete`

2. `@Observable @MainActor final class RoomScanController: NSObject` — creates `RoomCaptureView`,
   sets delegate (`_RoomCaptureDelegate`), `start()` / `stop()` / `stopIfNeeded()`.

3. `private final class _RoomCaptureDelegate: NSObject, RoomCaptureSessionDelegate,
   @unchecked Sendable` — `captureSession(_:didEndWith:error:)` runs `RoomBuilder` to get
   `CapturedRoom`, sets owner's `capturedRoom` and `captureFinished` on MainActor.

4. `private struct RoomCaptureLiveView: UIViewRepresentable` — wraps `RoomCaptureView`.

5. `enum RoomFloorPlanRenderer` — `render(_ room: CapturedRoom) -> Result?`:
   - Max dimension 1400 px, padding 80 px
   - Project all wall corners: `float4x4 * SIMD4<Float>` local corners → world XZ
   - Compute bounding box
   - Draw walls (dark fill + light stroke), doors (green), openings (blue)
   - Return `Result(image:, calibration:)` where calibration uses longest real dimension

### Task 4.4 — Register new files in `project.yml` if needed

Run `xcodegen generate`.

### Gate 4

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/Platform/
```

---

## Chunk 5 — Shared UI components

Files live in `NetMonitor-iOS/Views/Tools/`.

### Task 5.1 — `HeatmapCanvasView.swift` (new file)

`struct HeatmapCanvasView: View` with these init parameters (all by value / binding-free —
no `@Binding` required):

```swift
let points: [HeatmapDataPoint]
let floorplanImage: UIImage?
let colorScheme: HeatmapColorScheme
let overlays: HeatmapDisplayOverlay
let calibration: CalibrationScale?
let isSurveying: Bool
var onTap: ((CGPoint, CGSize) -> Void)?
```

Body: `GeometryReader` → `ZStack` with layers in this order:

1. **Background:** if `floorplanImage != nil` → `Image(uiImage:).resizable().scaledToFit()`
   at 0.55 opacity; else Canvas drawing 40 px grid lines at `white.opacity(0.06)` +
   `background(Color.white.opacity(0.03))`

2. **Gradient** (if `.gradient` in overlays): `Canvas { drawGradient(context:size:) }`
   - For each point: radial gradient from RSSI color (center) to transparent at `adaptiveRadius`
   - Blend mode `.screen`
   - `adaptiveRadius`: `max(40, min(100, sqrt(area / pointCount) * 0.9))` or 80 if ≤1 point

3. **Dead zones** (if `.deadZones`): `Canvas { drawDeadZones(context:size:opacity:) }` with
   `@State private var deadZonePulse` animating 0.15↔0.45 over 2 s `.easeInOut.repeatForever`
   - `HeatmapRenderer.idwGrid(gridSize: 40, ...)`; cells with rssi < -75 → red overlay

4. **Contours** (if `.contour`): `Canvas { drawContours(context:size:) }`
   - IDW grid 40×40; edge-detect transitions at thresholds -50 (green), -65 (yellow), -80 (red)
   - Only draw edge where cell and right/bottom neighbor straddle threshold

5. **Dots** (if `.dots`): `Canvas { drawDots(context:size:) }`
   - 9 px radius circle per point, RSSI color fill, white stroke lineWidth 1
   - dBm label below at `cy + radius + 8`

6. **Scale bar** (if `calibration != nil`): call `HeatmapRenderer.scaleBar(...)`, draw ruler
   line with end ticks and label at bottom-left

7. **Tap capture** (if `isSurveying`): `Color.clear.contentShape(Rectangle()).onTapGesture`

Clip entire ZStack with `RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)`.

### Task 5.2 — `HeatmapControlStrip.swift` (new file)

```swift
struct HeatmapControlStrip: View {
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var overlays: HeatmapDisplayOverlay
    let isSurveying: Bool
    var onStopSurvey: (() -> Void)?
}
```

Horizontal `HStack` with `ultraThinMaterial` background:
- `Menu` label showing current scheme name + icon; ForEach allCases with checkmark
- `Divider` (height 20, opacity 0.3)
- Three `overlayToggle` buttons: Dots / Contour / Zones
- `Spacer()`
- Stop button (only when `isSurveying`)

Private `overlayToggle` helper: toggles the OptionSet bit; active = accent bg, inactive = white 6% bg.

Accessibility identifiers: `heatmap_menu_scheme`, `heatmap_toggle_dots/contour/zones`,
`heatmap_button_strip_stop`.

### Task 5.3 — `HeatmapFullScreenView.swift` (new file)

```swift
struct HeatmapFullScreenView: View {
    @Binding var points: [HeatmapDataPoint]
    let floorplanImage: UIImage?
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var overlays: HeatmapDisplayOverlay
    let calibration: CalibrationScale?
    let isSurveying: Bool
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onStopSurvey: (() -> Void)?
    var onDismiss: () -> Void
}
```

`GeometryReader` detects landscape when `width > height`:
- **Portrait:** `VStack` — canvas on top, `HeatmapControlStrip` at bottom
- **Landscape:** `HStack` — 160 px sidebar + canvas

Canvas has `xmark.circle.fill` dismiss button overlaid top-right.

Sidebar (landscape only): title, scheme radio list, overlay checkboxes, optional Stop button.

`.ignoresSafeArea()`, `.statusBarHidden(true)`.

Accessibility: `heatmap_fullscreen_button_close`, `heatmap_fullscreen_button_stop`.

### Task 5.4 — `MeasurementsPanel.swift` (new file)

```swift
struct MeasurementsPanel: View {
    let points: [HeatmapDataPoint]
    let isSurveying: Bool
    let calibration: CalibrationScale?
    @Binding var preferredUnit: DistanceUnit
}
```

Uses `HeatmapRenderer.computeStats(...)`. Renders:
- Header: "Live Stats" (surveying) or "Measurements" (static) + optional unit `Picker` if calibrated
- Empty state message when `points.isEmpty`
- 2-column `LazyVGrid` with stat cells: Points, Average, Strongest, Weakest, Strong coverage %, calibration nag cell

Accessibility: `heatmap_section_measurements`, `measurements_picker_unit`.

### Task 5.5 — `CalibrationView.swift` (new file)

```swift
struct CalibrationView: View {
    let floorplanImage: UIImage?
    var onComplete: (CalibrationScale?) -> Void
}
```

State: `lineStart: CGPoint?`, `lineEnd: CGPoint?`, `isDragging: Bool`,
`showDistanceEntry: Bool`, `distanceText: String`, `unit: DistanceUnit`, `canvasSize: CGSize`

Layout: `NavigationStack` with:
- Instruction banner (GlassCard) — text updates as state progresses
- Canvas area: floor plan image (or gray placeholder) with overlay lines drawn via SwiftUI
  `Canvas`; `DragGesture` on overlay sets `lineStart`/`lineEnd`
- Distance entry panel (shown after line is drawn): `TextField` for distance + `Picker` for
  unit + Confirm button
- "Skip" toolbar button → `onComplete(nil)`

Confirm: `guard let dist = Double(distanceText), let px = pixelDistance` →
`onComplete(CalibrationScale(pixelDistance: px, realDistance: dist, unit: unit))`

Accessibility: `calibration_button_skip`.

### Task 5.6 — Register all new Views in `project.yml` if needed

Run `xcodegen generate`.

### Gate 5

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/Views/Tools/
```

---

## Chunk 6 — Feature views

### Task 6.1 — `WiFiHeatmapSurveyView.swift` (new file)

```swift
struct WiFiHeatmapSurveyView: View {
    @Bindable var viewModel: WiFiHeatmapSurveyViewModel
    @Environment(\.dismiss) private var dismiss
}
```

`ZStack(alignment: .bottom)`:
- `HeatmapCanvasView(...)` with `onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) }`
- Ghost label "Tap to drop survey points" when `dataPoints.isEmpty`
- `bottomHUD` at bottom: glass card with SIGNAL + NODES stat cells

Navigation bar: `xmark.circle.fill` dismiss (calls `stopSurvey()` then `dismiss()`);
pulsing red dot indicator (`@State private var recordingPulse`, `.repeatForever(autoreverses: true)`).

`.onAppear`: if not surveying → `startSurvey()`, set `recordingPulse = true`.
`.onDisappear`: `stopSurvey()`.

Accessibility: `screen_activeMappingSurvey`, `heatmap_survey_button_close`.

### Task 6.2 — `ARContinuousHeatmapView.swift` (new file)

```swift
struct ARContinuousHeatmapView: View {
    @State private var viewModel = ARContinuousHeatmapViewModel()
    var onComplete: (HeatmapSurvey?) -> Void
}
```

Body: `ZStack` — if `ARContinuousHeatmapSession.isSupported` → `arContent` else `unsupportedContent`.
`.statusBarHidden(true).ignoresSafeArea()`.
`.onAppear { viewModel.startScanning() }`.
`.onDisappear { if isScanning { viewModel.stopScanning() } }`.

**arContent (real device only, guarded with `#if os(iOS) && !targetEnvironment(simulator)`):**
`ZStack(alignment: .bottom)`:
- `ARViewRepresentable(session: viewModel.session)` fills screen
- `statusOverlay` (shown when `!floorDetected`): centered spinner + statusMessage in glass
- Bottom chrome: `colorScaleStrip` + `apInfoBar`, both padded from bottom
- `.overlay(alignment: .top)`: `topBar` with `padding(.top, 56)`

**topBar:** ✕ button (onComplete(nil)) + "Signal Strength" title + "Done" button (onComplete(buildSurvey())) + SSID subtitle below

**colorScaleStrip:** `HStack` — "dBm" label + `GeometryReader` with:
- `LinearGradient` bar red→green clipped to RoundedRectangle height 12
- `HStack` with ForEach([-80,-70,-60,-50,-40,-30]) labels offset below bar

**apInfoBar:** icon circle + SSID/BSSID VStack + signal dBm/band VStack + glass background

**statusOverlay:** `ProgressView` + `Text(viewModel.statusMessage)` in glass pill, centered

**unsupportedContent:** dark screen with SF symbol + explanation + "Go Back" button

**Simulator branch of arContent:** black placeholder + "AR not available in Simulator" text + chrome

Accessibility identifiers: `screen_arContinuousHeatmap`, `ar_continuous_button_close/done`,
`ar_continuous_status_overlay`, `ar_continuous_color_scale`, `ar_continuous_ap_info_bar`.

### Task 6.3 — `ARWiFiSignalView.swift` (new file)

`struct ARWiFiSignalView: View` — `@State private var viewModel = ARWiFiViewModel()`

Body: `ZStack` — if `viewModel.isARSupported` → `arOverlayContent` else `fallbackContent`.

**arOverlayContent (guarded):** `ARViewContainer(arSession:)` fullscreen + `signalHUD` GlassCard
at top + "Drop Signal Anchor" button at bottom.

**signalHUD:** SF wifi icon, dBm value, signal label, `ProgressView(value: signalQuality)`,
optional SSID/BSSID row, optional errorMessage.

**fallbackContent:** gradient background ScrollView with AR-unavailable label + signalHUD.

`.onAppear { viewModel.startSession() }`, `.onDisappear { viewModel.stopSession() }`.

### Task 6.4 — `HeatmapResultView.swift` (new file)

```swift
struct HeatmapResultView: View {
    let survey: HeatmapSurvey
    @Bindable var viewModel: WiFiHeatmapSurveyViewModel
}
```

`ScrollView` with:
1. `summaryCard`: mode badge, calibration badge, point count, avg dBm, signal level, date
2. Canvas section (height 300): non-interactive `HeatmapCanvasView` + fullscreen expand button
3. `HeatmapControlStrip` (non-surveying, no stop button)
4. `MeasurementsPanel`

Fullscreen: `.fullScreenCover` presenting `HeatmapFullScreenView` bound to `localPoints`
(`@State` copy of `survey.dataPoints`, set in `.onAppear`).

Trash button in toolbar: `.confirmationDialog` → `viewModel.deleteSurvey(survey)` + `dismiss()`.

Accessibility: `screen_heatmapResult`, `heatmap_result_summary_card`,
`heatmap_result_button_delete`, `heatmap_result_button_fullscreen`.

### Task 6.5 — Register all new Views in `project.yml` if needed

Run `xcodegen generate`.

### Gate 6

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/Views/Tools/
```

---

## Chunk 7 — Navigation shell

### Task 7.1 — `FloorPlanSelectionView.swift` (new file)

```swift
struct FloorPlanSelectionView: View {
    let viewModel: WiFiHeatmapSurveyViewModel
    var onProceed: () -> Void
    var onARSurveyComplete: ((HeatmapSurvey) -> Void)?
}
```

`NavigationStack` body (presented as `.sheet`, detents `[.medium, .large]`, drag indicator visible):

Header text, then four `SourceCard` option buttons:
1. **AR Continuous Scan** → sets `showARContinuousScan = true`
   - Badge "RECOMMENDED" (green) if supported, "AR REQUIRED" (yellow) if not
2. **AR LiDAR Scan** → sets `showARScan = true`
   - Badge "LIDAR REQUIRED" (yellow) if not supported
3. **Import Floor Plan** → `PhotosPicker` with `.images` matching
4. **Freeform Grid** → `viewModel.floorplanImageData = nil`, `selectedMode = .freeform`, `onProceed()`

Sheet modifiers:
- `.sheet(isPresented: $showCalibration)` → `CalibrationView`
- `.fullScreenCover(isPresented: $showARScan)` → `RoomPlanScanView`
- `.fullScreenCover(isPresented: $showARContinuousScan)` → `ARContinuousHeatmapView { survey in ... }`
- `.onChange(of: selectedPhoto)` → load data, set `floorplanImageData`, show calibration

AR continuous completion: dismiss cover, call `onARSurveyComplete?(survey)` if non-nil.
LiDAR completion: set `floorplanImageData`, `selectedMode = .floorplan`, optionally set calibration.

`SourceCard` private struct: `icon`, `iconColor`, `title`, `subtitle`, `badge?`, `badgeColor`
→ GlassCard-styled HStack with chevron.

Accessibility: `screen_floorPlanSelection`, `floorplan_button_cancel`,
`floorplan_option_ar_continuous/ar/import/freeform`.

### Task 7.2 — `HeatmapDashboardView.swift` (new file)

`struct HeatmapDashboardView: View` — owns `@State private var viewModel = WiFiHeatmapSurveyViewModel()`

State: `showFloorPlanSelection`, `shouldStartSurvey`, `resultSurvey: HeatmapSurvey?`,
`showResultSurvey`

`ScrollView` body:
- `networkStatusCard` GlassCard: "TARGET NETWORK" label, LIVE badge, wifi icon, signal text
- `startScanButton`: full-width gradient button → `showFloorPlanSelection = true`
- `savedSurveysSection` (if `!surveys.isEmpty`): "Saved Surveys" header + GlassCard with
  `ForEach` survey rows; each row taps to set `resultSurvey` + `showResultSurvey = true`

Survey row: mode icon circle + name/avg/count/date + chevron. Show ruler badge if calibrated.

Sheet/destination modifiers:
- `.sheet(isPresented: $showFloorPlanSelection)` → `FloorPlanSelectionView`
  with `onProceed` (dismiss + 350 ms delay + `shouldStartSurvey = true`)
  and `onARSurveyComplete` (dismiss + `viewModel.addSurvey(survey)` + navigate to result)
- `.navigationDestination(isPresented: $shouldStartSurvey)` → `WiFiHeatmapSurveyView`
- `.navigationDestination(isPresented: $showResultSurvey)` → `HeatmapResultView` (if let)

Accessibility: `screen_heatmapDashboard`, `heatmap_dashboard_network_card`,
`heatmap_dashboard_button_new_scan`, `heatmap_survey_row_\(index)`,
`heatmap_dashboard_saved_surveys`.

### Task 7.3 — Wire into app tab bar / tool list

In the iOS tool list (wherever the app's tool navigation is defined), add a navigation link
to `HeatmapDashboardView` labelled "Wi-Fi Heatmap" with system image `wifi.square.fill` (or
whatever the existing tool list uses).

Also add `ARWiFiSignalView` as a separate tool entry ("AR WiFi Signal", `camera.viewfinder`).

### Task 7.4 — Register new files in `project.yml`

Run `xcodegen generate`.

### Gate 7

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
swiftlint lint --quiet NetMonitor-iOS/
```

Full app must build with zero errors.

---

## Chunk 8 — Entitlements and Info.plist

### Task 8.1 — Add WiFi Information entitlement

In `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements`:

```xml
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

Then in Xcode (or Apple Developer portal): Signing & Capabilities → + Capability →
**Access WiFi Information**. The capability must appear in the provisioning profile,
not just the entitlements file.

### Task 8.2 — Info.plist additions via `project.yml`

In `project.yml` under the iOS target's `info.plist` / `properties` section, confirm or add:

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

Run `xcodegen generate` after editing `project.yml`.

### Gate 8

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

---

## Chunk 9 — Tests

All tests run on the mac-mini via SSH. Write tests locally, push, then run remotely.

### Task 9.1 — `HeatmapModelsTests.swift` (NetMonitorCoreTests)

```swift
@Suite("HeatmapModels") struct HeatmapModelsTests {
    @Test func averageSignal_emptyReturnsNil()
    @Test func averageSignal_multiplePoints()
    @Test func signalLevel_fromRSSI_boundaries()  // -50 = strong, -51 = fair, -70 = fair, -71 = weak
    @Test func calibrationScale_pixelsPerUnit()
    @Test func heatmapSurvey_codable_roundTrip()
}
```

### Task 9.2 — `HeatmapRendererTests.swift` (NetMonitorCoreTests)

```swift
@Suite("HeatmapRenderer") struct HeatmapRendererTests {
    @Test func colorComponents_minRSSI()      // -100 → blue (thermal t=0)
    @Test func colorComponents_maxRSSI()      // -30  → red  (thermal t=1)
    @Test func colorComponents_midRSSI()      // -65  → somewhere in between, not zero
    @Test func idwGrid_noPoints_allNil()
    @Test func idwGrid_singlePointAtCenter()  // center cells non-nil, edges nil
    @Test func idwGrid_weightedAverage()      // two points, check midpoint ≈ average
    @Test func scaleBar_picksLargestFitting()
    @Test func scaleBar_zeroPixelsPerUnit()
}
```

### Task 9.3 — `WiFiSignalSamplerTests.swift` (NetMonitor-iOSTests)

Use a mock conforming to `WiFiInfoServiceProtocol`.

```swift
@Suite("WiFiSignalSampler") struct WiFiSignalSamplerTests {
    @Test func returnsDBmFromService()
    @Test func fallsBackToLastKnownWhenNil()
    @Test func convertsPercentToDBm()
    @Test func defaultsToMinusSeventyWhenNoHistory()
    @Test func updatesLastKnownOnEachCall()
}
```

### Task 9.4 — `WiFiHeatmapSurveyViewModelTests.swift` (NetMonitor-iOSTests)

Use mock `WiFiHeatmapServiceProtocol` and mock `WiFiSignalSampling`.

```swift
@Suite("WiFiHeatmapSurveyViewModel") struct WiFiHeatmapSurveyViewModelTests {
    @Test func startSurvey_setsIsSurveying()
    @Test func stopSurvey_clearsIsSurveying()
    @Test func recordDataPoint_normalizesCorrectly()  // point at (100, 200) in 400×400 = (0.25, 0.5)
    @Test func stopSurvey_createsSurveyFromService()
    @Test func deleteSurvey_removesFromList()
    @Test func surveys_persistThroughReload()         // save, create new VM, check surveys loaded
    @Test func colorScheme_persistedToUserDefaults()
}
```

### Task 9.5 — `ARContinuousHeatmapViewModelTests.swift` (NetMonitor-iOSTests)

Inject a mock `ARContinuousHeatmapSession` (or use the simulator stub directly since
`ARContinuousHeatmapSession` on simulator is a no-op stub).

```swift
@Suite("ARContinuousHeatmapViewModel") struct ARContinuousHeatmapViewModelTests {
    @Test func startScanning_setsIsScanning()
    @Test func stopScanning_clearsIsScanning()
    @Test func distanceExceeded_trueWhenOverThreshold()   // SIMD3(0.4, 0, 0) from origin
    @Test func distanceExceeded_falseWhenUnder()          // SIMD3(0.2, 0, 0) from origin
    @Test func distanceExceeded_trueWithNilLastPosition() // first call always records
    @Test func injectWorldPoint_incrementsPointCount()
    @Test func buildSurvey_nilWhenNoPoints()
    @Test func buildSurvey_normalizesWorldPoints()        // inject 3 world pts, check 0–1 range
    @Test func renderGridTexture_returnsNonNilImage()
    @Test func gridState_allNilAfterReset()
}
```

### Task 9.6 — UI Tests (optional but expected)

`WiFiHeatmapSurveyUITests.swift`:
- Launch app, navigate to heatmap
- Tap "New Scan", assert `screen_floorPlanSelection` appears
- Tap Freeform, assert `screen_activeMappingSurvey` appears
- Tap canvas, assert point count increases
- Tap close, assert dashboard visible with one saved survey row

`ARWiFiSignalUITests.swift`:
- Navigate to AR WiFi Signal tool
- Assert signal HUD elements visible

### Task 9.7 — Run tests on mac-mini

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && \
  xcodebuild test -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -30"
```

All tests must pass. Fix any failures before declaring the feature complete.

### Gate 9 (final)

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && \
  xcodebuild test -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E 'Test Suite|passed|failed|error'"
```

```bash
swiftlint lint --quiet
```

Both must be clean.

---

## File creation order summary

```
Chunk 1 (NetMonitorCore):
  Packages/NetMonitorCore/Sources/NetMonitorCore/Services/ServiceProtocols.swift  (edit)
  Packages/NetMonitorCore/Sources/NetMonitorCore/Models/HeatmapModels.swift       (new)
  Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/HeatmapRenderer.swift  (new)

Chunk 2 (Platform services):
  NetMonitor-iOS/Platform/AppSettings.swift                                        (edit)
  NetMonitor-iOS/Platform/WiFiInfoService.swift                                    (new)
  NetMonitor-iOS/Platform/WiFiSignalSampler.swift                                  (new)
  NetMonitor-iOS/Platform/WiFiHeatmapService.swift                                 (new)

Chunk 3 (ViewModels):
  NetMonitor-iOS/ViewModels/WiFiHeatmapSurveyViewModel.swift                       (new)
  NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift                     (new)
  NetMonitor-iOS/ViewModels/ARWiFiViewModel.swift                                  (new)

Chunk 4 (AR sessions):
  NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift                        (new)
  NetMonitor-iOS/Platform/ARWiFiSession.swift                                      (new)
  NetMonitor-iOS/Views/Tools/RoomPlanScanView.swift                                (new)

Chunk 5 (Shared UI):
  NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift                               (new)
  NetMonitor-iOS/Views/Tools/HeatmapControlStrip.swift                             (new)
  NetMonitor-iOS/Views/Tools/HeatmapFullScreenView.swift                           (new)
  NetMonitor-iOS/Views/Tools/MeasurementsPanel.swift                               (new)
  NetMonitor-iOS/Views/Tools/CalibrationView.swift                                 (new)

Chunk 6 (Feature views):
  NetMonitor-iOS/Views/Tools/WiFiHeatmapSurveyView.swift                           (new)
  NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift                         (new)
  NetMonitor-iOS/Views/Tools/ARWiFiSignalView.swift                                (new)
  NetMonitor-iOS/Views/Tools/HeatmapResultView.swift                               (new)

Chunk 7 (Navigation):
  NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift                          (new)
  NetMonitor-iOS/Views/Tools/HeatmapDashboardView.swift                            (new)
  [app tool list file]                                                              (edit)

Chunk 8 (Config):
  NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements                             (edit)
  project.yml                                                                      (edit)

Chunk 9 (Tests):
  Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapModelsTests.swift       (new)
  Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift     (new)
  Tests/NetMonitor-iOSTests/WiFiSignalSamplerTests.swift                           (new)
  Tests/NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests.swift                  (new)
  Tests/NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests.swift                (new)
  Tests/NetMonitor-iOSUITests/WiFiHeatmapSurveyUITests.swift                       (new)
  Tests/NetMonitor-iOSUITests/ARWiFiSignalUITests.swift                            (new)
```

---

## Key constraints to preserve throughout

- **Never store `ARPlaneAnchor`** — always copy `anchor.transform: simd_float4x4` before the delegate method returns
- **Never call `AVCaptureDevice.requestAccess` before `session.run()`** — ARKit handles this
- **`HeatmapDataPoint.x/y` are always `[0,1]`** — normalize at the point of recording or on survey build, never store pixel coordinates
- **`WiFiSignalSampler.dbm` is never nil** — callers use `usingEstimatedSignal: Bool` flag to distinguish live vs estimated
- **Swift 6 strict concurrency** — all service protocols are `Sendable`; ViewModels are `@MainActor @Observable`; `nonisolated` delegate callbacks dispatch back to `MainActor` via `Task { @MainActor in ... }`
- **Simulator stubs required for ARKit types** — every file that imports `ARKit` or `RealityKit` must be wrapped in `#if os(iOS) && !targetEnvironment(simulator)` with a matching stub outside the guard
