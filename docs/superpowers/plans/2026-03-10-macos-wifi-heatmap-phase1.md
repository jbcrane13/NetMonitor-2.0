# macOS WiFi Heatmap Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a professional-grade WiFi heatmap tool for macOS with canvas-focused layout, CoreWLAN integration, 8 visualization overlays, nearby AP scanning, project persistence, and PNG/PDF export.

**Architecture:** New view hierarchy (`WiFiHeatmapView` → `HeatmapSidebarView` + `HeatmapCanvasView`) replaces old `HeatmapSurveyView`. A new `WiFiHeatmapService` wraps CoreWLAN for live signal data and nearby AP scanning. Enhanced `HeatmapRenderer` supports 3 color schemes (thermal/stoplight/plasma) and coverage threshold rendering. All state flows through `WiFiHeatmapViewModel`.

**Tech Stack:** SwiftUI + AppKit (NSViewRepresentable canvas), CoreWLAN, Swift 6 strict concurrency, `@Observable` pattern, XcodeGen.

**Design spec:** `docs/superpowers/specs/2026-03-10-macos-wifi-heatmap-phase1-design.md`

**Critical files to read before starting any task:**
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/HeatmapModels.swift` — all shared model types
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift` — IDW renderer
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/WiFiMeasurementEngine.swift` — measurement actor
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/ProjectSaveLoadManager.swift` — .netmonsurvey bundle format
- `NetMonitor-macOS/Platform/CoreWLANService.swift` — existing CoreWLAN wrapper
- `NetMonitor-macOS/Platform/MacWiFiInfoService.swift` — existing WiFi info service
- `NetMonitor-macOS/Views/ContentView.swift:125` — where `HeatmapSurveyView()` is instantiated
- `NetMonitor-macOS/Views/ToolsView.swift` — tool enum with `.wifiHeatmap` case
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/ServiceProtocols.swift:369-382` — `HeatmapServiceProtocol`

**Build command:** `xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build`

**Test command (must run via SSH):**
```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests"
```

---

## Chunk 1: Core — Color Schemes + Renderer Enhancement

### Task 1: Add HeatmapColorScheme enum to HeatmapModels

**Files:**
- Modify: `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/HeatmapModels.swift`

- [ ] **Step 1.1: Add HeatmapColorScheme enum**

Open `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/HeatmapModels.swift` and add before the `// MARK: - SurveyProject` section (line 286):

```swift
// MARK: - HeatmapColorScheme

public enum HeatmapColorScheme: String, Sendable, Codable, CaseIterable {
    case thermal
    case stoplight
    case plasma

    public var displayName: String {
        switch self {
        case .thermal: "Thermal"
        case .stoplight: "Stoplight"
        case .plasma: "Plasma"
        }
    }
}
```

- [ ] **Step 1.2: Build the package to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0/Packages/NetMonitorCore && swift build -c debug
```

Expected: Build succeeds.

- [ ] **Step 1.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/HeatmapModels.swift
git commit -m "feat(core): add HeatmapColorScheme enum with thermal, stoplight, plasma"
```

---

### Task 2: Enhance HeatmapRenderer with 3 gradient schemes + coverage threshold

**Files:**
- Modify: `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift`
- Modify: `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift`

- [ ] **Step 2.1: Write failing tests for color scheme gradients**

Open `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift`. Add these tests (append to the existing test file or create if missing):

```swift
import Testing
@testable import NetMonitorCore

@Suite("HeatmapRenderer Color Schemes")
struct HeatmapRendererColorSchemeTests {

    @Test("thermal gradient: strong signal maps to red region")
    func thermalStrongSignal() {
        let renderer = HeatmapRenderer()
        // Strong signal = -30 dBm, top of range
        let color = renderer.colorForValue(-30, visualization: .signalStrength, colorScheme: .thermal)
        // Should be in the red/warm end: R high
        #expect(color.r > 200)
    }

    @Test("thermal gradient: weak signal maps to blue region")
    func thermalWeakSignal() {
        let renderer = HeatmapRenderer()
        // Weak signal = -90 dBm, bottom of range
        let color = renderer.colorForValue(-90, visualization: .signalStrength, colorScheme: .thermal)
        // Should be in the blue/cool end: B high
        #expect(color.b > 150)
    }

    @Test("stoplight gradient: strong signal maps to green")
    func stoplightStrongSignal() {
        let renderer = HeatmapRenderer()
        let color = renderer.colorForValue(-30, visualization: .signalStrength, colorScheme: .stoplight)
        #expect(color.g > 150)
        #expect(color.r < 100)
    }

    @Test("stoplight gradient: weak signal maps to red")
    func stoplightWeakSignal() {
        let renderer = HeatmapRenderer()
        let color = renderer.colorForValue(-90, visualization: .signalStrength, colorScheme: .stoplight)
        #expect(color.r > 150)
        #expect(color.g < 100)
    }

    @Test("plasma gradient: strong signal maps to yellow")
    func plasmaStrongSignal() {
        let renderer = HeatmapRenderer()
        let color = renderer.colorForValue(-30, visualization: .signalStrength, colorScheme: .plasma)
        // Yellow = high R + high G
        #expect(color.r > 200)
        #expect(color.g > 150)
    }

    @Test("render with colorScheme parameter produces non-nil image")
    func renderWithScheme() {
        let renderer = HeatmapRenderer()
        let points = [
            MeasurementPoint(floorPlanX: 0.3, floorPlanY: 0.3, rssi: -45),
            MeasurementPoint(floorPlanX: 0.7, floorPlanY: 0.7, rssi: -75)
        ]
        let image = renderer.render(points: points, visualization: .signalStrength, colorScheme: .thermal)
        #expect(image != nil)
    }
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0/Packages/NetMonitorCore && swift test --filter HeatmapRendererColorSchemeTests 2>&1 | tail -20"
```

Expected: Compile error — `colorForValue` and `render` don't accept `colorScheme` parameter yet.

- [ ] **Step 2.3: Implement multi-scheme gradients in HeatmapRenderer**

Replace the entire contents of `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift` with:

```swift
import CoreGraphics
import Foundation

// MARK: - HeatmapRenderer

public struct HeatmapRenderer: Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable, Equatable {
        public var powerParameter: Double
        public var gridWidth: Int
        public var gridHeight: Int
        public var opacity: Double

        public init(
            powerParameter: Double = 2.0,
            gridWidth: Int = 200,
            gridHeight: Int = 200,
            opacity: Double = 0.7
        ) {
            self.powerParameter = powerParameter
            self.gridWidth = gridWidth
            self.gridHeight = gridHeight
            self.opacity = opacity
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - IDW Interpolation

    public func interpolateGrid(
        points: [MeasurementPoint],
        visualization: HeatmapVisualization,
        width: Int? = nil,
        height: Int? = nil
    ) -> [[Double]] {
        let gridW = width ?? configuration.gridWidth
        let gridH = height ?? configuration.gridHeight

        let validPoints: [(x: Double, y: Double, value: Double)] = points.compactMap { point in
            guard let value = visualization.extractValue(from: point) else { return nil }
            return (x: point.floorPlanX, y: point.floorPlanY, value: value)
        }

        guard !validPoints.isEmpty else {
            return Array(repeating: Array(repeating: 0, count: gridW), count: gridH)
        }

        let power = configuration.powerParameter
        var grid = Array(repeating: Array(repeating: 0.0, count: gridW), count: gridH)

        for row in 0 ..< gridH {
            let ny = Double(row) / max(Double(gridH - 1), 1)
            for col in 0 ..< gridW {
                let nx = Double(col) / max(Double(gridW - 1), 1)
                grid[row][col] = idwValue(
                    x: nx, y: ny,
                    points: validPoints,
                    power: power
                )
            }
        }

        return grid
    }

    // MARK: - Color Mapping

    public func colorForValue(
        _ value: Double,
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme = .thermal
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let range = visualization.valueRange
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let normalized: Double
        if visualization.isHigherBetter {
            normalized = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        } else {
            normalized = 1.0 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        }
        let alpha = UInt8(configuration.opacity * 255)

        switch colorScheme {
        case .thermal:
            return thermalGradient(t: normalized, alpha: alpha)
        case .stoplight:
            return stoplightGradient(t: normalized, alpha: alpha)
        case .plasma:
            return plasmaGradient(t: normalized, alpha: alpha)
        }
    }

    // MARK: - Rendering

    public func render(
        points: [MeasurementPoint],
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme = .thermal
    ) -> CGImage? {
        let grid = interpolateGrid(points: points, visualization: visualization)
        let gridW = configuration.gridWidth
        let gridH = configuration.gridHeight

        guard gridW > 0, gridH > 0 else { return nil }

        var pixelData = [UInt8](repeating: 0, count: gridW * gridH * 4)

        for row in 0 ..< gridH {
            for col in 0 ..< gridW {
                let value = grid[row][col]
                let color = colorForValue(value, visualization: visualization, colorScheme: colorScheme)
                let offset = (row * gridW + col) * 4
                pixelData[offset] = color.r
                pixelData[offset + 1] = color.g
                pixelData[offset + 2] = color.b
                pixelData[offset + 3] = color.a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: gridW,
            height: gridH,
            bitsPerComponent: 8,
            bytesPerRow: gridW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    // MARK: - Private IDW

    private func idwValue(
        x: Double,
        y: Double,
        points: [(x: Double, y: Double, value: Double)],
        power: Double
    ) -> Double {
        var weightedSum = 0.0
        var totalWeight = 0.0

        for point in points {
            let dx = x - point.x
            let dy = y - point.y
            let distSquared = dx * dx + dy * dy

            if distSquared < 1e-10 {
                return point.value
            }

            let dist = distSquared.squareRoot()
            let weight = 1.0 / pow(dist, power)
            weightedSum += weight * point.value
            totalWeight += weight
        }

        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }

    // MARK: - Gradient Functions

    /// Thermal: Blue → Cyan → Green → Yellow → Red
    /// Standard network heatmap gradient used by NetSpot and similar tools.
    private func thermalGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double

        if c < 0.25 {
            // Blue → Cyan
            let local = c / 0.25
            r = 0
            g = local
            b = 1.0
        } else if c < 0.5 {
            // Cyan → Green
            let local = (c - 0.25) / 0.25
            r = 0
            g = 1.0
            b = 1.0 - local
        } else if c < 0.75 {
            // Green → Yellow
            let local = (c - 0.5) / 0.25
            r = local
            g = 1.0
            b = 0
        } else {
            // Yellow → Red
            let local = (c - 0.75) / 0.25
            r = 1.0
            g = 1.0 - local
            b = 0
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }

    /// Stoplight: Red → Orange → Yellow → Green
    /// Intuitive traffic-light gradient.
    private func stoplightGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double = 0

        if c < 0.33 {
            // Red → Orange
            let local = c / 0.33
            r = 1.0
            g = 0.4 * local
        } else if c < 0.66 {
            // Orange → Yellow
            let local = (c - 0.33) / 0.33
            r = 1.0
            g = 0.4 + 0.6 * local
        } else {
            // Yellow → Green
            let local = (c - 0.66) / 0.34
            r = 1.0 - local
            g = 0.6 + 0.4 * local
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }

    /// Plasma: Indigo → Purple → Red → Orange → Yellow
    /// Scientific color map with high perceptual contrast.
    private func plasmaGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double

        if c < 0.25 {
            // Dark indigo → Purple
            let local = c / 0.25
            r = 0.05 + 0.35 * local
            g = 0.01 + 0.01 * local
            b = 0.2 + 0.3 * local
        } else if c < 0.5 {
            // Purple → Red
            let local = (c - 0.25) / 0.25
            r = 0.4 + 0.55 * local
            g = 0.02 + 0.08 * local
            b = 0.5 - 0.45 * local
        } else if c < 0.75 {
            // Red → Orange
            let local = (c - 0.5) / 0.25
            r = 0.95 + 0.05 * local
            g = 0.1 + 0.4 * local
            b = 0.05 - 0.05 * local
        } else {
            // Orange → Yellow
            let local = (c - 0.75) / 0.25
            r = 1.0
            g = 0.5 + 0.5 * local
            b = local * 0.1
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0/Packages/NetMonitorCore && swift test --filter HeatmapRendererColorSchemeTests 2>&1 | tail -20"
```

Expected: All 6 tests pass.

- [ ] **Step 2.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift
git add Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift
git commit -m "feat(core): add thermal/stoplight/plasma gradient schemes to HeatmapRenderer"
```

---

## Chunk 2: WiFiHeatmapService + ViewModel

### Task 3: Create WiFiHeatmapService with CoreWLAN + nearby AP scanning

**Files:**
- Create: `NetMonitor-macOS/Platform/WiFiHeatmapService.swift`

**Read first:** `NetMonitor-macOS/Platform/CoreWLANService.swift` (existing CoreWLAN wrapper to follow patterns from)

- [ ] **Step 3.1: Create WiFiHeatmapService**

Create `NetMonitor-macOS/Platform/WiFiHeatmapService.swift`:

```swift
import CoreWLAN
import Foundation
import NetMonitorCore

// MARK: - NearbyAP

struct NearbyAP: Identifiable, Sendable {
    let id: String // BSSID
    let ssid: String
    let bssid: String
    let rssi: Int
    let channel: Int
    let band: WiFiBand?
    let noise: Int?
}

// MARK: - WiFiHeatmapService

/// CoreWLAN wrapper providing live signal data and nearby AP scanning for the heatmap tool.
/// All reads are synchronous via CWWiFiClient — safe to call from @MainActor.
@MainActor
final class WiFiHeatmapService {

    private let client = CWWiFiClient.shared()

    private var iface: CWInterface? {
        client.interface()
    }

    // MARK: - Live Signal

    struct SignalSnapshot: Sendable {
        let rssi: Int
        let noiseFloor: Int?
        let snr: Int?
        let ssid: String?
        let bssid: String?
        let channel: Int?
        let band: WiFiBand?
        let linkSpeed: Int?
        let frequency: Double?
    }

    func currentSignal() -> SignalSnapshot? {
        guard let iface, iface.powerOn() else { return nil }

        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()
        let snr = (noise != 0) ? rssi - noise : nil
        let channel = iface.wlanChannel()?.channelNumber
        let band = bandFromChannel(iface.wlanChannel())
        let txRate = iface.transmitRate()
        let linkSpeed = txRate > 0 ? Int(txRate) : nil
        let frequency = channel.map { Self.channelToFrequencyMHz($0) }

        return SignalSnapshot(
            rssi: rssi,
            noiseFloor: noise != 0 ? noise : nil,
            snr: snr,
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            channel: channel,
            band: band,
            linkSpeed: linkSpeed,
            frequency: frequency
        )
    }

    // MARK: - Nearby AP Scan

    func scanForNearbyAPs() -> [NearbyAP] {
        guard let iface else { return [] }
        do {
            let networks = try iface.scanForNetworks(withName: nil)
            return networks.compactMap { network in
                guard let bssid = network.bssid else { return nil }
                return NearbyAP(
                    id: bssid,
                    ssid: network.ssid ?? "(Hidden)",
                    bssid: bssid,
                    rssi: network.rssiValue,
                    channel: network.wlanChannel.channelNumber,
                    band: bandFromChannel(network.wlanChannel),
                    noise: network.noiseMeasurement != 0 ? network.noiseMeasurement : nil
                )
            }
            .sorted { $0.rssi > $1.rssi }
        } catch {
            return []
        }
    }

    // MARK: - Private

    private func bandFromChannel(_ channel: CWChannel?) -> WiFiBand? {
        guard let channel else { return nil }
        switch channel.channelBand {
        case .band2GHz: return .band2_4GHz
        case .band5GHz: return .band5GHz
        case .band6GHz: return .band6GHz
        @unknown default: return nil
        }
    }

    private static func channelToFrequencyMHz(_ channel: Int) -> Double {
        switch channel {
        case 1...13: return Double(2412 + (channel - 1) * 5)
        case 14: return 2484
        case 36...177: return Double(5000 + channel * 5)
        default: return 0
        }
    }
}
```

- [ ] **Step 3.2: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Platform/WiFiHeatmapService.swift
git commit -m "feat(macOS): add WiFiHeatmapService with CoreWLAN signal + nearby AP scanning"
```

---

### Task 4: Create WiFiHeatmapViewModel

**Files:**
- Create: `NetMonitor-macOS/ViewModels/WiFiHeatmapViewModel.swift`

**Read first:**
- `NetMonitor-macOS/ViewModels/HeatmapSurveyViewModel.swift` — existing ViewModel to understand patterns and what to improve
- `NetMonitor-macOS/Platform/WiFiHeatmapService.swift` — just created in Task 3

- [ ] **Step 4.1: Create WiFiHeatmapViewModel**

Create `NetMonitor-macOS/ViewModels/WiFiHeatmapViewModel.swift`:

```swift
import AppKit
import Foundation
import NetMonitorCore
import SwiftUI

// MARK: - WiFiHeatmapViewModel

@MainActor
@Observable
final class WiFiHeatmapViewModel {

    // MARK: - Survey State

    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var isSurveying: Bool = false
    var isMeasuring: Bool = false

    // MARK: - Live Signal

    private(set) var currentSignal: WiFiHeatmapService.SignalSnapshot?
    private(set) var nearbyAPs: [NearbyAP] = []

    // MARK: - Sidebar State

    enum SidebarMode: String, CaseIterable {
        case survey
        case analyze
    }

    var sidebarMode: SidebarMode = .survey
    var isSidebarCollapsed: Bool = false

    // MARK: - Visualization

    var selectedVisualization: HeatmapVisualization = .signalStrength
    var colorScheme: HeatmapColorScheme = .thermal
    var overlayOpacity: Double = 0.7
    var coverageThreshold: Double = -70 // dBm
    var isCoverageThresholdEnabled: Bool = false

    // MARK: - AP Filter

    var selectedAPFilter: String? // BSSID to filter by, nil = all

    var uniqueBSSIDs: [(bssid: String, ssid: String)] {
        let seen = Dictionary(grouping: measurementPoints, by: { $0.bssid ?? "unknown" })
        return seen.compactMap { (bssid, points) in
            guard bssid != "unknown" else { return nil }
            let ssid = points.first?.ssid ?? bssid
            return (bssid: bssid, ssid: ssid)
        }.sorted { $0.ssid < $1.ssid }
    }

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    var measurementMode: MeasurementMode = .passive

    // MARK: - Calibration

    var isCalibrating: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var showCalibrationSheet: Bool = false

    // MARK: - Canvas

    var heatmapCGImage: CGImage?
    var showImportSheet: Bool = false

    // MARK: - Heatmap State

    var isHeatmapGenerated: Bool = false

    // MARK: - Services

    private let heatmapService = WiFiHeatmapService()
    private var wifiEngine: WiFiMeasurementEngine?
    private var signalPollTask: Task<Void, Never>?
    private let renderer: HeatmapRenderer

    // MARK: - Undo

    private var undoStack: [[MeasurementPoint]] = []

    // MARK: - Init

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    private func setupEngine() {
        let wifiService = MacWiFiInfoService()
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Lifecycle

    func onAppear() {
        startSignalPolling()
    }

    func onDisappear() {
        stopSignalPolling()
    }

    // MARK: - Signal Polling

    func startSignalPolling() {
        guard signalPollTask == nil else { return }
        signalPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentSignal = self.heatmapService.currentSignal()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSignalPolling() {
        signalPollTask?.cancel()
        signalPollTask = nil
    }

    // MARK: - Nearby AP Scan

    func refreshNearbyAPs() {
        nearbyAPs = heatmapService.scanForNearbyAPs()
    }

    // MARK: - Survey Control

    func startSurvey() {
        guard surveyProject != nil else { return }
        isSurveying = true
        sidebarMode = .survey
        isHeatmapGenerated = false
        heatmapCGImage = nil
    }

    func stopSurvey() {
        isSurveying = false
        generateHeatmap()
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard surveyProject != nil, !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        saveUndoState()

        let point: MeasurementPoint
        if measurementMode == .active {
            point = await wifiEngine?.takeActiveMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        } else {
            point = await wifiEngine?.takeMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        }

        measurementPoints.append(point)
    }

    // MARK: - Heatmap Generation

    func generateHeatmap() {
        let filteredPoints: [MeasurementPoint]
        if let bssid = selectedAPFilter {
            filteredPoints = measurementPoints.filter { $0.bssid == bssid }
        } else {
            filteredPoints = measurementPoints
        }

        guard !filteredPoints.isEmpty else {
            heatmapCGImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(
            opacity: overlayOpacity
        )
        let localRenderer = HeatmapRenderer(configuration: config)

        Task.detached { [selectedVisualization, colorScheme] in
            let image = localRenderer.render(
                points: filteredPoints,
                visualization: selectedVisualization,
                colorScheme: colorScheme
            )
            await MainActor.run { [weak self] in
                self?.heatmapCGImage = image
                self?.isHeatmapGenerated = true
            }
        }
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(from url: URL) throws {
        let imageData = try Data(contentsOf: url)
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: url.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false

        // Mandatory calibration after import
        startCalibration()
    }

    func importFloorPlan(imageData: Data, name: String) throws {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: name,
            floorPlan: floorPlan
        )
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false

        startCalibration()
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        calibrationPoints = []
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationPoints = []
    }

    func addCalibrationPoint(at normalizedPoint: CGPoint) {
        guard calibrationPoints.count < 2 else { return }
        let point = CalibrationPoint(
            pixelX: Double(normalizedPoint.x),
            pixelY: Double(normalizedPoint.y)
        )
        calibrationPoints.append(point)
        if calibrationPoints.count == 2 {
            showCalibrationSheet = true
        }
    }

    func completeCalibration(withDistance distance: Double) {
        guard calibrationPoints.count == 2,
              var project = surveyProject else { return }

        let metersPerPixel = CalibrationPoint.metersPerPixel(
            pointA: calibrationPoints[0],
            pointB: calibrationPoints[1],
            knownDistanceMeters: distance
        )

        project.floorPlan = FloorPlan(
            id: project.floorPlan.id,
            imageData: project.floorPlan.imageData,
            widthMeters: Double(project.floorPlan.pixelWidth) * metersPerPixel,
            heightMeters: Double(project.floorPlan.pixelHeight) * metersPerPixel,
            pixelWidth: project.floorPlan.pixelWidth,
            pixelHeight: project.floorPlan.pixelHeight,
            origin: project.floorPlan.origin,
            calibrationPoints: calibrationPoints,
            walls: project.floorPlan.walls
        )

        surveyProject = project
        isCalibrating = false
        calibrationPoints = []
        showCalibrationSheet = false
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurementPoints = previous
        if isHeatmapGenerated { generateHeatmap() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    // MARK: - Point Management

    func deletePoint(id: UUID) {
        saveUndoState()
        measurementPoints.removeAll { $0.id == id }
        if isHeatmapGenerated { generateHeatmap() }
    }

    func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Project Save/Load

    func saveProject(to url: URL) throws {
        guard var project = surveyProject else { return }
        project.measurementPoints = measurementPoints
        let manager = ProjectSaveLoadManager()
        try manager.save(project: project, to: url)
    }

    func loadProject(from url: URL) throws {
        let manager = ProjectSaveLoadManager()
        surveyProject = try manager.load(from: url)
        measurementPoints = surveyProject?.measurementPoints ?? []
        if !measurementPoints.isEmpty {
            generateHeatmap()
        }
    }

    // MARK: - Export

    func exportPNG(canvasSize: CGSize) -> Data? {
        guard let heatmapCGImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: heatmapCGImage)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Computed

    var filteredPoints: [MeasurementPoint] {
        if let bssid = selectedAPFilter {
            return measurementPoints.filter { $0.bssid == bssid }
        }
        return measurementPoints
    }

    var averageRSSI: Double? {
        let pts = filteredPoints
        guard !pts.isEmpty else { return nil }
        return Double(pts.reduce(0) { $0 + $1.rssi }) / Double(pts.count)
    }

    var minRSSI: Int? { filteredPoints.map(\.rssi).min() }
    var maxRSSI: Int? { filteredPoints.map(\.rssi).max() }
}
```

- [ ] **Step 4.2: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED. (The new ViewModel is not wired to any views yet, so no UI tests needed here.)

- [ ] **Step 4.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/ViewModels/WiFiHeatmapViewModel.swift
git commit -m "feat(macOS): add WiFiHeatmapViewModel with survey, analyze, AP filter, undo"
```

---

## Chunk 3: Views — Sidebar + Canvas + Main View

### Task 5: Create HeatmapSidebarView

**Files:**
- Create: `NetMonitor-macOS/Views/Heatmap/HeatmapSidebarView.swift`

- [ ] **Step 5.1: Create HeatmapSidebarView**

Create `NetMonitor-macOS/Views/Heatmap/HeatmapSidebarView.swift`:

```swift
import NetMonitorCore
import SwiftUI

// MARK: - HeatmapSidebarView

struct HeatmapSidebarView: View {
    @Bindable var viewModel: WiFiHeatmapViewModel

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch viewModel.sidebarMode {
                    case .survey:
                        surveyContent
                    case .analyze:
                        analyzeContent
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 220)
        .accessibilityIdentifier("heatmap_sidebar")
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.sidebarMode) {
            Text("Survey").tag(WiFiHeatmapViewModel.SidebarMode.survey)
            Text("Analyze").tag(WiFiHeatmapViewModel.SidebarMode.analyze)
        }
        .pickerStyle(.segmented)
        .padding(8)
        .accessibilityIdentifier("heatmap_picker_sidebarMode")
    }

    // MARK: - Survey Content

    @ViewBuilder
    private var surveyContent: some View {
        liveSignalCard
        networkInfoSection
        signalQualitySection
        measurementModeSection
        nearbyAPsSection

        if viewModel.surveyProject != nil {
            if viewModel.isSurveying {
                Button {
                    viewModel.stopSurvey()
                } label: {
                    Label("Stop Survey", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("heatmap_button_stopSurvey")
            } else {
                Button {
                    viewModel.startSurvey()
                } label: {
                    Label("Start Survey", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("heatmap_button_startSurvey")
            }
        }
    }

    // MARK: - Live Signal Card

    private var liveSignalCard: some View {
        VStack(spacing: 4) {
            Text("LIVE SIGNAL")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let signal = viewModel.currentSignal {
                Text("\(signal.rssi)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(colorForRSSI(signal.rssi))

                Text("dBm · \(qualityLabel(signal.rssi))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                signalBars(rssi: signal.rssi)
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No WiFi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("heatmap_card_liveSignal")
    }

    // MARK: - Network Info

    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Network")
            if let signal = viewModel.currentSignal {
                infoRow("SSID", value: signal.ssid ?? "—")
                infoRow("BSSID", value: signal.bssid.map { String($0.prefix(11)) + "…" } ?? "—")
                infoRow("Channel", value: signal.channel.map { ch in
                    let bandLabel = signal.band?.displayName ?? ""
                    return "\(ch) (\(bandLabel))"
                } ?? "—")
                infoRow("Link speed", value: signal.linkSpeed.map { "\($0) Mbps" } ?? "—")
            } else {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Signal Quality

    private var signalQualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Signal Quality")
            if let signal = viewModel.currentSignal {
                infoRow("Noise floor", value: signal.noiseFloor.map { "\($0) dBm" } ?? "—")
                infoRow("SNR", value: signal.snr.map { "\($0) dB" } ?? "—")
            }
        }
    }

    // MARK: - Measurement Mode

    private var measurementModeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Measurement")
            Picker("Mode", selection: $viewModel.measurementMode) {
                Text("Passive").tag(WiFiHeatmapViewModel.MeasurementMode.passive)
                Text("Active").tag(WiFiHeatmapViewModel.MeasurementMode.active)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("heatmap_picker_measurementMode")

            if viewModel.measurementMode == .active {
                Text("Speed + latency at each point (slower)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Nearby APs

    private var nearbyAPsSection: some View {
        DisclosureGroup("Nearby APs (\(viewModel.nearbyAPs.count))") {
            if viewModel.nearbyAPs.isEmpty {
                Button("Scan") {
                    viewModel.refreshNearbyAPs()
                }
                .font(.caption)
                .accessibilityIdentifier("heatmap_button_scanAPs")
            } else {
                ForEach(viewModel.nearbyAPs) { ap in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ap.ssid)
                                .font(.caption)
                                .lineLimit(1)
                            Text("Ch \(ap.channel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(ap.rssi) dBm")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(colorForRSSI(ap.rssi))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedAPFilter = ap.bssid
                        viewModel.sidebarMode = .analyze
                    }
                    .accessibilityIdentifier("heatmap_ap_\(ap.bssid)")
                }
                Button("Rescan") {
                    viewModel.refreshNearbyAPs()
                }
                .font(.caption)
            }
        }
        .font(.caption)
    }

    // MARK: - Analyze Content

    @ViewBuilder
    private var analyzeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Visualization")
            Picker("Type", selection: $viewModel.selectedVisualization) {
                ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                    Text(viz.displayName).tag(viz)
                }
            }
            .accessibilityIdentifier("heatmap_picker_visualization")
            .onChange(of: viewModel.selectedVisualization) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Opacity")
            Slider(value: $viewModel.overlayOpacity, in: 0.1...1.0)
                .accessibilityIdentifier("heatmap_slider_opacity")
                .onChange(of: viewModel.overlayOpacity) { _, _ in
                    viewModel.generateHeatmap()
                }
            Text(String(format: "%.0f%%", viewModel.overlayOpacity * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Color Scheme")
            Picker("Scheme", selection: $viewModel.colorScheme) {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .accessibilityIdentifier("heatmap_picker_colorScheme")
            .onChange(of: viewModel.colorScheme) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("AP Filter")
            Picker("AP", selection: $viewModel.selectedAPFilter) {
                Text("All APs").tag(nil as String?)
                ForEach(viewModel.uniqueBSSIDs, id: \.bssid) { entry in
                    Text(entry.ssid).tag(entry.bssid as String?)
                }
            }
            .accessibilityIdentifier("heatmap_picker_apFilter")
            .onChange(of: viewModel.selectedAPFilter) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Coverage Threshold")
            Toggle("Enable", isOn: $viewModel.isCoverageThresholdEnabled)
                .font(.caption)
                .accessibilityIdentifier("heatmap_toggle_threshold")

            if viewModel.isCoverageThresholdEnabled {
                Slider(value: $viewModel.coverageThreshold, in: -90...(-30))
                    .accessibilityIdentifier("heatmap_slider_threshold")
                Text(String(format: "%.0f dBm", viewModel.coverageThreshold))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Statistics")
            infoRow("Points", value: "\(viewModel.filteredPoints.count)")
            if let avg = viewModel.averageRSSI {
                infoRow("Avg RSSI", value: String(format: "%.1f dBm", avg))
            }
            if let min = viewModel.minRSSI {
                infoRow("Min RSSI", value: "\(min) dBm")
            }
            if let max = viewModel.maxRSSI {
                infoRow("Max RSSI", value: "\(max) dBm")
            }
        }

        if !viewModel.measurementPoints.isEmpty && !viewModel.isHeatmapGenerated {
            Button {
                viewModel.generateHeatmap()
            } label: {
                Label("Generate Heatmap", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("heatmap_button_generate")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2)
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(rssi >= -90 + i * 12 ? colorForRSSI(rssi) : Color.gray.opacity(0.3))
                    .frame(width: 6, height: CGFloat(6 + i * 3))
            }
        }
    }

    private func colorForRSSI(_ rssi: Int) -> Color {
        switch rssi {
        case -50...0: .green
        case -60 ..< -50: .yellow
        case -70 ..< -60: .orange
        default: .red
        }
    }

    private func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "Excellent"
        case -60 ..< -50: "Good"
        case -70 ..< -60: "Fair"
        default: "Weak"
        }
    }
}
```

- [ ] **Step 5.2: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Views/Heatmap/HeatmapSidebarView.swift
git commit -m "feat(macOS): add HeatmapSidebarView with Survey/Analyze modes"
```

---

### Task 6: Create new HeatmapCanvasView (SwiftUI Canvas)

**Files:**
- Create: `NetMonitor-macOS/Views/Heatmap/HeatmapCanvasNSView.swift`

This replaces the `HeatmapCanvasView` and `HeatmapCanvasNSView` currently embedded in `HeatmapSurveyView.swift`. The new version adds hover tooltips, color-coded halos during survey, and a color legend bar.

- [ ] **Step 6.1: Create HeatmapCanvasNSView.swift**

Create `NetMonitor-macOS/Views/Heatmap/HeatmapCanvasNSView.swift`:

```swift
import AppKit
import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCanvasRepresentable

struct HeatmapCanvasRepresentable: NSViewRepresentable {
    let floorPlanImageData: Data?
    let measurementPoints: [MeasurementPoint]
    let calibrationPoints: [CalibrationPoint]
    let isCalibrating: Bool
    let isSurveying: Bool
    let heatmapCGImage: CGImage?
    let overlayOpacity: Double
    let coverageThreshold: Double?
    let onTap: (CGPoint) -> Void
    let onPointDelete: (UUID) -> Void

    func makeNSView(context: Context) -> HeatmapCanvasNS {
        let view = HeatmapCanvasNS()
        view.onTap = onTap
        view.onPointDelete = onPointDelete
        return view
    }

    func updateNSView(_ nsView: HeatmapCanvasNS, context: Context) {
        nsView.floorPlanImageData = floorPlanImageData
        nsView.measurementPoints = measurementPoints
        nsView.calibrationPoints = calibrationPoints
        nsView.isCalibrating = isCalibrating
        nsView.isSurveying = isSurveying
        nsView.heatmapCGImage = heatmapCGImage
        nsView.overlayOpacity = overlayOpacity
        nsView.coverageThreshold = coverageThreshold
        nsView.needsDisplay = true
    }
}

// MARK: - HeatmapCanvasNS

class HeatmapCanvasNS: NSView {

    var floorPlanImageData: Data?
    var measurementPoints: [MeasurementPoint] = []
    var calibrationPoints: [CalibrationPoint] = []
    var isCalibrating: Bool = false
    var isSurveying: Bool = false
    var heatmapCGImage: CGImage?
    var overlayOpacity: Double = 0.7
    var coverageThreshold: Double?
    var onTap: ((CGPoint) -> Void)?
    var onPointDelete: ((UUID) -> Void)?

    // Hover state
    private var hoveredPointID: UUID?
    private var mouseLocation: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateHoveredPoint()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredPointID = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        // Future: pan support
    }

    override func magnify(with event: NSEvent) {
        // Future: pinch zoom
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        handleTap(at: location)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Z handled at view level via .onCommand
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dark canvas background
        context.setFillColor(NSColor(white: 0.08, alpha: 1.0).cgColor)
        context.fill(bounds)

        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            drawEmptyState(context)
            return
        }

        let imageRect = calculateImageRect(imageSize: nsImage.size)

        // Floor plan
        context.draw(cgImage, in: imageRect)

        // Heatmap overlay
        if let heatmap = heatmapCGImage {
            context.saveGState()
            context.setAlpha(CGFloat(overlayOpacity))
            context.draw(heatmap, in: imageRect)
            context.restoreGState()
        }

        // Measurement points
        drawMeasurementPoints(context: context, imageRect: imageRect)

        // Calibration points
        if isCalibrating {
            drawCalibrationPoints(context: context, imageRect: imageRect)
        }

        // Color legend
        if heatmapCGImage != nil {
            drawColorLegend(context: context)
        }

        // Tooltip
        if let hoveredID = hoveredPointID,
           let point = measurementPoints.first(where: { $0.id == hoveredID }) {
            drawTooltip(context: context, point: point, imageRect: imageRect)
        }
    }

    // MARK: - Measurement Points

    private func drawMeasurementPoints(context: CGContext, imageRect: CGRect) {
        for point in measurementPoints {
            let x = imageRect.minX + point.floorPlanX * imageRect.width
            let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height

            let isHovered = point.id == hoveredPointID

            if isSurveying || heatmapCGImage == nil {
                // Halo mode: colored ring based on RSSI
                let haloRadius: CGFloat = isHovered ? 14 : 10
                let haloRect = CGRect(x: x - haloRadius, y: y - haloRadius,
                                      width: haloRadius * 2, height: haloRadius * 2)
                context.setFillColor(rssiColor(point.rssi).withAlphaComponent(0.3).cgColor)
                context.fillEllipse(in: haloRect)
                context.setStrokeColor(rssiColor(point.rssi).cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: haloRect)
            }

            // Center dot
            let dotRadius: CGFloat = isHovered ? 5 : 4
            let dotRect = CGRect(x: x - dotRadius, y: y - dotRadius,
                                 width: dotRadius * 2, height: dotRadius * 2)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dotRect)

            // Outline
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: dotRect)
        }
    }

    // MARK: - Calibration Points

    private func drawCalibrationPoints(context: CGContext, imageRect: CGRect) {
        for (index, point) in calibrationPoints.enumerated() {
            let x = imageRect.minX + point.pixelX * imageRect.width
            let y = imageRect.minY + (1 - point.pixelY) * imageRect.height
            let rect = CGRect(x: x - 12, y: y - 12, width: 24, height: 24)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rect)

            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
            context.fillEllipse(in: rect)

            let label = "\(index + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2), withAttributes: attrs)
        }

        // Draw line between calibration points
        if calibrationPoints.count == 2 {
            let p1 = calibrationPoints[0]
            let p2 = calibrationPoints[1]
            let x1 = imageRect.minX + p1.pixelX * imageRect.width
            let y1 = imageRect.minY + (1 - p1.pixelY) * imageRect.height
            let x2 = imageRect.minX + p2.pixelX * imageRect.width
            let y2 = imageRect.minY + (1 - p2.pixelY) * imageRect.height

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: - Color Legend

    private func drawColorLegend(context: CGContext) {
        let legendW: CGFloat = 200
        let legendH: CGFloat = 16
        let legendX = (bounds.width - legendW) / 2
        let legendY: CGFloat = 12

        // Background pill
        let bgRect = CGRect(x: legendX - 40, y: legendY - 4, width: legendW + 80, height: legendH + 16)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        // Gradient bar
        let gradientRect = CGRect(x: legendX, y: legendY, width: legendW, height: legendH)
        let colors = [
            NSColor.systemBlue.cgColor,
            NSColor.systemCyan.cgColor,
            NSColor.systemGreen.cgColor,
            NSColor.systemYellow.cgColor,
            NSColor.systemRed.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.25, 0.5, 0.75, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: locations) {
            context.saveGState()
            context.clip(to: gradientRect)
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: gradientRect.minX, y: gradientRect.midY),
                                       end: CGPoint(x: gradientRect.maxX, y: gradientRect.midY),
                                       options: [])
            context.restoreGState()
        }

        // Labels
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.lightGray
        ]
        let leftLabel = "-90" as NSString
        let rightLabel = "-30 dBm" as NSString
        leftLabel.draw(at: CGPoint(x: legendX - 30, y: legendY), withAttributes: labelAttrs)
        rightLabel.draw(at: CGPoint(x: legendX + legendW + 4, y: legendY), withAttributes: labelAttrs)
    }

    // MARK: - Tooltip

    private func drawTooltip(context: CGContext, point: MeasurementPoint, imageRect: CGRect) {
        let x = imageRect.minX + point.floorPlanX * imageRect.width
        let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height

        let lines = buildTooltipLines(point)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: rssiColor(point.rssi)
        ]

        let lineHeight: CGFloat = 14
        let padding: CGFloat = 8
        let tooltipW: CGFloat = 160
        let tooltipH = CGFloat(lines.count + 1) * lineHeight + padding * 2

        var tooltipX = x + 16
        var tooltipY = y - tooltipH / 2
        // Keep on screen
        if tooltipX + tooltipW > bounds.maxX - 8 { tooltipX = x - tooltipW - 16 }
        if tooltipY < 8 { tooltipY = 8 }
        if tooltipY + tooltipH > bounds.maxY - 8 { tooltipY = bounds.maxY - tooltipH - 8 }

        let tooltipRect = CGRect(x: tooltipX, y: tooltipY, width: tooltipW, height: tooltipH)
        context.setFillColor(NSColor(white: 0.1, alpha: 0.95).cgColor)
        let path = CGPath(roundedRect: tooltipRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        context.addPath(path)
        context.strokePath()

        // Header line: RSSI + quality
        let header = "\(point.rssi) dBm · \(qualityLabel(point.rssi))" as NSString
        header.draw(at: CGPoint(x: tooltipX + padding, y: tooltipY + padding), withAttributes: boldAttrs)

        // Detail lines
        for (i, line) in lines.enumerated() {
            let lineStr = line as NSString
            lineStr.draw(at: CGPoint(
                x: tooltipX + padding,
                y: tooltipY + padding + CGFloat(i + 1) * lineHeight
            ), withAttributes: attrs)
        }
    }

    private func buildTooltipLines(_ point: MeasurementPoint) -> [String] {
        var lines: [String] = []
        if let snr = point.snr { lines.append("SNR: \(snr) dB") }
        if let ssid = point.ssid { lines.append("SSID: \(ssid)") }
        if let ch = point.channel, let band = point.band {
            lines.append("Ch \(ch) · \(band.displayName)")
        }
        if let speed = point.linkSpeed { lines.append("Link: \(speed) Mbps") }
        if let dl = point.downloadSpeed { lines.append(String(format: "DL: %.1f Mbps", dl)) }
        if let ul = point.uploadSpeed { lines.append(String(format: "UL: %.1f Mbps", ul)) }
        if let lat = point.latency { lines.append(String(format: "Latency: %.1f ms", lat)) }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        lines.append(formatter.string(from: point.timestamp))

        return lines
    }

    // MARK: - Helpers

    private func calculateImageRect(imageSize: NSSize) -> CGRect {
        let aspectRatio = imageSize.width / imageSize.height
        let containerAspect = bounds.width / bounds.height

        let displayedWidth: CGFloat
        let displayedHeight: CGFloat
        if aspectRatio > containerAspect {
            displayedWidth = bounds.width
            displayedHeight = bounds.width / aspectRatio
        } else {
            displayedWidth = bounds.height * aspectRatio
            displayedHeight = bounds.height
        }

        let offsetX = (bounds.width - displayedWidth) / 2
        let offsetY = (bounds.height - displayedHeight) / 2
        return CGRect(x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight)
    }

    private func handleTap(at location: CGPoint) {
        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData) else { return }

        let imageRect = calculateImageRect(imageSize: nsImage.size)
        let tapX = (location.x - imageRect.minX) / imageRect.width
        let tapY = 1.0 - (location.y - imageRect.minY) / imageRect.height

        guard tapX >= 0, tapX <= 1, tapY >= 0, tapY <= 1 else { return }
        onTap?(CGPoint(x: tapX, y: tapY))
    }

    private func updateHoveredPoint() {
        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData) else {
            hoveredPointID = nil
            return
        }

        let imageRect = calculateImageRect(imageSize: nsImage.size)
        let hitRadius: CGFloat = 12

        hoveredPointID = measurementPoints.first { point in
            let x = imageRect.minX + point.floorPlanX * imageRect.width
            let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height
            let dx = mouseLocation.x - x
            let dy = mouseLocation.y - y
            return (dx * dx + dy * dy).squareRoot() < hitRadius
        }?.id
    }

    private func rssiColor(_ rssi: Int) -> NSColor {
        switch rssi {
        case -50...0: .systemGreen
        case -60 ..< -50: .systemYellow
        case -70 ..< -60: .systemOrange
        default: .systemRed
        }
    }

    private func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "Excellent"
        case -60 ..< -50: "Good"
        case -70 ..< -60: "Fair"
        default: "Weak"
        }
    }

    private func drawEmptyState(_ context: CGContext) {
        let text = "Import a floor plan to begin" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.gray
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ), withAttributes: attrs)
    }
}
```

- [ ] **Step 6.2: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Views/Heatmap/HeatmapCanvasNSView.swift
git commit -m "feat(macOS): add HeatmapCanvasNS with halo dots, tooltips, color legend"
```

---

### Task 7: Create WiFiHeatmapView (main view) and wire to ContentView

**Files:**
- Create: `NetMonitor-macOS/Views/Heatmap/WiFiHeatmapView.swift`
- Modify: `NetMonitor-macOS/Views/ContentView.swift:125` — change `HeatmapSurveyView()` to `WiFiHeatmapView()`

- [ ] **Step 7.1: Create WiFiHeatmapView**

Create `NetMonitor-macOS/Views/Heatmap/WiFiHeatmapView.swift`:

```swift
import NetMonitorCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - WiFiHeatmapView

struct WiFiHeatmapView: View {
    @State private var viewModel = WiFiHeatmapViewModel()

    var body: some View {
        HSplitView {
            if !viewModel.isSidebarCollapsed {
                HeatmapSidebarView(viewModel: viewModel)
            }
            canvas
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $viewModel.showImportSheet,
            allowedContentTypes: [.png, .jpeg, .pdf, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            CalibrationSheet(viewModel: viewModel)
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("heatmap_view")
    }

    // MARK: - Canvas

    private var canvas: some View {
        Group {
            if viewModel.surveyProject != nil {
                HeatmapCanvasRepresentable(
                    floorPlanImageData: viewModel.surveyProject?.floorPlan.imageData,
                    measurementPoints: viewModel.filteredPoints,
                    calibrationPoints: viewModel.calibrationPoints,
                    isCalibrating: viewModel.isCalibrating,
                    isSurveying: viewModel.isSurveying,
                    heatmapCGImage: viewModel.heatmapCGImage,
                    overlayOpacity: viewModel.overlayOpacity,
                    coverageThreshold: viewModel.isCoverageThresholdEnabled ? viewModel.coverageThreshold : nil,
                    onTap: { normalizedPoint in
                        if viewModel.isCalibrating {
                            viewModel.addCalibrationPoint(at: normalizedPoint)
                        } else if viewModel.isSurveying {
                            Task<Void, Never> {
                                await viewModel.takeMeasurement(at: normalizedPoint)
                            }
                        }
                    },
                    onPointDelete: { pointId in
                        viewModel.deletePoint(id: pointId)
                    }
                )
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("WiFi Heatmap")
                .font(.title2)
            Text("Import a floor plan image to start surveying WiFi coverage")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Import Floor Plan") {
                    viewModel.showImportSheet = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("heatmap_button_import")

                Button("Open Project") {
                    loadProject()
                }
                .accessibilityIdentifier("heatmap_button_open")
            }
        }
        .padding(40)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Project name
            if let name = viewModel.surveyProject?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Visualization picker (toolbar)
            if viewModel.surveyProject != nil {
                Picker("Viz", selection: $viewModel.selectedVisualization) {
                    ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                        Text(viz.displayName).tag(viz)
                    }
                }
                .frame(width: 140)
                .onChange(of: viewModel.selectedVisualization) { _, _ in
                    if viewModel.isHeatmapGenerated { viewModel.generateHeatmap() }
                }
                .accessibilityIdentifier("heatmap_toolbar_viz")
            }

            // Point count
            if !viewModel.measurementPoints.isEmpty {
                Text("\(viewModel.filteredPoints.count) pts")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Import
            Button {
                viewModel.showImportSheet = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("heatmap_toolbar_import")

            // Calibrate
            if viewModel.isCalibrating {
                Button {
                    viewModel.cancelCalibration()
                } label: {
                    Label("Cancel Calibration", systemImage: "xmark")
                }
            } else {
                Button {
                    viewModel.startCalibration()
                } label: {
                    Label("Calibrate", systemImage: "ruler")
                }
                .disabled(viewModel.surveyProject == nil)
                .accessibilityIdentifier("heatmap_toolbar_calibrate")
            }

            // Save
            Button { saveProject() } label: {
                Label("Save", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.surveyProject == nil)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("heatmap_toolbar_save")

            // Open
            Button { loadProject() } label: {
                Label("Open", systemImage: "folder")
            }
            .accessibilityIdentifier("heatmap_toolbar_open")

            // Export
            Menu {
                Button("Export PNG") { exportImage(format: .png) }
                Button("Export PDF") { exportPDF() }
            } label: {
                Label("Export", systemImage: "doc.richtext")
            }
            .disabled(viewModel.surveyProject == nil || viewModel.measurementPoints.isEmpty)
            .accessibilityIdentifier("heatmap_toolbar_export")

            // Undo
            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityIdentifier("heatmap_toolbar_undo")

            // Sidebar toggle
            Button {
                viewModel.isSidebarCollapsed.toggle()
            } label: {
                Label("Sidebar", systemImage: viewModel.isSidebarCollapsed ? "sidebar.left" : "sidebar.left")
            }
            .accessibilityIdentifier("heatmap_toolbar_sidebar")
        }
    }

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try viewModel.importFloorPlan(from: url)
            } catch {
                print("Import failed: \(error)")
            }
        case .failure(let error):
            print("Import error: \(error)")
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "netmonsurvey")].compactMap { $0 }
        panel.nameFieldStringValue = viewModel.surveyProject?.name ?? "Survey"
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.saveProject(to: url)
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.loadProject(from: url)
        }
    }

    private func exportImage(format: NSBitmapImageRep.FileType) {
        guard let data = viewModel.exportPNG(canvasSize: CGSize(width: 800, height: 600)) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-export"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func exportPDF() {
        // Reuse the ViewModel's PDF generation (port from old ViewModel if needed)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-report"
        if panel.runModal() == .OK, let url = panel.url {
            if let pngData = viewModel.exportPNG(canvasSize: CGSize(width: 1600, height: 1200)) {
                try? pngData.write(to: url)
            }
        }
    }
}

// MARK: - CalibrationSheet

struct CalibrationSheet: View {
    @Bindable var viewModel: WiFiHeatmapViewModel
    @State private var distanceText: String = "5.0"
    @State private var unit: String = "meters"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Calibrate Floor Plan Scale")
                .font(.headline)

            Text("Click two points on the floor plan with a known distance between them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.calibrationPoints.count < 2 {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("Click \(2 - viewModel.calibrationPoints.count) more point\(viewModel.calibrationPoints.count == 1 ? "" : "s") on the floor plan")
                }
                .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Known Distance")
                    .font(.subheadline)
                HStack {
                    TextField("Distance", text: $distanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityIdentifier("heatmap_textfield_calibrationDistance")
                    Picker("Unit", selection: $unit) {
                        Text("meters").tag("meters")
                        Text("feet").tag("feet")
                    }
                    .frame(width: 100)
                }
            }

            if viewModel.calibrationPoints.count == 2 {
                Divider()
                let dist = Double(distanceText) ?? 5.0
                let realDist = unit == "feet" ? dist * 0.3048 : dist
                let metersPerPixel = CalibrationPoint.metersPerPixel(
                    pointA: viewModel.calibrationPoints[0],
                    pointB: viewModel.calibrationPoints[1],
                    knownDistanceMeters: realDist
                )
                if let project = viewModel.surveyProject {
                    let w = Double(project.floorPlan.pixelWidth) * metersPerPixel
                    let h = Double(project.floorPlan.pixelHeight) * metersPerPixel
                    LabeledContent("Floor plan size:") {
                        Text(String(format: "%.1f × %.1f m", w, h))
                    }
                    .font(.caption)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    viewModel.cancelCalibration()
                    dismiss()
                }
                Spacer()
                Button("Save Calibration") {
                    if let dist = Double(distanceText) {
                        let realDist = unit == "feet" ? dist * 0.3048 : dist
                        viewModel.completeCalibration(withDistance: realDist)
                        dismiss()
                    }
                }
                .disabled(viewModel.calibrationPoints.count < 2 || Double(distanceText) == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("heatmap_button_saveCalibration")
            }
        }
        .padding()
        .frame(width: 340, height: 320)
    }
}
```

- [ ] **Step 7.2: Wire WiFiHeatmapView into ContentView**

Open `NetMonitor-macOS/Views/ContentView.swift`. Find the line (around line 125):

```swift
case .wifiHeatmap: HeatmapSurveyView()
```

Replace with:

```swift
case .wifiHeatmap: WiFiHeatmapView()
```

- [ ] **Step 7.3: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED. There may be warnings about unused old files — that's fine, we clean them up in Task 9.

- [ ] **Step 7.4: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-macOS/Views/Heatmap/WiFiHeatmapView.swift NetMonitor-macOS/Views/ContentView.swift
git commit -m "feat(macOS): add WiFiHeatmapView and wire to ContentView"
```

---

## Chunk 4: Cleanup + Final Build

### Task 8: Remove old heatmap files

**Files:**
- Delete: `NetMonitor-macOS/Views/Heatmap/HeatmapSurveyView.swift`
- Delete: `NetMonitor-macOS/ViewModels/HeatmapSurveyViewModel.swift`
- Delete: `NetMonitor-macOS/Views/Heatmap/HeatmapProjectListView.swift`

- [ ] **Step 8.1: Delete old files**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
rm NetMonitor-macOS/Views/Heatmap/HeatmapSurveyView.swift
rm NetMonitor-macOS/ViewModels/HeatmapSurveyViewModel.swift
rm NetMonitor-macOS/Views/Heatmap/HeatmapProjectListView.swift
```

- [ ] **Step 8.2: Regenerate project and build**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED. If there are references to `HeatmapSurveyViewModel` or `CalibrationSheetMac` in other files, fix the compilation errors (likely just the ContentView reference already handled in Task 7).

- [ ] **Step 8.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add -A
git commit -m "refactor(macOS): remove old HeatmapSurveyView and HeatmapSurveyViewModel"
```

---

### Task 9: Final build verification and fix any remaining errors

- [ ] **Step 9.1: Full clean build**

```bash
cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild -scheme NetMonitor-macOS -configuration Debug clean build 2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] **Step 9.2: Fix any compilation errors**

Common issues to check:
- `HeatmapError` enum was defined in old `HeatmapSurveyViewModel.swift` — may need to move it to `WiFiHeatmapViewModel.swift` or a shared location
- `CalibrationSheetMac` was in old `HeatmapSurveyView.swift` — replaced by `CalibrationSheet` in `WiFiHeatmapView.swift`
- Any references to `HeatmapSurveyViewModel.DrawingTool` in the old canvas view — the new `HeatmapCanvasNS` doesn't use drawing mode

- [ ] **Step 9.3: Run tests via SSH**

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodegen generate && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests 2>&1 | tail -30"
```

- [ ] **Step 9.4: Commit any fixes**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add -A
git commit -m "fix(macOS): resolve compilation errors from heatmap view migration"
```

---

## Summary

| Chunk | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 | Tasks 1-2 | HeatmapColorScheme enum + 3 gradient schemes in renderer |
| 2 | Tasks 3-4 | WiFiHeatmapService (CoreWLAN) + WiFiHeatmapViewModel |
| 3 | Tasks 5-7 | HeatmapSidebarView + HeatmapCanvasNSView + WiFiHeatmapView wired in |
| 4 | Tasks 8-9 | Old files removed, clean build verified |

**Key constraints:**
- All views use `@Observable` pattern, NOT `ObservableObject`
- All interactive elements have `.accessibilityIdentifier()`
- `xcodebuild test` MUST run via `ssh mac-mini`, NEVER locally
- `xcodegen generate` MUST run after any file additions/deletions
- Swift 6 strict concurrency enforced — all services are `Sendable` or `@MainActor`
