# WiFi Heatmap Redesign Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the WiFi Heatmap tool with full-screen floor plan canvas, skippable scale calibration, thermal gradient rendering with four display overlays, a rich measurements panel, and a complete macOS implementation with CoreWLAN signal reading.

**Architecture:** New pure-logic `HeatmapRenderer` type lives in NetMonitorCore for IDW interpolation and color mapping; platform-specific SwiftUI Views consume it. iOS gets a shared `HeatmapCanvasView`, a `CalibrationView` sheet, a `HeatmapControlStrip`, a `MeasurementsPanel`, and a full-screen cover. macOS gets a three-column `NavigationSplitView` with its own `WiFiHeatmapToolView` and a `WiFiHeatmapService` backed by CoreWLAN.

**Tech Stack:** SwiftUI Canvas API, Swift 6 strict concurrency, Swift Testing (`@Suite`/`@Test`/`#expect`), CoreWLAN (macOS), NetworkExtension (iOS), XcodeGen for project generation.

---

## Chunk 1: Core Logic — Models + Renderer

### Task 1: Extend HeatmapModels with new types

**Files:**
- Modify: `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/HeatmapModels.swift`
- Modify: `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapModelsTests.swift`

- [ ] **Step 1.1: Write failing tests for the new model types**

Open `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapModelsTests.swift` and append these test suites at the end of the file (before the last `}`):

```swift
// MARK: - DistanceUnit Tests

@Suite("DistanceUnit")
struct DistanceUnitTests {

    @Test("feet displayName is ft")
    func feetDisplayName() {
        #expect(DistanceUnit.feet.displayName == "ft")
    }

    @Test("meters displayName is m")
    func metersDisplayName() {
        #expect(DistanceUnit.meters.displayName == "m")
    }

    @Test("feet to meters conversion")
    func feetToMeters() {
        let result = DistanceUnit.feet.convert(10, to: .meters)
        #expect(abs(result - 3.048) < 0.001)
    }

    @Test("meters to feet conversion")
    func metersToFeet() {
        let result = DistanceUnit.meters.convert(3.048, to: .feet)
        #expect(abs(result - 10.0) < 0.001)
    }

    @Test("same unit convert is identity")
    func sameUnitIdentity() {
        #expect(DistanceUnit.feet.convert(5, to: .feet) == 5)
    }
}

// MARK: - CalibrationScale Tests

@Suite("CalibrationScale")
struct CalibrationScaleTests {

    @Test("pixelsPerUnit computes correctly")
    func pixelsPerUnit() {
        let scale = CalibrationScale(pixelDistance: 200, realDistance: 10, unit: .feet)
        #expect(scale.pixelsPerUnit == 20.0)
    }

    @Test("realDistance(pixels:) converts correctly")
    func realDistanceFromPixels() {
        let scale = CalibrationScale(pixelDistance: 200, realDistance: 10, unit: .feet)
        #expect(scale.realDistance(pixels: 100) == 5.0)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = CalibrationScale(pixelDistance: 150.5, realDistance: 5.0, unit: .meters)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalibrationScale.self, from: data)
        #expect(decoded.pixelDistance == original.pixelDistance)
        #expect(decoded.realDistance == original.realDistance)
        #expect(decoded.unit == original.unit)
    }
}

// MARK: - HeatmapColorScheme Tests

@Suite("HeatmapColorScheme")
struct HeatmapColorSchemeTests {

    @Test("all cases exist")
    func allCases() {
        let cases = HeatmapColorScheme.allCases
        #expect(cases.contains(.thermal))
        #expect(cases.contains(.signal))
        #expect(cases.contains(.nebula))
        #expect(cases.contains(.arctic))
    }

    @Test("thermal has non-empty stop table")
    func thermalStops() {
        #expect(!HeatmapColorScheme.thermal.colorStops.isEmpty)
    }

    @Test("all schemes have at least 2 color stops")
    func allSchemesHaveStops() {
        for scheme in HeatmapColorScheme.allCases {
            #expect(scheme.colorStops.count >= 2, "scheme \(scheme.rawValue) needs ≥ 2 stops")
        }
    }

    @Test("Codable round-trip")
    func codable() throws {
        let data = try JSONEncoder().encode(HeatmapColorScheme.thermal)
        let decoded = try JSONDecoder().decode(HeatmapColorScheme.self, from: data)
        #expect(decoded == .thermal)
    }
}

// MARK: - HeatmapDisplayOverlay Tests

@Suite("HeatmapDisplayOverlay")
struct HeatmapDisplayOverlayTests {

    @Test("default contains gradient")
    func defaultContainsGradient() {
        let overlay = HeatmapDisplayOverlay.gradient
        #expect(overlay.contains(.gradient))
        #expect(!overlay.contains(.dots))
    }

    @Test("union works")
    func union() {
        let combo: HeatmapDisplayOverlay = [.gradient, .dots]
        #expect(combo.contains(.gradient))
        #expect(combo.contains(.dots))
        #expect(!combo.contains(.contour))
    }

    @Test("Codable round-trip")
    func codable() throws {
        let overlay: HeatmapDisplayOverlay = [.gradient, .contour]
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(HeatmapDisplayOverlay.self, from: data)
        #expect(decoded == overlay)
    }
}

// MARK: - HeatmapSurvey calibration field tests

@Suite("HeatmapSurvey calibration")
struct HeatmapSurveyCalibratedTests {

    @Test("uncalibrated survey decodes without calibration field (backward compat)")
    func backwardCompatibility() throws {
        // Old JSON without calibration field
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Old Survey",
         "mode":"freeform","createdAt":0,"dataPoints":[]}
        """
        let survey = try JSONDecoder().decode(HeatmapSurvey.self, from: Data(json.utf8))
        #expect(survey.calibration == nil)
    }

    @Test("calibrated survey encodes and decodes calibration")
    func calibratedRoundTrip() throws {
        let scale = CalibrationScale(pixelDistance: 100, realDistance: 20, unit: .feet)
        var survey = HeatmapSurvey(name: "Test")
        survey.calibration = scale
        let data = try JSONEncoder().encode(survey)
        let decoded = try JSONDecoder().decode(HeatmapSurvey.self, from: data)
        #expect(decoded.calibration?.pixelDistance == 100)
        #expect(decoded.calibration?.unit == .feet)
    }
}
```

- [ ] **Step 1.2: Run tests — expect failures on missing types**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swift test --package-path Packages/NetMonitorCore 2>&1 | grep -E "error:|FAILED|cannot find"
```

Expected: multiple "cannot find type" errors for `DistanceUnit`, `CalibrationScale`, `HeatmapColorScheme`, `HeatmapDisplayOverlay`.

- [ ] **Step 1.3: Add new types to HeatmapModels.swift**

Open `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/HeatmapModels.swift` and add after the existing `HeatmapMode` enum:

```swift
// MARK: - DistanceUnit

public enum DistanceUnit: String, Codable, CaseIterable, Sendable, Equatable {
    case feet   = "ft"
    case meters = "m"

    public var displayName: String { rawValue }

    /// Convert `value` (in `self` units) to `target` units.
    public func convert(_ value: Double, to target: DistanceUnit) -> Double {
        guard self != target else { return value }
        return self == .feet ? value * 0.3048 : value / 0.3048
    }
}

// MARK: - CalibrationScale

/// Scale established by the user drawing a reference line on the floor plan.
public struct CalibrationScale: Codable, Sendable, Equatable {
    public let pixelDistance: Double   // px length of the drawn reference line
    public let realDistance: Double    // real-world distance entered by the user
    public let unit: DistanceUnit

    public init(pixelDistance: Double, realDistance: Double, unit: DistanceUnit) {
        self.pixelDistance = pixelDistance
        self.realDistance = realDistance
        self.unit = unit
    }

    public var pixelsPerUnit: Double { pixelDistance / realDistance }

    /// Convert a pixel distance to real-world units.
    public func realDistance(pixels: Double) -> Double { pixels / pixelsPerUnit }
}

// MARK: - HeatmapColorScheme

/// Color mapping for heatmap gradient rendering.
public enum HeatmapColorScheme: String, Codable, CaseIterable, Sendable, Equatable {
    case thermal = "thermal"  // blue → cyan → green → yellow → red (DEFAULT)
    case signal  = "signal"   // red → orange → yellow → green
    case nebula  = "nebula"   // navy → violet → magenta → white
    case arctic  = "arctic"   // navy → teal → ice blue → white

    public var displayName: String {
        switch self {
        case .thermal: "Thermal"
        case .signal:  "Signal"
        case .nebula:  "Nebula"
        case .arctic:  "Arctic"
        }
    }

    /// Color stops: (t: 0–1, hexRGB string). t=0 is weakest signal, t=1 is strongest.
    public var colorStops: [(t: Double, hex: String)] {
        switch self {
        case .thermal:
            return [(0, "000080"), (0.15, "0000ff"), (0.30, "00ffff"),
                    (0.50, "00ff00"), (0.70, "ffff00"), (0.85, "ff8800"), (1.0, "ff0000")]
        case .signal:
            return [(0, "cc0000"), (0.25, "ff4400"), (0.50, "ffcc00"),
                    (0.75, "88ff00"), (1.0, "00dd44")]
        case .nebula:
            return [(0, "0a0a2a"), (0.20, "1a0060"), (0.40, "6600aa"),
                    (0.60, "cc00aa"), (0.80, "ff44cc"), (1.0, "ffffff")]
        case .arctic:
            return [(0, "050a14"), (0.20, "062040"), (0.40, "0a4060"),
                    (0.60, "1088aa"), (0.80, "44ccdd"), (1.0, "ffffff")]
        }
    }
}

// MARK: - HeatmapDisplayOverlay

/// Bit-mask of active rendering overlays. Multiple may be combined.
public struct HeatmapDisplayOverlay: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let gradient  = HeatmapDisplayOverlay(rawValue: 1 << 0)  // default ON
    public static let dots      = HeatmapDisplayOverlay(rawValue: 1 << 1)
    public static let contour   = HeatmapDisplayOverlay(rawValue: 1 << 2)
    public static let deadZones = HeatmapDisplayOverlay(rawValue: 1 << 3)
}
```

Then update `HeatmapSurvey` to add the `calibration` field (make it `var` not `let` since it's set post-init):

```swift
// In HeatmapSurvey struct, add after `var dataPoints`:
public var calibration: CalibrationScale? = nil
```

Also update the `init` to accept it:
```swift
public init(
    id: UUID = UUID(),
    name: String,
    mode: HeatmapMode = .freeform,
    createdAt: Date = Date(),
    dataPoints: [HeatmapDataPoint] = [],
    calibration: CalibrationScale? = nil
) {
    self.id = id
    self.name = name
    self.mode = mode
    self.createdAt = createdAt
    self.dataPoints = dataPoints
    self.calibration = calibration
}
```

- [ ] **Step 1.4: Run tests — expect all to pass**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swift test --package-path Packages/NetMonitorCore 2>&1 | grep -E "Test run|passed|failed"
```

Expected: All tests pass.

- [ ] **Step 1.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Models/HeatmapModels.swift \
        Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapModelsTests.swift
git commit -m "feat(models): add CalibrationScale, DistanceUnit, HeatmapColorScheme, HeatmapDisplayOverlay"
```

---

### Task 2: HeatmapRenderer — pure computation engine

**Files:**
- Create: `Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/HeatmapRenderer.swift`
- Create: `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift`

This type does all heavy computation (IDW interpolation, color conversion, stats, scale bar sizing) with no SwiftUI dependency. Views simply call it.

- [ ] **Step 2.1: Write failing tests**

Create `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift`:

```swift
import Foundation
import Testing
@testable import NetMonitorCore

@Suite("HeatmapRenderer")
struct HeatmapRendererTests {

    // MARK: - Color interpolation

    @Test("colorForRSSI at minimum returns first stop color")
    func colorAtMin() {
        let rgb = HeatmapRenderer.colorComponents(rssi: -100, scheme: .thermal)
        // t=0 → hex "000080" → r=0, g=0, b=128
        #expect(rgb.r == 0)
        #expect(rgb.g == 0)
        #expect(rgb.b == 128)
    }

    @Test("colorForRSSI at maximum returns last stop color")
    func colorAtMax() {
        let rgb = HeatmapRenderer.colorComponents(rssi: -30, scheme: .thermal)
        // t=1 → hex "ff0000" → r=255, g=0, b=0
        #expect(rgb.r == 255)
        #expect(rgb.g == 0)
        #expect(rgb.b == 0)
    }

    @Test("colorForRSSI clamps below -100")
    func colorBelowMin() {
        let rgb1 = HeatmapRenderer.colorComponents(rssi: -110, scheme: .thermal)
        let rgb2 = HeatmapRenderer.colorComponents(rssi: -100, scheme: .thermal)
        #expect(rgb1.r == rgb2.r && rgb1.g == rgb2.g && rgb1.b == rgb2.b)
    }

    // MARK: - IDW interpolation

    @Test("IDW grid with one point returns that point's RSSI at origin")
    func idwSinglePoint() {
        let points = [HeatmapDataPoint(x: 0.5, y: 0.5, signalStrength: -60, timestamp: Date())]
        let grid = HeatmapRenderer.idwGrid(points: points, gridSize: 4, canvasWidth: 100, canvasHeight: 100)
        // Centre cell (1,1) should be closest to (0.5,0.5) → rssi ≈ -60
        let centre = grid[1][1]
        #expect(centre != nil)
        #expect(abs(centre! - (-60)) < 5)
    }

    @Test("IDW grid cell far from all points returns nil when no points within 80pt")
    func idwFarCell() {
        // Point at top-left; query bottom-right at 200×200 canvas, far cell
        let points = [HeatmapDataPoint(x: 0.05, y: 0.05, signalStrength: -60, timestamp: Date())]
        let grid = HeatmapRenderer.idwGrid(points: points, gridSize: 4, canvasWidth: 200, canvasHeight: 200)
        // Bottom-right cell [3][3] should be ~190pt away (> 80pt threshold) → nil
        #expect(grid[3][3] == nil)
    }

    // MARK: - Stats

    @Test("stats with no points returns zeroed struct")
    func statsEmpty() {
        let stats = HeatmapRenderer.computeStats(points: [], calibration: nil, unit: .feet)
        #expect(stats.count == 0)
        #expect(stats.averageDBm == nil)
    }

    @Test("stats computes average correctly")
    func statsAverage() {
        let pts = [
            HeatmapDataPoint(x: 0, y: 0, signalStrength: -40, timestamp: Date()),
            HeatmapDataPoint(x: 1, y: 1, signalStrength: -60, timestamp: Date()),
        ]
        let stats = HeatmapRenderer.computeStats(points: pts, calibration: nil, unit: .feet)
        #expect(stats.averageDBm == -50)
        #expect(stats.strongestDBm == -40)
        #expect(stats.weakestDBm == -60)
    }

    // MARK: - Scale bar

    @Test("scaleBarLength picks a round number >= 50px")
    func scaleBar() {
        // 20px per foot, want a nice label
        let result = HeatmapRenderer.scaleBar(pixelsPerUnit: 20, unit: .feet)
        // Should pick 5 ft (= 100px) or 10 ft (= 200px) — both round numbers
        #expect(result.pixels >= 50)
        #expect([1, 2, 5, 10, 25, 50, 100].contains(result.labelValue))
    }
}
```

- [ ] **Step 2.2: Run tests — expect failures (type not found)**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swift test --package-path Packages/NetMonitorCore --filter HeatmapRendererTests 2>&1 | grep -E "error:|cannot find"
```

Expected: "cannot find type 'HeatmapRenderer'".

- [ ] **Step 2.3: Implement HeatmapRenderer**

Create `Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/HeatmapRenderer.swift`:

```swift
import Foundation

// MARK: - HeatmapRenderer

/// Pure-computation engine for heatmap rendering. No SwiftUI dependency.
/// Views call these methods and use the results to drive Canvas drawing.
public enum HeatmapRenderer {

    // MARK: - RGB Helper

    public struct RGB: Sendable {
        public let r: Int
        public let g: Int
        public let b: Int
    }

    // MARK: - Color Mapping

    /// Map an RSSI value (dBm) to an RGB color using the given scheme.
    /// RSSI range: −100 (weakest, t=0) … −30 (strongest, t=1)
    public static func colorComponents(rssi: Int, scheme: HeatmapColorScheme) -> RGB {
        let t = Double(rssi - (-100)) / Double((-30) - (-100))
        let tc = max(0.0, min(1.0, t))
        return interpolate(t: tc, stops: scheme.colorStops)
    }

    private static func interpolate(t: Double, stops: [(t: Double, hex: String)]) -> RGB {
        guard stops.count >= 2 else {
            return hexToRGB(stops.first?.hex ?? "000000")
        }
        var lo = stops[0]
        var hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if t >= stops[i].t && t <= stops[i + 1].t {
                lo = stops[i]
                hi = stops[i + 1]
                break
            }
        }
        let range = hi.t - lo.t
        let localT = range > 0 ? (t - lo.t) / range : 0.0
        let loRGB = hexToRGB(lo.hex)
        let hiRGB = hexToRGB(hi.hex)
        return RGB(
            r: Int(Double(loRGB.r) + Double(hiRGB.r - loRGB.r) * localT),
            g: Int(Double(loRGB.g) + Double(hiRGB.g - loRGB.g) * localT),
            b: Int(Double(loRGB.b) + Double(hiRGB.b - loRGB.b) * localT)
        )
    }

    private static func hexToRGB(_ hex: String) -> RGB {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let val = UInt32(h, radix: 16) ?? 0
        return RGB(r: Int((val >> 16) & 0xff), g: Int((val >> 8) & 0xff), b: Int(val & 0xff))
    }

    // MARK: - IDW Grid

    /// Compute a `gridSize×gridSize` matrix of interpolated RSSI values using
    /// Inverse Distance Weighting (k=4 nearest, max radius 80pt).
    /// Returns `nil` for cells with no nearby points (dead zones).
    public static func idwGrid(
        points: [HeatmapDataPoint],
        gridSize: Int,
        canvasWidth: Double,
        canvasHeight: Double,
        maxRadiusPt: Double = 80
    ) -> [[Double?]] {
        guard !points.isEmpty else {
            return Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)
        }
        let cellW = canvasWidth / Double(gridSize)
        let cellH = canvasHeight / Double(gridSize)
        var grid: [[Double?]] = Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cx = (Double(col) + 0.5) * cellW
                let cy = (Double(row) + 0.5) * cellH

                // Gather nearby points
                var weighted = 0.0
                var totalWeight = 0.0
                for pt in points {
                    let px = pt.x * canvasWidth
                    let py = pt.y * canvasHeight
                    let dx = cx - px
                    let dy = cy - py
                    let dist = sqrt(dx * dx + dy * dy)
                    guard dist < maxRadiusPt else { continue }
                    let w = dist < 0.001 ? 1e9 : 1.0 / (dist * dist)
                    weighted += w * Double(pt.signalStrength)
                    totalWeight += w
                }
                if totalWeight > 0 {
                    grid[row][col] = weighted / totalWeight
                }
            }
        }
        return grid
    }

    // MARK: - Stats

    public struct SurveyStats: Sendable {
        public let count: Int
        public let averageDBm: Int?
        public let strongestDBm: Int?
        public let weakestDBm: Int?
        /// Estimated coverage in square units (nil when uncalibrated).
        public let coverageArea: Double?
        /// % of measurement points that are ≥ −50 dBm.
        public let strongCoveragePercent: Int?
        /// Count of IDW cells with RSSI < −75 dBm.
        public let deadZoneCount: Int
    }

    public static func computeStats(
        points: [HeatmapDataPoint],
        calibration: CalibrationScale?,
        unit: DistanceUnit
    ) -> SurveyStats {
        guard !points.isEmpty else {
            return SurveyStats(count: 0, averageDBm: nil, strongestDBm: nil,
                               weakestDBm: nil, coverageArea: nil,
                               strongCoveragePercent: nil, deadZoneCount: 0)
        }
        let rssiValues = points.map { $0.signalStrength }
        let avg = rssiValues.reduce(0, +) / rssiValues.count
        let strongest = rssiValues.max()!
        let weakest = rssiValues.min()!
        let strongCount = rssiValues.filter { $0 >= -50 }.count
        let strongPct = (strongCount * 100) / rssiValues.count
        return SurveyStats(
            count: points.count,
            averageDBm: avg,
            strongestDBm: strongest,
            weakestDBm: weakest,
            coverageArea: nil,    // requires canvas size; computed in View
            strongCoveragePercent: strongPct,
            deadZoneCount: 0      // computed from IDW grid in View
        )
    }

    // MARK: - Scale Bar

    public struct ScaleBarConfig: Sendable {
        public let pixels: Double
        public let labelValue: Int
        public let unit: DistanceUnit
    }

    private static let roundNumbers = [1, 2, 5, 10, 25, 50, 100]

    /// Pick the largest round-number label that fits within `maxPixels`.
    public static func scaleBar(
        pixelsPerUnit: Double,
        unit: DistanceUnit,
        maxPixels: Double = 120
    ) -> ScaleBarConfig {
        var best = ScaleBarConfig(pixels: pixelsPerUnit, labelValue: 1, unit: unit)
        for n in roundNumbers {
            let px = pixelsPerUnit * Double(n)
            if px <= maxPixels { best = ScaleBarConfig(pixels: px, labelValue: n, unit: unit) }
        }
        return best
    }
}
```

- [ ] **Step 2.4: Run tests — expect all to pass**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swift test --package-path Packages/NetMonitorCore 2>&1 | grep -E "Test run|passed|failed"
```

Expected: All tests pass.

- [ ] **Step 2.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/HeatmapRenderer.swift \
        Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift
git commit -m "feat(renderer): add HeatmapRenderer with IDW interpolation, color mapping, and scale bar"
```

---

## Chunk 2: iOS Views

### Task 3: HeatmapCanvasView — shared rendering canvas

**Files:**
- Create: `NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift`

This view renders all four layers (gradient, dots, contour, dead zones) using SwiftUI `Canvas`. It is used by both the normal scroll view and the full-screen view. It also handles floor plan image display and tap-to-record.

- [ ] **Step 3.1: Run `xcodegen generate` after adding the file**

After creating the file below, run:
```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
```

- [ ] **Step 3.2: Create `NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift`**

```swift
import SwiftUI
import NetMonitorCore

// MARK: - HeatmapCanvasView

/// The central heatmap rendering canvas. Shared between the scroll-view layout
/// and `HeatmapFullScreenView`. Handles all four overlay layers.
struct HeatmapCanvasView: View {

    let points: [HeatmapDataPoint]
    let floorplanImage: UIImage?
    let colorScheme: HeatmapColorScheme
    let overlays: HeatmapDisplayOverlay
    let calibration: CalibrationScale?
    let isSurveying: Bool
    var onTap: ((CGPoint, CGSize) -> Void)?

    // Pulsing animation for dead zones
    @State private var deadZonePulse: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── 1. Background (floor plan or grid) ──────────────────────
                backgroundLayer(in: geo.size)

                // ── 2. Gradient heatmap ──────────────────────────────────────
                if overlays.contains(.gradient) {
                    Canvas { ctx, size in
                        drawGradient(context: ctx, size: size)
                    }
                }

                // ── 3. Dead zone highlight (animated) ───────────────────────
                if overlays.contains(.deadZones) {
                    Canvas { ctx, size in
                        drawDeadZones(context: ctx, size: size, opacity: deadZonePulse)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            deadZonePulse = 0.45
                        }
                    }
                }

                // ── 4. Contour lines ─────────────────────────────────────────
                if overlays.contains(.contour) {
                    Canvas { ctx, size in
                        drawContours(context: ctx, size: size)
                    }
                }

                // ── 5. Measurement dots ──────────────────────────────────────
                if overlays.contains(.dots) {
                    Canvas { ctx, size in
                        drawDots(context: ctx, size: size)
                    }
                }

                // ── 6. Scale bar ─────────────────────────────────────────────
                if let cal = calibration {
                    scaleBarView(calibration: cal, canvasSize: geo.size)
                }

                // ── 7. Tap capture ───────────────────────────────────────────
                if isSurveying {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { loc in
                            onTap?(loc, geo.size)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(in size: CGSize) -> some View {
        if let img = floorplanImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(0.55)
        } else {
            Canvas { ctx, size in
                let step: CGFloat = 40
                var x: CGFloat = 0
                while x <= size.width {
                    ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) },
                               with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                               with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                    y += step
                }
            }
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: - Gradient Layer

    private func drawGradient(context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.blendMode = .screen
        for pt in points {
            let cx = pt.x * size.width
            let cy = pt.y * size.height
            let rgb = HeatmapRenderer.colorComponents(rssi: pt.signalStrength, scheme: colorScheme)
            let color = Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
            let radius: CGFloat = adaptiveRadius(for: size)
            let grad = Gradient(colors: [color.opacity(0.85), color.opacity(0)])
            let radialGrad = GraphicsContext.Shading.radialGradient(
                grad,
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: radius
            )
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: radialGrad)
        }
    }

    private func adaptiveRadius(for size: CGSize) -> CGFloat {
        guard points.count > 1 else { return 80 }
        // Rough estimate: radius so blobs cover the canvas with ~2x overlap at median density
        let area = size.width * size.height
        let perPoint = area / CGFloat(points.count)
        return max(40, min(100, sqrt(perPoint) * 0.9))
    }

    // MARK: - Dead Zones

    private func drawDeadZones(context: GraphicsContext, size: CGSize, opacity: Double) {
        guard !points.isEmpty else { return }
        let gridSize = 40
        let grid = HeatmapRenderer.idwGrid(
            points: points, gridSize: gridSize,
            canvasWidth: size.width, canvasHeight: size.height
        )
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                guard let rssi = grid[row][col], rssi < -75 else { continue }
                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH,
                                  width: cellW, height: cellH)
                context.fill(Path(rect), with: .color(.red.opacity(opacity)))
            }
        }
    }

    // MARK: - Contour Lines

    private func drawContours(context: GraphicsContext, size: CGSize) {
        guard points.count >= 3 else { return }
        let gridSize = 40
        let grid = HeatmapRenderer.idwGrid(
            points: points, gridSize: gridSize,
            canvasWidth: size.width, canvasHeight: size.height
        )
        let thresholds: [(rssi: Double, color: Color)] = [
            (-50, .green), (-65, .yellow), (-80, .red)
        ]
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)

        for (threshold, color) in thresholds {
            var path = Path()
            for row in 0..<(gridSize - 1) {
                for col in 0..<(gridSize - 1) {
                    guard let v = grid[row][col], let vr = grid[row][col + 1],
                          let vb = grid[row + 1][col] else { continue }
                    // Simple threshold crossing — draw a line segment where signal crosses threshold
                    let x = CGFloat(col) * cellW + cellW / 2
                    let y = CGFloat(row) * cellH + cellH / 2
                    if (v < threshold) != (vr < threshold) {
                        path.move(to: CGPoint(x: x + cellW, y: y))
                        path.addLine(to: CGPoint(x: x + cellW, y: y + cellH))
                    }
                    if (v < threshold) != (vb < threshold) {
                        path.move(to: CGPoint(x: x, y: y + cellH))
                        path.addLine(to: CGPoint(x: x + cellW, y: y + cellH))
                    }
                }
            }
            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
        }
    }

    // MARK: - Measurement Dots

    private func drawDots(context: GraphicsContext, size: CGSize) {
        for pt in points {
            let cx = pt.x * size.width
            let cy = pt.y * size.height
            let rgb = HeatmapRenderer.colorComponents(rssi: pt.signalStrength, scheme: colorScheme)
            let color = Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
            let r: CGFloat = 9
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 1)
            // dBm label
            var text = AttributedString("\(pt.signalStrength)")
            text.font = .init(.monospacedSystemFont(ofSize: 9, weight: .regular))
            text.foregroundColor = UIColor.white
            context.draw(Text(text), at: CGPoint(x: cx, y: cy + r + 8))
        }
    }

    // MARK: - Scale Bar

    private func scaleBarView(calibration: CalibrationScale, canvasSize: CGSize) -> some View {
        let config = HeatmapRenderer.scaleBar(pixelsPerUnit: calibration.pixelsPerUnit)
        return VStack(alignment: .leading, spacing: 2) {
            // Tick marks + line
            ZStack(alignment: .leading) {
                Rectangle()
                    .frame(width: config.pixels, height: 2)
                    .foregroundStyle(Color.white.opacity(0.9))
                HStack {
                    Rectangle().frame(width: 1, height: 8).foregroundStyle(Color.white)
                    Spacer()
                    Rectangle().frame(width: 1, height: 8).foregroundStyle(Color.white)
                }
                .frame(width: config.pixels)
            }
            Text("\(config.labelValue) \(config.unit.displayName)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(10)
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3.3: Build iOS to check for compile errors**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 3.4: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift
git commit -m "feat(ios): add HeatmapCanvasView with gradient, dots, contour, and dead-zone overlays"
```

---

### Task 4: CalibrationView — draw-line + distance entry

**Files:**
- Create: `NetMonitor-iOS/Views/Tools/CalibrationView.swift`

Presented as a sheet after importing a floor plan. User drags to draw a reference line, enters the real-world distance, and taps "Set Scale" or "Skip".

- [ ] **Step 4.1: Create `NetMonitor-iOS/Views/Tools/CalibrationView.swift`**

```swift
import SwiftUI
import NetMonitorCore

// MARK: - CalibrationView

/// Presented as a sheet after importing a floor plan.
/// The user draws a reference line on the image and enters the real-world distance.
struct CalibrationView: View {
    let floorplanImage: UIImage?
    /// Called with the completed scale, or nil when skipped.
    var onComplete: (CalibrationScale?) -> Void

    @State private var lineStart: CGPoint? = nil
    @State private var lineEnd: CGPoint?   = nil
    @State private var isDragging = false
    @State private var showDistanceEntry = false
    @State private var distanceText = ""
    @State private var unit: DistanceUnit = .feet
    @State private var canvasSize: CGSize = .zero

    private var pixelDistance: Double? {
        guard let s = lineStart, let e = lineEnd else { return nil }
        let dx = e.x - s.x
        let dy = e.y - s.y
        return sqrt(dx * dx + dy * dy)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionBanner
                canvasArea
                if showDistanceEntry { distancePanel }
            }
            .themedBackground()
            .navigationTitle("Calibrate Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { onComplete(nil) }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("calibration_button_skip")
                }
            }
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "ruler")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lineStart == nil ? "Draw a Reference Line" : (showDistanceEntry ? "Enter Real Distance" : "Drag to extend line"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(lineStart == nil
                         ? "Drag between two points whose real distance you know"
                         : pixelLengthDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if lineStart != nil {
                    Button("Reset") {
                        lineStart = nil; lineEnd = nil; showDistanceEntry = false
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.top, 8)
    }

    private var pixelLengthDescription: String {
        guard let d = pixelDistance else { return "" }
        return String(format: "Line length: %.0f px — enter real distance below", d)
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                // Floor plan
                if let img = floorplanImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.7)
                }

                // Drawn line
                if let s = lineStart, let e = lineEnd ?? lineStart {
                    Canvas { ctx, _ in
                        // Dashed cyan line
                        var path = Path()
                        path.move(to: s)
                        path.addLine(to: e)
                        ctx.stroke(path, with: .color(Theme.Colors.accent.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                        // Endpoint handles
                        for pt in [s, e] {
                            let r: CGFloat = 7
                            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.Colors.accent))
                            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { val in
                        if lineStart == nil || (!isDragging) {
                            lineStart = val.startLocation
                            isDragging = true
                            showDistanceEntry = false
                        }
                        lineEnd = val.location
                    }
                    .onEnded { _ in
                        isDragging = false
                        if pixelDistance ?? 0 > 20 {
                            showDistanceEntry = true
                        }
                    }
            )
            .onAppear { canvasSize = geo.size }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 8)
    }

    // MARK: - Distance Entry Panel

    private var distancePanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Real-world distance of this line:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(spacing: 10) {
                    TextField("e.g. 12", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(10)
                        .background(Theme.Colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Colors.accent.opacity(0.4)))
                        .accessibilityIdentifier("calibration_input_distance")

                    Picker("Unit", selection: $unit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .accessibilityIdentifier("calibration_picker_unit")

                    Button("Set Scale") {
                        commitCalibration()
                    }
                    .disabled(Double(distanceText) == nil || (Double(distanceText) ?? 0) <= 0)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("calibration_button_set")
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35), value: showDistanceEntry)
    }

    private func commitCalibration() {
        guard let dist = Double(distanceText), dist > 0,
              let px = pixelDistance else { return }
        let scale = CalibrationScale(pixelDistance: px, realDistance: dist, unit: unit)
        onComplete(scale)
    }
}
```

- [ ] **Step 4.2: Build iOS**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/CalibrationView.swift
git commit -m "feat(ios): add CalibrationView with drag-line and distance entry"
```

---

### Task 5: HeatmapControlStrip + MeasurementsPanel

**Files:**
- Create: `NetMonitor-iOS/Views/Tools/HeatmapControlStrip.swift`
- Create: `NetMonitor-iOS/Views/Tools/MeasurementsPanel.swift`

- [ ] **Step 5.1: Create `NetMonitor-iOS/Views/Tools/HeatmapControlStrip.swift`**

Horizontal strip with scheme picker and overlay toggles. Used below the canvas and inside full-screen mode.

```swift
import SwiftUI
import NetMonitorCore

// MARK: - HeatmapControlStrip

/// Compact control strip for scheme and overlay selection.
/// Adapts between horizontal (normal) and vertical (landscape full-screen sidebar).
struct HeatmapControlStrip: View {
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var overlays: HeatmapDisplayOverlay
    let isSurveying: Bool
    var onStopSurvey: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Scheme picker
            Menu {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Button {
                        colorScheme = scheme
                    } label: {
                        HStack {
                            Text(scheme.displayName)
                            if scheme == colorScheme { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(colorScheme.displayName, systemImage: "thermometer.medium")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.accent.opacity(0.15))
                    .foregroundStyle(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("heatmap_menu_scheme")

            Divider().frame(height: 20).opacity(0.3)

            // Overlay toggles
            overlayToggle("Dots", icon: "circle.fill", overlay: .dots)
            overlayToggle("Contour", icon: "waveform", overlay: .contour)
            overlayToggle("Zones", icon: "exclamationmark.triangle.fill", overlay: .deadZones)

            Spacer()

            if isSurveying {
                Button {
                    onStopSurvey?()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.Colors.error.opacity(0.15))
                        .foregroundStyle(Theme.Colors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("heatmap_button_strip_stop")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func overlayToggle(_ label: String, icon: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = overlays.contains(overlay)
        return Button {
            if active { overlays.remove(overlay) } else { overlays.insert(overlay) }
        } label: {
            Label(label, systemImage: icon)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(active ? Theme.Colors.accent.opacity(0.18) : Color.white.opacity(0.06))
                .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityIdentifier("heatmap_toggle_\(label.lowercased())")
    }
}
```

- [ ] **Step 5.2: Create `NetMonitor-iOS/Views/Tools/MeasurementsPanel.swift`**

```swift
import SwiftUI
import NetMonitorCore

// MARK: - MeasurementsPanel

/// Shows live stats during survey and full stats after completion.
struct MeasurementsPanel: View {
    let points: [HeatmapDataPoint]
    let isSurveying: Bool
    let calibration: CalibrationScale?
    @Binding var preferredUnit: DistanceUnit

    private var stats: HeatmapRenderer.SurveyStats {
        HeatmapRenderer.computeStats(points: points, calibration: calibration, unit: preferredUnit)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text(isSurveying ? "Live Stats" : "Measurements")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if calibration != nil {
                        Picker("", selection: $preferredUnit) {
                            ForEach(DistanceUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        .accessibilityIdentifier("measurements_picker_unit")
                    }
                }

                if points.isEmpty {
                    Text("Tap the canvas to record signal at each location")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        statCell(value: "\(stats.count)", label: "Points")
                        statCell(value: stats.averageDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Average", color: colorFor(stats.averageDBm))
                        statCell(value: stats.strongestDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Strongest", color: Theme.Colors.success)
                        statCell(value: stats.weakestDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Weakest", color: Theme.Colors.error)
                        statCell(value: stats.strongCoveragePercent.map { "\($0)%" } ?? "--",
                                 label: "Strong coverage")
                        if calibration == nil {
                            statCell(value: "—", label: "Calibrate for scale", color: Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_section_measurements")
    }

    private func statCell(value: String, label: String, color: Color = Theme.Colors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colorFor(_ rssi: Int?) -> Color {
        guard let r = rssi else { return Theme.Colors.textPrimary }
        switch SignalLevel.from(rssi: r) {
        case .strong: return Theme.Colors.success
        case .fair:   return Theme.Colors.warning
        case .weak:   return Theme.Colors.error
        }
    }
}
```

- [ ] **Step 5.3: Build iOS**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5.4: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/HeatmapControlStrip.swift \
        NetMonitor-iOS/Views/Tools/MeasurementsPanel.swift
git commit -m "feat(ios): add HeatmapControlStrip and MeasurementsPanel"
```

---

### Task 6: HeatmapFullScreenView — full-screen cover

**Files:**
- Create: `NetMonitor-iOS/Views/Tools/HeatmapFullScreenView.swift`

- [ ] **Step 6.1: Create `NetMonitor-iOS/Views/Tools/HeatmapFullScreenView.swift`**

```swift
import SwiftUI
import NetMonitorCore

// MARK: - HeatmapFullScreenView

/// Full-screen heatmap presented via `.fullScreenCover`.
/// In portrait: controls float at bottom. In landscape: controls move to leading sidebar.
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

    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape {
                    HStack(spacing: 0) {
                        sidebarControls
                            .frame(width: 160)
                        canvas
                    }
                } else {
                    VStack(spacing: 0) {
                        canvas
                        bottomControls
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    // MARK: - Canvas

    private var canvas: some View {
        HeatmapCanvasView(
            points: points,
            floorplanImage: floorplanImage,
            colorScheme: colorScheme,
            overlays: overlays,
            calibration: calibration,
            isSurveying: isSurveying,
            onTap: onTap
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .accessibilityIdentifier("heatmap_fullscreen_button_close")
        }
    }

    // MARK: - Bottom controls (portrait)

    private var bottomControls: some View {
        HeatmapControlStrip(
            colorScheme: $colorScheme,
            overlays: $overlays,
            isSurveying: isSurveying,
            onStopSurvey: onStopSurvey
        )
        .background(.ultraThinMaterial)
    }

    // MARK: - Sidebar controls (landscape)

    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WiFi Heatmap")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.top, 20)

            Divider().opacity(0.2)

            // Scheme picker
            VStack(alignment: .leading, spacing: 6) {
                Text("SCHEME")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Button {
                        colorScheme = scheme
                    } label: {
                        HStack {
                            Text(scheme.displayName)
                                .font(.caption)
                                .foregroundStyle(colorScheme == scheme ? Theme.Colors.accent : .white.opacity(0.7))
                            Spacer()
                            if colorScheme == scheme {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider().opacity(0.2)

            // Overlay toggles
            VStack(alignment: .leading, spacing: 6) {
                Text("OVERLAYS")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                overlayRow("Dots", overlay: .dots)
                overlayRow("Contour", overlay: .contour)
                overlayRow("Dead Zones", overlay: .deadZones)
            }

            Spacer()

            if isSurveying {
                Button {
                    onStopSurvey?()
                } label: {
                    Label("Stop Survey", systemImage: "stop.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.error.opacity(0.2))
                        .foregroundStyle(Theme.Colors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.bottom, 16)
                .accessibilityIdentifier("heatmap_fullscreen_button_stop")
            }
        }
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
    }

    private func overlayRow(_ label: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = overlays.contains(overlay)
        return Button {
            if active { overlays.remove(overlay) } else { overlays.insert(overlay) }
        } label: {
            HStack {
                Image(systemName: active ? "checkmark.square.fill" : "square")
                    .foregroundStyle(active ? Theme.Colors.accent : .white.opacity(0.4))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 2)
        }
    }
}
```

- [ ] **Step 6.2: Build iOS**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 6.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/HeatmapFullScreenView.swift
git commit -m "feat(ios): add HeatmapFullScreenView with landscape sidebar support"
```

---

## Chunk 3: iOS Wiring

### Task 7: Update ViewModel and AppSettings

**Files:**
- Modify: `NetMonitor-iOS/Platform/AppSettings.swift`
- Modify: `NetMonitor-iOS/ViewModels/WiFiHeatmapSurveyViewModel.swift`
- Modify: `Tests/NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests.swift`

- [ ] **Step 7.1: Add keys to AppSettings**

Open `NetMonitor-iOS/Platform/AppSettings.swift`. In the `Keys` enum, add a new section:

```swift
// MARK: Heatmap
static let heatmapColorScheme   = "heatmapColorScheme"
static let heatmapDisplayOverlays = "heatmapDisplayOverlays"
static let heatmapPreferredUnit = "heatmapPreferredUnit"
```

- [ ] **Step 7.2: Write failing ViewModel tests**

Open `Tests/NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests.swift` and append:

```swift
// MARK: - Calibration tests

@Test("setCalibration stores scale on viewModel")
@MainActor
func setCalibrationStores() async {
    let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
    vm.setCalibration(pixelDist: 100, realDist: 10, unit: .feet)
    #expect(vm.calibration?.pixelsPerUnit == 10.0)
    #expect(vm.calibration?.unit == .feet)
}

@Test("clearCalibration removes scale")
@MainActor
func clearCalibration() async {
    let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
    vm.setCalibration(pixelDist: 100, realDist: 10, unit: .feet)
    vm.clearCalibration()
    #expect(vm.calibration == nil)
}

@Test("default colorScheme is thermal")
@MainActor
func defaultColorScheme() async {
    let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
    #expect(vm.colorScheme == .thermal)
}

@Test("default preferredUnit is feet")
@MainActor
func defaultUnit() async {
    let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
    #expect(vm.preferredUnit == .feet)
}
```

- [ ] **Step 7.3: Run tests — expect failures**

```bash
xcodebuild test -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests 2>&1 | grep -E "error:|failed|passed"
```

Expected: compile errors on missing `setCalibration`, `clearCalibration`, `calibration`, `colorScheme`, `preferredUnit`.

- [ ] **Step 7.4: Update WiFiHeatmapSurveyViewModel**

Open `NetMonitor-iOS/ViewModels/WiFiHeatmapSurveyViewModel.swift`.

Add new published state (below the existing private vars):

```swift
// MARK: - Heatmap display settings
private(set) var calibration: CalibrationScale?
var colorScheme: HeatmapColorScheme = .thermal {
    didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: AppSettings.Keys.heatmapColorScheme) }
}
var displayOverlays: HeatmapDisplayOverlay = .gradient {
    didSet { UserDefaults.standard.set(displayOverlays.rawValue, forKey: AppSettings.Keys.heatmapDisplayOverlays) }
}
var preferredUnit: DistanceUnit = .feet {
    didSet { UserDefaults.standard.set(preferredUnit.rawValue, forKey: AppSettings.Keys.heatmapPreferredUnit) }
}

// MARK: - Calibration state
var isCalibrating = false
```

Add new methods (before `// MARK: - Signal reading`):

```swift
// MARK: - Calibration

func setCalibration(pixelDist: Double, realDist: Double, unit: DistanceUnit) {
    calibration = CalibrationScale(pixelDistance: pixelDist, realDistance: realDist, unit: unit)
    isCalibrating = false
}

func clearCalibration() {
    calibration = nil
}
```

Update `init` to load persisted settings:

```swift
// In init, after loadSurveys():
if let raw = UserDefaults.standard.string(forKey: AppSettings.Keys.heatmapColorScheme),
   let scheme = HeatmapColorScheme(rawValue: raw) {
    colorScheme = scheme
}
if let rawUnit = UserDefaults.standard.string(forKey: AppSettings.Keys.heatmapPreferredUnit),
   let unit = DistanceUnit(rawValue: rawUnit) {
    preferredUnit = unit
}
let overlayRaw = UserDefaults.standard.integer(forKey: AppSettings.Keys.heatmapDisplayOverlays)
if overlayRaw != 0 {
    displayOverlays = HeatmapDisplayOverlay(rawValue: overlayRaw)
}
```

Update `stopSurvey()` to include calibration when saving the `HeatmapSurvey`:

```swift
// Replace the survey creation line in stopSurvey():
let survey = HeatmapSurvey(
    name: "Survey \(surveys.count + 1)",
    mode: selectedMode,
    dataPoints: dataPoints,
    calibration: calibration
)
```

- [ ] **Step 7.5: Run tests — expect all to pass**

```bash
xcodebuild test -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests 2>&1 | grep -E "passed|failed"
```

Expected: All tests pass.

- [ ] **Step 7.6: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Platform/AppSettings.swift \
        NetMonitor-iOS/ViewModels/WiFiHeatmapSurveyViewModel.swift \
        Tests/NetMonitor-iOSTests/WiFiHeatmapSurveyViewModelTests.swift
git commit -m "feat(ios): wire calibration, colorScheme, overlays, and unit preferences into ViewModel"
```

---

### Task 8: Wire WiFiHeatmapSurveyView

**Files:**
- Modify: `NetMonitor-iOS/Views/Tools/WiFiHeatmapSurveyView.swift`

Replace the existing view implementation with one that uses all the new subviews.

- [ ] **Step 8.1: Rewrite WiFiHeatmapSurveyView**

Replace the entire content of `NetMonitor-iOS/Views/Tools/WiFiHeatmapSurveyView.swift`:

```swift
import SwiftUI
import PhotosUI
import NetMonitorCore

// MARK: - WiFiHeatmapSurveyView

struct WiFiHeatmapSurveyView: View {
    @State private var viewModel = WiFiHeatmapSurveyViewModel()
    @State private var showingGuide = false
    @State private var showingFullScreen = false
    @State private var showingCalibration = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                statusBarSection
                heatmapCanvasSection
                HeatmapControlStrip(
                    colorScheme: $viewModel.colorScheme,
                    overlays: $viewModel.displayOverlays,
                    isSurveying: viewModel.isSurveying,
                    onStopSurvey: { viewModel.stopSurvey() }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
                actionButtonsSection
                MeasurementsPanel(
                    points: viewModel.dataPoints,
                    isSurveying: viewModel.isSurveying,
                    calibration: viewModel.calibration,
                    preferredUnit: $viewModel.preferredUnit
                )
                if !viewModel.surveys.isEmpty {
                    previousSurveysSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("WiFi Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingGuide = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("heatmap_button_info")
            }
        }
        .sheet(isPresented: $showingGuide) { guideSheet }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                onComplete: { scale in
                    if let scale {
                        viewModel.setCalibration(pixelDist: scale.pixelDistance,
                                                 realDist: scale.realDistance,
                                                 unit: scale.unit)
                    }
                    showingCalibration = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            HeatmapFullScreenView(
                points: $viewModel.dataPoints,
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                colorScheme: $viewModel.colorScheme,
                overlays: $viewModel.displayOverlays,
                calibration: viewModel.calibration,
                isSurveying: viewModel.isSurveying,
                onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) },
                onStopSurvey: { viewModel.stopSurvey() },
                onDismiss: { showingFullScreen = false }
            )
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.floorplanImageData = data
                    viewModel.selectedMode = .floorplan
                    showingCalibration = true
                }
            }
        }
        .accessibilityIdentifier("screen_wifiHeatmapTool")
    }

    // MARK: - Status Bar

    private var statusBarSection: some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: "wifi.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.isSurveying ? viewModel.signalColor : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isSurveying ? "Recording" : "Ready")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if viewModel.calibration != nil {
                    Label("Calibrated", systemImage: "ruler")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }

                if viewModel.isSurveying {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.signalText)
                            .font(.headline).fontWeight(.bold)
                            .foregroundStyle(viewModel.signalColor)
                            .monospacedDigit()
                        Text(viewModel.signalLevel.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_status_bar")
    }

    // MARK: - Canvas

    private var heatmapCanvasSection: some View {
        ZStack {
            HeatmapCanvasView(
                points: viewModel.dataPoints,
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                colorScheme: viewModel.colorScheme,
                overlays: viewModel.displayOverlays,
                calibration: viewModel.calibration,
                isSurveying: viewModel.isSurveying,
                onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) }
            )
            .frame(height: 280)

            // Full-screen button
            Button {
                showingFullScreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(10)
            .accessibilityIdentifier("heatmap_button_fullscreen")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Button {
                if viewModel.isSurveying { viewModel.stopSurvey() }
                else { viewModel.startSurvey() }
            } label: {
                HStack {
                    Image(systemName: viewModel.isSurveying ? "record.circle" : "play.circle.fill")
                    Text(viewModel.isSurveying ? "Recording…" : "Start Survey")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.isSurveying ? Theme.Colors.warning : Theme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("heatmap_button_main_action")

            HStack(spacing: Theme.Layout.itemSpacing) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Floor Plan")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("heatmap_button_select_floorplan")

                Button {
                    showingCalibration = true
                } label: {
                    HStack {
                        Image(systemName: "ruler")
                        Text("Calibrate")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.calibration != nil
                                ? Theme.Colors.accent.opacity(0.12)
                                : Color.clear.opacity(0))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(viewModel.calibration != nil ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .stroke(viewModel.calibration != nil ? Theme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
                .accessibilityIdentifier("heatmap_button_calibrate")
            }
        }
    }

    // MARK: - Previous Surveys

    private var previousSurveysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Saved Surveys")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(viewModel.surveys) { survey in
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(survey.name)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                if survey.calibration != nil {
                                    Label("", systemImage: "ruler")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            Text("\(survey.dataPoints.count) points • \(survey.mode.displayName)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(survey.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Button { viewModel.deleteSurvey(survey) } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.Colors.error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Guide Sheet (unchanged content, kept for brevity)

    private var guideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                    guideSection(icon: "ruler", title: "Calibration",
                        body: "After importing a floor plan, draw a line between two known points and enter the real distance. This unlocks real-world measurements.")
                    guideSection(icon: "hand.tap", title: "Survey",
                        body: "Start a survey, walk to each location, and tap the canvas to record the WiFi signal at that spot.")
                    guideSection(icon: "thermometer.medium", title: "Color Schemes",
                        body: "Thermal (default): blue → red by signal strength. Signal: red → green. Nebula and Arctic for stylised views.")
                    guideSection(icon: "exclamationmark.triangle", title: "Permissions",
                        body: "Live signal readings require the Wi-Fi Info entitlement. Without it, the app uses simulated values for demonstration.")
                }
                .padding(Theme.Layout.screenPadding)
            }
            .themedBackground()
            .navigationTitle("Heatmap Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingGuide = false }
                        .fontWeight(.semibold).foregroundStyle(Theme.Colors.accent)
                        .accessibilityIdentifier("heatmap_button_guide_done")
                }
            }
        }
        .accessibilityIdentifier("screen_wifiHeatmapGuide")
    }

    private func guideSection(icon: String, title: String, body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: Theme.Layout.itemSpacing) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.Colors.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.Colors.textPrimary)
                    Text(body).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack { WiFiHeatmapSurveyView() }
}
```

- [ ] **Step 8.2: Build iOS — fix any remaining errors**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

If `Theme.Colors.success` or `Theme.Colors.warning` don't exist, substitute `Color.green` / `Color.orange` and note it for a follow-up.

- [ ] **Step 8.3: Run all iOS tests**

```bash
xcodebuild test -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test session|passed|failed"
```

Expected: All existing tests pass; no regressions.

- [ ] **Step 8.4: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/WiFiHeatmapSurveyView.swift
git commit -m "feat(ios): wire all heatmap subviews into WiFiHeatmapSurveyView"
```

---

## Chunk 4: macOS

### Task 9: macOS WiFiHeatmapService — CoreWLAN signal reading

**Files:**
- Create: `NetMonitor-macOS/Platform/WiFiHeatmapService.swift`

- [ ] **Step 9.1: Create `NetMonitor-macOS/Platform/WiFiHeatmapService.swift`**

```swift
import Foundation
import CoreWLAN
import NetMonitorCore

// MARK: - WiFiHeatmapService (macOS)

/// macOS implementation of WiFiHeatmapServiceProtocol.
/// Reads RSSI from the primary Wi-Fi interface via CoreWLAN.
/// Falls back to simulated values when no interface is available
/// (e.g., in tests or when Wi-Fi is off).
final class WiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {

    private var dataPoints: [HeatmapDataPoint] = []
    private var isRunning = false

    func startSurvey() {
        isRunning = true
        dataPoints = []
    }

    func stopSurvey() {
        isRunning = false
    }

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        let pt = HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength, timestamp: Date())
        dataPoints.append(pt)
    }

    func getSurveyData() -> [HeatmapDataPoint] { dataPoints }

    // MARK: - Signal Reading

    /// Read the current RSSI from the primary Wi-Fi interface.
    /// Returns nil if Wi-Fi is unavailable.
    func currentRSSI() -> Int? {
        guard let iface = CWWiFiClient.shared().interface(),
              iface.serviceActive() else { return nil }
        return iface.rssiValue()
    }

    func simulatedRSSI() -> Int {
        Int.random(in: (-80)...(-45))
    }
}
```

- [ ] **Step 9.2: Run `xcodegen generate` and build macOS**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 9.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Platform/WiFiHeatmapService.swift
git commit -m "feat(macos): add WiFiHeatmapService with CoreWLAN RSSI reading"
```

---

### Task 10: macOS WiFiHeatmapToolView — three-column layout

**Files:**
- Create: `NetMonitor-macOS/Views/Tools/WiFiHeatmapToolView.swift`
- Create: `NetMonitor-macOS/ViewModels/WiFiHeatmapToolViewModel.swift`

The macOS view uses `NavigationSplitView` with a left survey list, center canvas, and right stats panel. It mirrors the iOS ViewModel logic but uses CoreWLAN instead of NetworkExtension.

- [ ] **Step 10.1: Create `NetMonitor-macOS/ViewModels/WiFiHeatmapToolViewModel.swift`**

Check if a `ViewModels` directory exists for macOS:
```bash
ls /Users/blake/Projects/NetMonitor-2.0/NetMonitor-macOS/
```

If no `ViewModels` folder: place the file directly in `NetMonitor-macOS/` alongside the Platform folder.

```swift
import Foundation
import SwiftUI
import NetMonitorCore

// MARK: - WiFiHeatmapToolViewModel (macOS)

@MainActor
@Observable
final class WiFiHeatmapToolViewModel {

    // MARK: - Survey state

    private(set) var isSurveying = false
    private(set) var currentRSSI: Int = 0
    private(set) var dataPoints: [HeatmapDataPoint] = []
    private(set) var surveys: [HeatmapSurvey] = []
    private(set) var selectedSurveyID: UUID? = nil
    private(set) var statusMessage = "Click 'Start Survey' to begin"

    var colorScheme: HeatmapColorScheme = .thermal
    var displayOverlays: HeatmapDisplayOverlay = .gradient
    var preferredUnit: DistanceUnit = .feet
    var calibration: CalibrationScale? = nil
    var floorplanImage: NSImage? = nil
    var hoverPoint: CGPoint? = nil   // canvas coordinate for tooltip
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero

    // MARK: - Private

    private let service = WiFiHeatmapService()
    private var signalRefreshTask: Task<Void, Never>?
    private static let surveysKey = "wifiHeatmap_surveys_mac"

    init() { loadSurveys() }

    // MARK: - Survey control

    func startSurvey() {
        guard !isSurveying else { return }
        isSurveying = true
        dataPoints = []
        service.startSurvey()
        statusMessage = "Click the canvas to record signal at each location"

        signalRefreshTask = Task {
            while !Task.isCancelled {
                currentRSSI = service.currentRSSI() ?? service.simulatedRSSI()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSurvey() {
        guard isSurveying else { return }
        isSurveying = false
        signalRefreshTask?.cancel()
        service.stopSurvey()
        dataPoints = service.getSurveyData()

        if !dataPoints.isEmpty {
            let survey = HeatmapSurvey(
                name: "Survey \(surveys.count + 1)",
                mode: floorplanImage != nil ? .floorplan : .freeform,
                dataPoints: dataPoints,
                calibration: calibration
            )
            surveys.insert(survey, at: 0)
            selectedSurveyID = survey.id
            saveSurveys()
        }
        statusMessage = dataPoints.isEmpty
            ? "No data recorded. Start another survey."
            : "Survey complete — \(dataPoints.count) measurements"
    }

    func recordDataPoint(at point: CGPoint, in size: CGSize) {
        guard isSurveying, size.width > 0, size.height > 0 else { return }
        let nx = point.x / size.width
        let ny = point.y / size.height
        let rssi = currentRSSI != 0 ? currentRSSI : service.simulatedRSSI()
        service.recordDataPoint(signalStrength: rssi, x: nx, y: ny)
        dataPoints = service.getSurveyData()
        statusMessage = "\(rssi) dBm recorded at (\(String(format: "%.2f", nx)), \(String(format: "%.2f", ny)))"
    }

    func selectSurvey(_ survey: HeatmapSurvey) {
        selectedSurveyID = survey.id
        dataPoints = survey.dataPoints
        calibration = survey.calibration
    }

    func deleteSurvey(_ survey: HeatmapSurvey) {
        surveys.removeAll { $0.id == survey.id }
        if selectedSurveyID == survey.id { selectedSurveyID = surveys.first?.id }
        saveSurveys()
    }

    func setCalibration(pixelDist: Double, realDist: Double, unit: DistanceUnit) {
        calibration = CalibrationScale(pixelDistance: pixelDist, realDistance: realDist, unit: unit)
    }

    func clearCalibration() { calibration = nil }

    // MARK: - Computed

    var stats: HeatmapRenderer.SurveyStats {
        HeatmapRenderer.computeStats(points: dataPoints, calibration: calibration, unit: preferredUnit)
    }

    var signalColor: Color {
        switch SignalLevel.from(rssi: currentRSSI) {
        case .strong: return .green
        case .fair:   return .yellow
        case .weak:   return .red
        }
    }

    // MARK: - Export

    func exportPNG(from view: NSView) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "heatmap.png"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            guard let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    // MARK: - Persistence

    private func loadSurveys() {
        guard let data = UserDefaults.standard.data(forKey: Self.surveysKey),
              let loaded = try? JSONDecoder().decode([HeatmapSurvey].self, from: data)
        else { return }
        surveys = loaded
        selectedSurveyID = surveys.first?.id
        if let first = surveys.first { dataPoints = first.dataPoints; calibration = first.calibration }
    }

    private func saveSurveys() {
        guard let data = try? JSONEncoder().encode(surveys) else { return }
        UserDefaults.standard.set(data, forKey: Self.surveysKey)
    }
}
```

- [ ] **Step 10.2: Create `NetMonitor-macOS/Views/Tools/WiFiHeatmapToolView.swift`**

```swift
import SwiftUI
import AppKit
import NetMonitorCore

// MARK: - WiFiHeatmapToolView (macOS)

struct WiFiHeatmapToolView: View {
    @State private var vm = WiFiHeatmapToolViewModel()
    @State private var showingCalibration = false
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationSplitView {
            surveyListSidebar
        } content: {
            VStack(spacing: 0) {
                macToolbar
                macCanvas
            }
            .navigationTitle("")
        } detail: {
            statsSidebar
        }
        .sheet(isPresented: $showingCalibration) {
            macCalibrationSheet
        }
        .frame(minWidth: 900, minHeight: 550)
    }

    // MARK: - Left Sidebar: Survey List

    private var surveyListSidebar: some View {
        List {
            Section("Surveys") {
                ForEach(vm.surveys) { survey in
                    surveyRow(survey)
                }
                .onDelete { indices in
                    indices.forEach { vm.deleteSurvey(vm.surveys[$0]) }
                }
            }

            Section("Tools") {
                Button {
                    showingCalibration = true
                } label: {
                    Label("Calibrate Scale", systemImage: "ruler")
                }
                .buttonStyle(.plain)
                .foregroundColor(vm.calibration != nil ? .accentColor : .primary)

                Button {
                    if vm.isSurveying { vm.stopSurvey() } else { vm.startSurvey() }
                } label: {
                    Label(vm.isSurveying ? "Stop Survey" : "New Survey",
                          systemImage: vm.isSurveying ? "stop.circle.fill" : "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(vm.isSurveying ? .red : .primary)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private func surveyRow(_ survey: HeatmapSurvey) -> some View {
        Button {
            vm.selectSurvey(survey)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(survey.name)
                        .fontWeight(vm.selectedSurveyID == survey.id ? .semibold : .regular)
                    if survey.calibration != nil {
                        Image(systemName: "ruler").font(.caption2).foregroundColor(.accentColor)
                    }
                }
                Text("\(survey.dataPoints.count) pts · \(survey.mode.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .tag(survey.id)
    }

    // MARK: - Toolbar

    private var macToolbar: some View {
        HStack(spacing: 6) {
            // Scheme picker
            Picker("Scheme", selection: $vm.colorScheme) {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            .controlSize(.small)

            Divider().frame(height: 20)

            overlayToggle("Gradient", overlay: .gradient)
            overlayToggle("Dots", overlay: .dots)
            overlayToggle("Contour", overlay: .contour)
            overlayToggle("Zones", overlay: .deadZones)

            Divider().frame(height: 20)

            Button {
                vm.zoomScale = min(vm.zoomScale * 1.25, 5)
            } label: { Image(systemName: "plus.magnifyingglass") }
            .buttonStyle(.plain).controlSize(.small)

            Button {
                vm.zoomScale = max(vm.zoomScale / 1.25, 0.5)
            } label: { Image(systemName: "minus.magnifyingglass") }
            .buttonStyle(.plain).controlSize(.small)

            Button {
                vm.zoomScale = 1; vm.panOffset = .zero
            } label: { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.plain).controlSize(.small)
            .help("Reset zoom & pan")

            Spacer()

            if vm.isSurveying {
                HStack(spacing: 6) {
                    Circle().fill(vm.signalColor).frame(width: 8)
                    Text("\(vm.currentRSSI) dBm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(vm.signalColor)
                }
            }

            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Material.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private func overlayToggle(_ label: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = vm.displayOverlays.contains(overlay)
        return Toggle(label, isOn: Binding(
            get: { active },
            set: { on in
                if on { vm.displayOverlays.insert(overlay) }
                else { vm.displayOverlays.remove(overlay) }
            }
        ))
        .toggleStyle(.button)
        .controlSize(.small)
        .tint(.accentColor)
    }

    // MARK: - Center Canvas

    private var macCanvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                HeatmapCanvasView(
                    points: vm.dataPoints,
                    floorplanImage: vm.floorplanImage.map { nsImg in
                        // Convert NSImage → UIImage for shared HeatmapCanvasView
                        // On macOS, UIImage is not available; use a macOS-specific canvas.
                        // See Note below.
                        nil as UIImage?
                    } ?? nil,
                    colorScheme: vm.colorScheme,
                    overlays: vm.displayOverlays,
                    calibration: vm.calibration,
                    isSurveying: vm.isSurveying,
                    onTap: { loc, size in vm.recordDataPoint(at: loc, in: size) }
                )
                .scaleEffect(vm.zoomScale)
                .offset(vm.panOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in vm.zoomScale = max(0.5, min(5, val)) }
                )
                .gesture(
                    DragGesture()
                        .onChanged { val in vm.panOffset = val.translation }
                )

                // Hover tooltip
                if let hover = vm.hoverPoint, let rssi = interpolatedRSSI(at: hover, in: geo.size) {
                    hoverTooltip(rssi: rssi, pt: hover, canvasSize: geo.size)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): vm.hoverPoint = loc
                case .ended: vm.hoverPoint = nil
                }
            }
            .onAppear { canvasSize = geo.size }
        }
        .background(Color.black)
    }

    // NOTE: HeatmapCanvasView uses UIImage which is iOS-only.
    // On macOS, the floor plan rendering path in HeatmapCanvasView that uses UIImage
    // will receive nil and fall back to the grid background. A future iteration can
    // add #if os(macOS) conditional to support NSImage in HeatmapCanvasView.

    private func interpolatedRSSI(at pt: CGPoint, in size: CGSize) -> Int? {
        guard !vm.dataPoints.isEmpty else { return nil }
        // Use the nearest point's RSSI as a quick approximation for hover display
        let closest = vm.dataPoints.min {
            let dx0 = $0.x * size.width - pt.x, dy0 = $0.y * size.height - pt.y
            let dx1 = $1.x * size.width - pt.x, dy1 = $1.y * size.height - pt.y
            return dx0*dx0+dy0*dy0 < dx1*dx1+dy1*dy1
        }
        return closest?.signalStrength
    }

    private func hoverTooltip(rssi: Int, pt: CGPoint, canvasSize: CGSize) -> some View {
        let level = SignalLevel.from(rssi: rssi)
        var coord = ""
        if let cal = vm.calibration {
            let rx = cal.realDistance(pixels: pt.x)
            let ry = cal.realDistance(pixels: pt.y)
            coord = String(format: " · (%.1f %@, %.1f %@)", rx, cal.unit.displayName, ry, cal.unit.displayName)
        }
        return Text("\(rssi) dBm · \(level.label)\(coord)")
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
            .position(x: min(pt.x + 80, canvasSize.width - 80), y: max(pt.y - 20, 20))
            .allowsHitTesting(false)
    }

    // MARK: - Right Sidebar: Stats

    private var statsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signal Stats")
                    .font(.headline)
                    .padding(.top, 4)

                statBlock(value: vm.stats.averageDBm.map { "\($0) dBm" } ?? "--",
                          label: "Average", color: .primary)
                statBlock(value: vm.stats.weakestDBm.map { "\($0) dBm" } ?? "--",
                          label: "Minimum (worst)", color: .red)
                statBlock(value: vm.stats.strongestDBm.map { "\($0) dBm" } ?? "--",
                          label: "Maximum (best)", color: .green)

                Divider()
                Text("Coverage").font(.headline)

                statBlock(value: vm.stats.strongCoveragePercent.map { "\($0)%" } ?? "--",
                          label: "Strong (≥ −50 dBm)")

                Divider()
                Text("Scale").font(.headline)

                if let cal = vm.calibration {
                    statBlock(value: String(format: "1px = %.1f\(cal.unit.displayName)", 1 / cal.pixelsPerUnit),
                              label: "Calibrated", color: .accentColor)
                    Button("Clear Calibration") { vm.clearCalibration() }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Button("Calibrate Scale…") { showingCalibration = true }
                        .buttonStyle(.link)
                }

                Divider()

                Button {
                    // Export: placeholder — real implementation needs NSView reference
                    // which requires a representable bridge; use toolbar shortcut for now
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    private func statBlock(value: String, label: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Calibration Sheet (macOS)

    private var macCalibrationSheet: some View {
        // The iOS CalibrationView uses UIImage — on macOS we show a simpler sheet.
        // UIImage is not available on macOS, so we present a text-only calibration entry.
        VStack(spacing: 20) {
            Text("Calibrate Scale")
                .font(.title2).fontWeight(.bold)

            Text("Enter the scale manually. If 100 pixels on screen = 10 feet in reality:")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Pixels").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. 100", value: $macCalibPx, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                Text("=").foregroundColor(.secondary)
                VStack(alignment: .leading) {
                    Text("Real distance").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. 10", value: $macCalibReal, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                VStack(alignment: .leading) {
                    Text("Unit").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $macCalibUnit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 70)
                }
            }

            HStack {
                Button("Skip") { showingCalibration = false }
                    .keyboardShortcut(.escape)
                Button("Set Scale") {
                    if macCalibPx > 0 && macCalibReal > 0 {
                        vm.setCalibration(pixelDist: macCalibPx, realDist: macCalibReal, unit: macCalibUnit)
                    }
                    showingCalibration = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(macCalibPx <= 0 || macCalibReal <= 0)
            }
        }
        .padding(30)
        .frame(width: 500)
    }

    @State private var macCalibPx: Double = 0
    @State private var macCalibReal: Double = 0
    @State private var macCalibUnit: DistanceUnit = .feet
}
```

- [ ] **Step 10.3: Register the tool in the macOS tool routing**

Find where macOS tools are listed. Check the macOS tool panel (likely a sidebar or tab-bar listing `ToolType` cases):

```bash
grep -rn "WiFiHeatmap\|HeatmapTool\|ToolType\|\.heatmap" \
  /Users/blake/Projects/NetMonitor-2.0/NetMonitor-macOS/ 2>/dev/null | head -20
```

Add `WiFiHeatmapToolView` to the macOS tool routing wherever other tool views are registered (e.g., a `switch ToolType` statement or a `@ViewBuilder` function). Follow the pattern used by `SpeedTestToolView` or `PingToolView` in that file.

- [ ] **Step 10.4: Build macOS**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Fix any compile errors, particularly around:
- `UIImage` used in `HeatmapCanvasView` — add `#if os(iOS)` guards if needed to keep the macOS build clean, passing `nil` for the image on macOS
- `Theme.Colors.*` constants — macOS uses system colors; use `Color.accentColor`, `Color.red`, `Color.green` as substitutes where `Theme` is iOS-only

- [ ] **Step 10.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Platform/WiFiHeatmapService.swift \
        NetMonitor-macOS/Views/Tools/WiFiHeatmapToolView.swift
# Add ViewModel if in its own file
git add NetMonitor-macOS/WiFiHeatmapToolViewModel.swift 2>/dev/null || true
git commit -m "feat(macos): add WiFiHeatmapToolView with three-column layout, CoreWLAN RSSI, and stats sidebar"
```

---

## Chunk 5: Final Polish + Cross-Platform Guard

### Task 11: HeatmapCanvasView platform guard + final build verification

**Files:**
- Modify: `NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift`

- [ ] **Step 11.1: Add `#if os(iOS)` guard around UIImage usage in HeatmapCanvasView**

In `HeatmapCanvasView.swift`, find the `backgroundLayer` function and wrap the UIImage section:

```swift
@ViewBuilder
private func backgroundLayer(in size: CGSize) -> some View {
    #if os(iOS)
    if let img = floorplanImage {
        Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .opacity(0.55)
    } else {
        gridBackground
    }
    #else
    gridBackground
    #endif
}
```

Also guard the `floorplanImage` property type:

```swift
#if os(iOS)
let floorplanImage: UIImage?
#else
let floorplanImage: Void? = nil   // macOS passes nil; floor plan via NSImage handled in WiFiHeatmapToolView
#endif
```

- [ ] **Step 11.2: Build both targets clean**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Both must show `Build succeeded`.

- [ ] **Step 11.3: Run full test suite**

```bash
xcodebuild test -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test session|passed|failed"
swift test --package-path Packages/NetMonitorCore 2>&1 | grep -E "Test run|passed|failed"
```

Expected: All tests pass.

- [ ] **Step 11.4: Final commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add -A
git commit -m "feat: complete WiFi Heatmap redesign — thermal gradient, calibration, full-screen, macOS"
git push
```

---

## Summary

| Chunk | Tasks | Deliverable |
|---|---|---|
| 1 | 1–2 | Data models + HeatmapRenderer with full test coverage |
| 2 | 3–6 | iOS canvas, calibration, controls, full-screen |
| 3 | 7–8 | iOS ViewModel + View wiring (fully functional iOS feature) |
| 4 | 9–10 | macOS service + three-column tool view |
| 5 | 11 | Platform guards, clean dual-target build |

**Key constraints to remember:**
- Swift 6 strict concurrency — all service types must be `Sendable`; ViewModels are `@MainActor`
- `HeatmapCanvasView` uses `UIImage` — guard with `#if os(iOS)` for macOS compatibility
- `Theme.Colors.*` is iOS-only — macOS view uses native system colors
- Run `xcodegen generate` whenever a new `.swift` file is added to a target directory
- Tests use Swift Testing framework (`@Suite`, `@Test`, `#expect`) — not XCTest
