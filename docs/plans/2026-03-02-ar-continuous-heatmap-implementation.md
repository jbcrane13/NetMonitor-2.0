# AR Continuous Heatmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the existing AR sphere-based heatmap mode with a WiFi Man-style continuous scanning mode that projects a 32×32 colored grid flat onto the detected floor using ARKit + RealityKit, filling cells as the user walks.

**Architecture:** `ARContinuousHeatmapSession` manages the ARKit session, plane detection, and RealityKit plane entity. `ARContinuousHeatmapViewModel` owns the 32×32 grid state, signal polling, distance gating, and UIImage texture rendering. `ARContinuousHeatmapView` is the full-screen SwiftUI view with camera feed, top bar, color scale strip, and AP info bar. Three old files are deleted and replaced. `FloorPlanSelectionView` is updated to reference the new view.

**Tech Stack:** ARKit (`ARWorldTrackingConfiguration`, `ARPlaneAnchor`), RealityKit (`ModelEntity`, `UnlitMaterial`, `TextureResource`), UIKit (`UIGraphicsImageRenderer`, `CGContext`), NEHotspotNetwork (signal + BSSID), Swift 6 strict concurrency, Swift Testing (`@Suite`/`@Test`/`#expect`), XcodeGen.

**Design doc:** `docs/plans/2026-03-02-ar-continuous-heatmap-redesign.md`

---

## Chunk 1: Cleanup

### Task 1: Delete old files and register new ones in project.yml

**Files:**
- Delete: `NetMonitor-iOS/Platform/ARHeatmapSession.swift`
- Delete: `NetMonitor-iOS/ViewModels/ARHeatmapSurveyViewModel.swift`
- Delete: `NetMonitor-iOS/Views/Tools/ARHeatmapSurveyView.swift`
- Delete: `Tests/NetMonitor-iOSTests/ARHeatmapSurveyViewModelTests.swift`
- Modify: `project.yml`

- [ ] **Step 1.1: Remove the four old files**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
rm NetMonitor-iOS/Platform/ARHeatmapSession.swift
rm NetMonitor-iOS/ViewModels/ARHeatmapSurveyViewModel.swift
rm NetMonitor-iOS/Views/Tools/ARHeatmapSurveyView.swift
rm Tests/NetMonitor-iOSTests/ARHeatmapSurveyViewModelTests.swift
```

- [ ] **Step 1.2: Add new files to project.yml**

Open `project.yml`. Find the sections for `NetMonitor-iOS` sources and `Tests/NetMonitor-iOSTests`.

In the iOS sources, replace any occurrence of:
- `ARHeatmapSession.swift` → `ARContinuousHeatmapSession.swift`
- `ARHeatmapSurveyViewModel.swift` → `ARContinuousHeatmapViewModel.swift`
- `ARHeatmapSurveyView.swift` → `ARContinuousHeatmapView.swift`

In the test sources, replace:
- `ARHeatmapSurveyViewModelTests.swift` → `ARContinuousHeatmapViewModelTests.swift`

If project.yml uses glob patterns (e.g., `"**/*.swift"`), no change is needed — the new filenames will be picked up automatically.

- [ ] **Step 1.3: Regenerate the Xcode project**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
```

Expected: `Generating project NetMonitor-2.0.xcodeproj`

- [ ] **Step 1.4: Verify the project still builds (it will have missing-type errors for now — that is expected)**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -10
```

Expected: build errors referencing `ARHeatmapSurveyView`, `ARHeatmapSession`, etc. — that is correct at this stage.

- [ ] **Step 1.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add -A
git commit -m "chore: remove old AR heatmap files — replaced in next commits"
```

---

## Chunk 2: Session Layer

### Task 2: ARContinuousHeatmapSession

**Files:**
- Create: `NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift`

This class owns the ARKit session and the RealityKit plane entity. It is `@MainActor` and uses a simulator stub so unit tests compile on the host machine.

The plane entity covers a 10 m × 10 m area. Its texture is a 1024 × 1024 px `TextureResource` — 32 px per cell for a 32×32 grid.

- [ ] **Step 2.1: Create `NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift`**

```swift
import Foundation
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

// MARK: - ARContinuousHeatmapSession (real device)

/// Manages the ARKit world-tracking session and the RealityKit floor grid plane.
///
/// - Starts a world-tracking configuration with horizontal plane detection.
/// - On first detected horizontal plane, creates and anchors a 10 m × 10 m flat
///   `ModelEntity` with an `UnlitMaterial`. Callers update the texture via
///   `updateGridTexture(_:)`.
/// - Provides `worldToGridCell(gridSize:)` to map camera world XZ position
///   onto a grid cell index.
@MainActor
final class ARContinuousHeatmapSession: NSObject, @unchecked Sendable {

    // MARK: - Constants

    /// Side length of the AR floor plane in meters.
    static let planeSizeMeters: Float = 10.0
    /// Minimum camera movement (meters) before a new cell is recorded.
    static let distanceGate: Float = 0.3

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    // MARK: - Public

    let arView: ARView

    /// Called on the main actor when the first horizontal plane is detected.
    var onFloorDetected: (() -> Void)?

    // MARK: - Private

    private var floorAnchorEntity: AnchorEntity?
    private var gridPlaneEntity: ModelEntity?
    private var floorAnchor: ARPlaneAnchor?
    private var hasDetectedFloor = false

    // MARK: - Init

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.session.delegate = self
    }

    // MARK: - Lifecycle

    func startSession() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        hasDetectedFloor = false
        floorAnchorEntity = nil
        gridPlaneEntity = nil
        floorAnchor = nil
    }

    func stopSession() {
        arView.session.pause()
    }

    // MARK: - Position

    /// The camera's current position in world space, or nil if no frame is available.
    var currentWorldPosition: SIMD3<Float>? {
        guard let frame = arView.session.currentFrame else { return nil }
        let col = frame.camera.transform.columns.3
        return SIMD3(col.x, col.y, col.z)
    }

    // MARK: - Grid Mapping

    /// Convert the camera's current world XZ position to a grid (col, row) index.
    ///
    /// The floor plane is `planeSizeMeters × planeSizeMeters`, centred at the
    /// plane anchor's origin. (col, row) are clamped to `[0, gridSize-1]`.
    ///
    /// Returns nil if there is no floor anchor or no current frame.
    func worldToGridCell(gridSize: Int) -> (col: Int, row: Int)? {
        guard let anchor = floorAnchor,
              let frame = arView.session.currentFrame else { return nil }

        // World position of camera
        let camWorld = frame.camera.transform.columns.3
        let camPos = SIMD4<Float>(camWorld.x, camWorld.y, camWorld.z, 1)

        // Transform into floor-plane local space
        let anchorTransform = anchor.transform
        let invAnchor = anchorTransform.inverse
        let localPos = invAnchor * camPos

        // localPos.x and localPos.z are the in-plane coordinates
        // Plane spans [-planeSizeMeters/2 … +planeSizeMeters/2] on both axes
        let half = Self.planeSizeMeters / 2.0
        let normX = (localPos.x + half) / Self.planeSizeMeters  // 0…1
        let normZ = (localPos.z + half) / Self.planeSizeMeters  // 0…1

        let col = Int((normX * Float(gridSize)).rounded(.down)).clamped(to: 0...(gridSize - 1))
        let row = Int((normZ * Float(gridSize)).rounded(.down)).clamped(to: 0...(gridSize - 1))
        return (col, row)
    }

    // MARK: - Texture

    /// Replace the floor plane entity's material texture with the given image.
    /// Call this each time the grid state changes.
    func updateGridTexture(_ image: UIImage) {
        guard let entity = gridPlaneEntity else { return }
        guard let cgImage = image.cgImage else { return }
        let options = TextureResource.CreateOptions(semantic: .color)
        guard let texture = try? TextureResource.generate(from: cgImage, options: options) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.9), texture: .init(texture))
        entity.model?.materials = [material]
    }

    // MARK: - Private helpers

    private func createFloorPlane(for anchor: ARPlaneAnchor) {
        guard !hasDetectedFloor else { return }
        hasDetectedFloor = true
        floorAnchor = anchor

        let size = Self.planeSizeMeters
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        var material = UnlitMaterial()
        material.color = .init(tint: .black.withAlphaComponent(0.01))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        // Rotate 90° around X so the plane lies flat (RealityKit planes are vertical by default)
        entity.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)

        floorAnchorEntity = anchorEntity
        gridPlaneEntity = entity

        Task { @MainActor in
            self.onFloorDetected?()
        }
    }
}

// MARK: - ARSessionDelegate

extension ARContinuousHeatmapSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .horizontal else { continue }
            Task { @MainActor in
                self.createFloorPlane(for: plane)
            }
            return
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {}
    nonisolated func sessionWasInterrupted(_ session: ARSession) {}
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {}
}

// MARK: - Comparable extension for clamping

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

#else

// MARK: - ARContinuousHeatmapSession (simulator stub)

@MainActor
final class ARContinuousHeatmapSession: NSObject {
    static var isSupported: Bool { false }
    static let distanceGate: Float = 0.3
    static let planeSizeMeters: Float = 10.0

    var onFloorDetected: (() -> Void)?

    override init() { super.init() }

    func startSession() {}
    func stopSession() {}

    var currentWorldPosition: SIMD3<Float>? { nil }

    func worldToGridCell(gridSize: Int) -> (col: Int, row: Int)? { nil }

    func updateGridTexture(_ image: UIImage) {}
}

#endif
```

- [ ] **Step 2.2: Regenerate and build to verify no compile errors in this file**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep "ARContinuousHeatmapSession" | grep "error:" | head -5
```

Expected: no errors mentioning `ARContinuousHeatmapSession`.

- [ ] **Step 2.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift
git commit -m "feat(ios): add ARContinuousHeatmapSession with plane detection and grid texture"
```

---

## Chunk 3: ViewModel + Tests

### Task 3: ARContinuousHeatmapViewModel and tests

**Files:**
- Create: `Tests/NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests.swift`
- Create: `NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift`

The ViewModel owns the 32×32 grid state (`[[Int?]]`), signal polling loop, distance gating, AP info reading, and texture rendering. Pure computation methods (grid → UIImage, coord mapping) are tested without AR.

- [ ] **Step 3.1: Write failing tests first**

Create `Tests/NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ARContinuousHeatmapViewModel Tests

@Suite("ARContinuousHeatmapViewModel")
@MainActor
struct ARContinuousHeatmapViewModelTests {

    // MARK: - Initial state

    @Test("initial isScanning is false")
    func initialNotScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.isScanning == false)
    }

    @Test("initial floorDetected is false")
    func initialFloorNotDetected() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.floorDetected == false)
    }

    @Test("initial pointCount is 0")
    func initialPointCount() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.pointCount == 0)
    }

    @Test("initial signalDBm is -65")
    func initialSignal() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.signalDBm == -65)
    }

    @Test("initial ssid is nil")
    func initialSSID() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.ssid == nil)
    }

    @Test("initial bssid is nil")
    func initialBSSID() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.bssid == nil)
    }

    @Test("initial errorMessage is nil")
    func initialError() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Signal display helpers

    @Test("signalColor is green above -50 dBm")
    func signalColorGreen() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -40
        #expect(vm.signalColor == .green)
    }

    @Test("signalColor is yellow between -50 and -70 dBm")
    func signalColorYellow() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -60
        #expect(vm.signalColor == .yellow)
    }

    @Test("signalColor is red at -70 dBm or below")
    func signalColorRed() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -80
        #expect(vm.signalColor == .red)
    }

    @Test("signalText shows dBm when scanning")
    func signalTextScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.isScanning = true
        vm.signalDBm = -55
        #expect(vm.signalText == "-55 dBm")
    }

    @Test("signalText shows -- when not scanning")
    func signalTextNotScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.signalText == "--")
    }

    // MARK: - Scan lifecycle (simulator — AR session stub returns nil position)

    @Test("startScanning sets isScanning true")
    func startSetsScanning() async {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        #expect(vm.isScanning == true)
    }

    @Test("stopScanning sets isScanning false")
    func stopSetsNotScanning() async {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    @Test("double start is a no-op")
    func doubleStart() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        vm.startScanning()
        #expect(vm.isScanning == true)
    }

    @Test("double stop is a no-op")
    func doubleStop() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    @Test("startScanning resets grid state")
    func startResetsGrid() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        // Pre-populate a cell
        vm.gridState[5][5] = -60
        vm.startScanning()
        #expect(vm.gridState[5][5] == nil)
    }

    // MARK: - buildSurvey

    @Test("buildSurvey with no points returns nil")
    func buildSurveyEmpty() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.buildSurvey() == nil)
    }

    @Test("buildSurvey with points returns arContinuous mode survey")
    func buildSurveyMode() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.injectWorldPoint(x: 0.0, z: 0.0, rssi: -60)
        vm.injectWorldPoint(x: 1.0, z: 1.0, rssi: -70)
        let survey = vm.buildSurvey()
        #expect(survey != nil)
        #expect(survey?.mode == .arContinuous)
    }

    @Test("buildSurvey normalizes points to 0-1 range")
    func buildSurveyNormalized() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.injectWorldPoint(x: 0.0, z: 0.0, rssi: -60)
        vm.injectWorldPoint(x: 4.0, z: 4.0, rssi: -70)
        let survey = vm.buildSurvey()!
        let xs = survey.dataPoints.map(\.x)
        let ys = survey.dataPoints.map(\.y)
        #expect(xs.min()! >= 0.0)
        #expect(xs.max()! <= 1.0)
        #expect(ys.min()! >= 0.0)
        #expect(ys.max()! <= 1.0)
    }

    // MARK: - Grid texture rendering

    @Test("renderGridTexture with empty grid returns 1024x1024 image")
    func renderTextureSize() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        let img = vm.renderGridTexture()
        #expect(img.size.width == 1024)
        #expect(img.size.height == 1024)
    }

    @Test("renderGridTexture with a colored cell returns non-nil image")
    func renderTextureWithCell() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.gridState[0][0] = -50
        let img = vm.renderGridTexture()
        #expect(img.cgImage != nil)
    }

    // MARK: - Distance gating

    @Test("distanceExceeded returns true when position moved beyond gate")
    func distanceBeyondGate() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        // Set last recorded position manually
        vm.setLastPosition(SIMD3<Float>(0, 0, 0))
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0.5, 0, 0)) == true)
    }

    @Test("distanceExceeded returns false when position is close")
    func distanceWithinGate() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.setLastPosition(SIMD3<Float>(0, 0, 0))
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0.1, 0, 0)) == false)
    }

    @Test("distanceExceeded returns true when no last position (first point)")
    func distanceFirstPoint() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0, 0, 0)) == true)
    }
}
```

> **Note:** `injectWorldPoint`, `setLastPosition`, and `distanceExceeded` are `internal` test-support methods added to the ViewModel. `gridState` is a `var` (not `private`) so tests can inspect it. `isScanning` and `signalDBm` are also `var` for test injection.

- [ ] **Step 3.2: Run tests — expect failures**

Run tests on the mac-mini via SSH (see SKILL.md `run-tests`):

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|cannot find|FAILED|passed'"
```

Expected: compile errors — `ARContinuousHeatmapViewModel` not found.

- [ ] **Step 3.3: Create `NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift`**

```swift
import Foundation
import SwiftUI
import NetMonitorCore
import CoreLocation
#if os(iOS)
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
#endif

// MARK: - ARContinuousHeatmapViewModel

/// Drives the AR continuous heatmap scanning mode.
///
/// Manages a 32×32 grid of RSSI values painted cell-by-cell as the user walks.
/// Signal is polled every second; a 30 cm distance gate prevents duplicate readings.
/// On completion, world XZ coordinates are normalised to 0–1 for HeatmapSurvey.
@MainActor
@Observable
final class ARContinuousHeatmapViewModel {

    // MARK: - Constants

    static let gridSize = 32
    static let texturePx = 1024     // 32 px per cell
    static let cellPx = texturePx / gridSize   // 32 px

    // MARK: - Public State (var so tests can inject)

    var isScanning = false
    var floorDetected = false
    var signalDBm: Int = -65
    var ssid: String?
    var bssid: String?
    var band: String?
    var pointCount: Int = 0
    var errorMessage: String?
    var statusMessage = "Initializing AR session."

    /// 32×32 grid — nil means unvisited, Int = RSSI dBm at that cell.
    var gridState: [[Int?]] = Array(
        repeating: Array(repeating: nil, count: ARContinuousHeatmapViewModel.gridSize),
        count: ARContinuousHeatmapViewModel.gridSize
    )
    /// The grid cell currently under the camera (for drawing the position ring).
    private(set) var currentCell: (col: Int, row: Int)?

    // MARK: - Private

    let session: ARContinuousHeatmapSession
    private var worldPoints: [(x: Float, z: Float, signalStrength: Int, timestamp: Date)] = []
    private var lastRecordedPosition: SIMD3<Float>?
    private var scanTask: Task<Void, Never>?
    private let locationDelegate = ARHeatmapLocationDelegate()

    // MARK: - Init

    init(session: ARContinuousHeatmapSession? = nil) {
        self.session = session ?? ARContinuousHeatmapSession()
    }

    // MARK: - Lifecycle

    func startScanning() {
        guard !isScanning else { return }

        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.manager.requestWhenInUseAuthorization()
            statusMessage = "Grant location access to read WiFi signal"
            locationDelegate.onAuthorized = { [weak self] in
                Task { @MainActor in self?.beginScanning() }
            }
            locationDelegate.onDenied = { [weak self] in
                Task { @MainActor in
                    self?.errorMessage = "Location access required for WiFi signal reading"
                }
            }
            return
        } else if status == .denied || status == .restricted {
            errorMessage = "Location access denied — enable in Settings > Privacy > Location Services"
            return
        }

        beginScanning()
    }

    private func beginScanning() {
        isScanning = true
        floorDetected = false
        worldPoints = []
        gridState = Array(repeating: Array(repeating: nil, count: Self.gridSize), count: Self.gridSize)
        currentCell = nil
        lastRecordedPosition = nil
        pointCount = 0
        errorMessage = nil
        statusMessage = "Initializing AR session."

        session.onFloorDetected = { [weak self] in
            Task { @MainActor in
                self?.floorDetected = true
                self?.statusMessage = "Walk around to map coverage"
            }
        }

        session.startSession()

        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        session.stopSession()
        statusMessage = worldPoints.isEmpty ? "No data recorded" : "Scan complete — \(worldPoints.count) measurements"
    }

    // MARK: - Survey Output

    /// Build a `HeatmapSurvey` from the recorded world points, normalising XZ to 0–1.
    func buildSurvey(name: String? = nil) -> HeatmapSurvey? {
        let normalised = normalisePoints()
        guard !normalised.isEmpty else { return nil }
        return HeatmapSurvey(name: name ?? "AR Scan", mode: .arContinuous, dataPoints: normalised)
    }

    // MARK: - Grid Texture

    /// Render `gridState` into a 1024×1024 UIImage for the floor plane texture.
    func renderGridTexture() -> UIImage {
        let size = CGFloat(Self.texturePx)
        let cellSize = CGFloat(Self.cellPx)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Background — fully transparent
            cgCtx.clear(CGRect(x: 0, y: 0, width: size, height: size))

            // Paint visited cells
            for row in 0..<Self.gridSize {
                for col in 0..<Self.gridSize {
                    guard let rssi = gridState[row][col] else { continue }
                    let rgb = HeatmapRenderer.colorComponents(rssi: rssi, scheme: .signal)
                    let color = UIColor(red: CGFloat(rgb.r) / 255,
                                       green: CGFloat(rgb.g) / 255,
                                       blue: CGFloat(rgb.b) / 255,
                                       alpha: 0.85)
                    cgCtx.setFillColor(color.cgColor)
                    let rect = CGRect(x: CGFloat(col) * cellSize,
                                     y: CGFloat(row) * cellSize,
                                     width: cellSize, height: cellSize)
                    cgCtx.fill(rect)
                }
            }

            // Grid lines (subtle)
            cgCtx.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
            cgCtx.setLineWidth(0.5)
            for i in 0...Self.gridSize {
                let x = CGFloat(i) * cellSize
                cgCtx.move(to: CGPoint(x: x, y: 0))
                cgCtx.addLine(to: CGPoint(x: x, y: size))
                let y = CGFloat(i) * cellSize
                cgCtx.move(to: CGPoint(x: 0, y: y))
                cgCtx.addLine(to: CGPoint(x: size, y: y))
            }
            cgCtx.strokePath()

            // Current position ring
            if let cell = currentCell {
                let cx = CGFloat(cell.col) * cellSize + cellSize / 2
                let cy = CGFloat(cell.row) * cellSize + cellSize / 2
                let r = cellSize * 0.4
                let ring = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                cgCtx.setStrokeColor(UIColor.white.cgColor)
                cgCtx.setLineWidth(2.0)
                cgCtx.strokeEllipse(in: ring)
                // Inner fill
                cgCtx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                let inner = ring.insetBy(dx: r * 0.6, dy: r * 0.6)
                cgCtx.fillEllipse(in: inner)
            }
        }
    }

    // MARK: - Display Helpers

    var signalColor: Color {
        if signalDBm > -50 { return .green }
        if signalDBm > -70 { return .yellow }
        return .red
    }

    var signalText: String {
        isScanning ? "\(signalDBm) dBm" : "--"
    }

    // MARK: - Internal helpers (accessible to tests)

    /// Inject a world point directly (test support).
    func injectWorldPoint(x: Float, z: Float, rssi: Int) {
        worldPoints.append((x: x, z: z, signalStrength: rssi, timestamp: Date()))
        pointCount = worldPoints.count
    }

    /// Set last recorded position (test support).
    func setLastPosition(_ position: SIMD3<Float>) {
        lastRecordedPosition = position
    }

    /// Returns true when the camera has moved more than `distanceGate` from last recorded position.
    func distanceExceeded(from position: SIMD3<Float>) -> Bool {
        guard let last = lastRecordedPosition else { return true }
        let d = position - last
        return sqrt(d.x * d.x + d.z * d.z) >= ARContinuousHeatmapSession.distanceGate
    }

    // MARK: - Private

    private func sampleTick() async {
        await refreshSignal()

        guard let pos = session.currentWorldPosition else {
            if !floorDetected {
                statusMessage = "Detecting floor..."
            }
            return
        }

        // Update current cell for the position ring
        currentCell = session.worldToGridCell(gridSize: Self.gridSize)

        guard distanceExceeded(from: pos) else { return }
        lastRecordedPosition = pos

        // Record world point
        worldPoints.append((x: pos.x, z: pos.z, signalStrength: signalDBm, timestamp: Date()))
        pointCount = worldPoints.count

        // Paint grid cell
        if let cell = currentCell {
            gridState[cell.row][cell.col] = signalDBm
        }

        // Update AR plane texture
        let texture = renderGridTexture()
        session.updateGridTexture(texture)
    }

    private func refreshSignal() async {
        #if targetEnvironment(simulator)
        signalDBm = -55
        ssid = "Simulator WiFi"
        bssid = "AA:BB:CC:DD:EE:FF"
        band = "5 GHz"
        #elseif os(iOS)
        var network = await NEHotspotNetwork.fetchCurrent()
        if network == nil {
            try? await Task.sleep(for: .milliseconds(300))
            network = await NEHotspotNetwork.fetchCurrent()
        }

        if let network, network.signalStrength > 0 {
            errorMessage = nil
            let q = max(0, min(1, network.signalStrength))
            signalDBm = Int(-100.0 + q * 70.0)
            ssid = network.ssid
            bssid = network.bssid
        } else {
            if let interfaces = CNCopySupportedInterfaces() as? [String],
               let iface = interfaces.first,
               let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any] {
                ssid = info[kCNNetworkInfoKeySSID as String] as? String
            } else if errorMessage == nil {
                errorMessage = "WiFi signal unavailable"
            }
        }
        #endif
    }

    private func normalisePoints() -> [HeatmapDataPoint] {
        guard !worldPoints.isEmpty else { return [] }
        let xs = worldPoints.map(\.x)
        let zs = worldPoints.map(\.z)
        guard let xMin = xs.min(), let xMax = xs.max(),
              let zMin = zs.min(), let zMax = zs.max() else { return [] }
        let rangeX = xMax - xMin
        let rangeZ = zMax - zMin
        return worldPoints.map { pt in
            let nx = rangeX > 0.001 ? Double((pt.x - xMin) / rangeX) : 0.5
            let ny = rangeZ > 0.001 ? Double((pt.z - zMin) / rangeZ) : 0.5
            return HeatmapDataPoint(x: nx, y: ny, signalStrength: pt.signalStrength, timestamp: pt.timestamp)
        }
    }
}

// MARK: - Location auth helper (reused from existing pattern)

private final class ARHeatmapLocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var onAuthorized: (() -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            onAuthorized?(); onAuthorized = nil; onDenied = nil
        case .denied, .restricted:
            onDenied?(); onAuthorized = nil; onDenied = nil
        default:
            break
        }
    }
}
```

- [ ] **Step 3.4: Run tests — expect all to pass**

Run on mac-mini:
```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'Test run|passed|failed|error:'"
```

Expected: all tests pass.

- [ ] **Step 3.5: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift \
        Tests/NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests.swift
git commit -m "feat(ios): add ARContinuousHeatmapViewModel with grid state, texture rendering, and distance gating"
```

---

## Chunk 4: View

### Task 4: ARContinuousHeatmapView

**Files:**
- Create: `NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift`

Full-screen view. Uses `UIViewRepresentable` to embed the `ARView`. All UI is SwiftUI overlaid on top. Matches WiFi Man layout: top bar with SSID, bottom color scale strip, bottom AP info bar.

- [ ] **Step 4.1: Create `NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift`**

```swift
import SwiftUI
import NetMonitorCore

// MARK: - ARViewRepresentable

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

private struct ARViewRepresentable: UIViewRepresentable {
    let session: ARContinuousHeatmapSession
    func makeUIView(context: Context) -> ARView { session.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif

// MARK: - ARContinuousHeatmapView

/// Full-screen WiFi Man-style continuous heatmap.
///
/// Layout (portrait):
///   - Top bar: ✕  "Signal Strength"  [Done]  +  SSID below title
///   - Full-screen AR camera feed with floor grid rendered by ARKit
///   - Bottom: dBm color scale strip (GlassCard)
///   - Bottom: AP info bar — SSID, BSSID, dBm, band (GlassCard)
struct ARContinuousHeatmapView: View {
    @State private var viewModel = ARContinuousHeatmapViewModel()
    var onComplete: (HeatmapSurvey?) -> Void

    var body: some View {
        ZStack {
            if ARContinuousHeatmapSession.isSupported {
                arContent
            } else {
                unsupportedContent
            }
        }
        .statusBarHidden(true)
        .ignoresSafeArea()
        .onAppear { viewModel.startScanning() }
        .onDisappear {
            if viewModel.isScanning { viewModel.stopScanning() }
        }
        .accessibilityIdentifier("screen_arContinuousHeatmap")
    }

    // MARK: - AR Content

    @ViewBuilder
    private var arContent: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ZStack(alignment: .bottom) {
            // Camera feed
            ARViewRepresentable(session: viewModel.session)
                .ignoresSafeArea()

            // Status overlay (shown while waiting for floor)
            if !viewModel.floorDetected {
                statusOverlay
            }

            // Bottom chrome
            VStack(spacing: 0) {
                Spacer()
                colorScaleStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                apInfoBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            topBar
                .padding(.top, 56)
                .padding(.horizontal, 16)
        }
        #else
        // Simulator: show a dark placeholder with the overlay chrome
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            Text("AR not available in Simulator")
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 0) {
                Spacer()
                colorScaleStrip.padding(.horizontal, 12).padding(.bottom, 6)
                apInfoBar.padding(.horizontal, 12).padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            topBar.padding(.top, 56).padding(.horizontal, 16)
        }
        #endif
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    viewModel.stopScanning()
                    onComplete(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityIdentifier("ar_continuous_button_close")

                Spacer()

                Text("Signal Strength")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    viewModel.stopScanning()
                    onComplete(viewModel.buildSurvey())
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityIdentifier("ar_continuous_button_done")
            }

            if let ssid = viewModel.ssid {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.caption2)
                    Text(ssid)
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - Status Overlay

    private var statusOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("ar_continuous_status_overlay")
    }

    // MARK: - Color Scale Strip

    /// Matches WiFi Man: "dBm  -80  -70  -60  -50  -40  -30" with red→green gradient
    private var colorScaleStrip: some View {
        HStack(spacing: 0) {
            Text("dBm")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.trailing, 6)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Gradient bar
                    LinearGradient(
                        colors: [
                            Color(red: 0.8, green: 0, blue: 0),
                            Color(red: 1, green: 0.27, blue: 0),
                            Color(red: 1, green: 0.8, blue: 0),
                            Color(red: 0.53, green: 1, blue: 0),
                            Color(red: 0, green: 0.87, blue: 0.27),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Tick labels
                    HStack(spacing: 0) {
                        ForEach([-80, -70, -60, -50, -40, -30], id: \.self) { val in
                            Text("\(val)")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .offset(y: 14)
                }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("ar_continuous_color_scale")
    }

    // MARK: - AP Info Bar

    private var apInfoBar: some View {
        HStack(spacing: 14) {
            // AP icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // SSID + BSSID
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.ssid ?? "—")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(viewModel.bssid ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            // Signal + band
            VStack(alignment: .trailing, spacing: 3) {
                Text(viewModel.signalText)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(viewModel.signalColor)
                    .monospacedDigit()
                if let band = viewModel.band {
                    Text(band)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("ar_continuous_ap_info_bar")
    }

    // MARK: - Unsupported Fallback

    private var unsupportedContent: some View {
        ZStack {
            Theme.Colors.backgroundBase.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.Colors.warning)
                VStack(spacing: 10) {
                    Text("AR Not Available")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Continuous AR scanning requires ARKit world tracking.\nUse Freeform or Floorplan mode instead.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Button {
                    onComplete(nil)
                } label: {
                    Text("Go Back")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("ar_continuous_button_unsupported_back")
            }
            .padding(40)
        }
    }
}
```

- [ ] **Step 4.2: Build iOS to verify compile success**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 4.3: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift
git commit -m "feat(ios): add ARContinuousHeatmapView with WiFi Man-style floor grid UI"
```

---

## Chunk 5: Wiring

### Task 5: Update FloorPlanSelectionView

**Files:**
- Modify: `NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift`

One surgical change: replace the `fullScreenCover` that presented `ARHeatmapSurveyView` with `ARContinuousHeatmapView`, and update the `ARHeatmapSession.isSupported` badge check.

- [ ] **Step 5.1: Update the fullScreenCover in FloorPlanSelectionView**

Open `NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift`.

Find the `.fullScreenCover(isPresented: $showARContinuousScan)` block:

```swift
// Full-screen AR continuous scan
.fullScreenCover(isPresented: $showARContinuousScan) {
    ARHeatmapSurveyView { survey in
        showARContinuousScan = false
        if let survey {
            onARSurveyComplete?(survey)
        }
    }
}
```

Replace with:

```swift
// Full-screen AR continuous scan
.fullScreenCover(isPresented: $showARContinuousScan) {
    ARContinuousHeatmapView { survey in
        showARContinuousScan = false
        if let survey {
            onARSurveyComplete?(survey)
        }
    }
}
```

Also find the badge check in the "AR Continuous Scan" `SourceCard`:

```swift
badge: ARHeatmapSession.isSupported ? "RECOMMENDED" : "AR REQUIRED",
```

Replace with:

```swift
badge: ARContinuousHeatmapSession.isSupported ? "RECOMMENDED" : "AR REQUIRED",
```

- [ ] **Step 5.2: Build to verify**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded` with no references to old type names.

- [ ] **Step 5.3: Run all iOS tests on mac-mini**

```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'Test run|passed|failed|error:'"
```

Expected: all tests pass.

- [ ] **Step 5.4: Commit**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift
git commit -m "feat(ios): wire ARContinuousHeatmapView into FloorPlanSelectionView"
```

---

## Chunk 6: Lint + Final Verification

### Task 6: Lint and build check

- [ ] **Step 6.1: Run SwiftLint**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swiftlint lint --quiet NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift \
    NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift \
    NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift
```

Expected: zero errors. Fix any reported errors (warnings are OK).

- [ ] **Step 6.2: Run SwiftFormat lint**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
swiftformat --lint NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift \
    NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift \
    NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift 2>&1 | grep -v "^$"
```

Expected: no violations, or auto-fix and re-check.

- [ ] **Step 6.3: Full iOS build**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6.4: Final commit if any lint fixes were made**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add -A
git status
# Only commit if there are changes
git diff --cached --quiet || git commit -m "style: lint fixes for AR continuous heatmap files"
```

---

## Summary of all new/changed files

| File | Action |
|------|--------|
| `NetMonitor-iOS/Platform/ARContinuousHeatmapSession.swift` | **Create** |
| `NetMonitor-iOS/ViewModels/ARContinuousHeatmapViewModel.swift` | **Create** |
| `NetMonitor-iOS/Views/Tools/ARContinuousHeatmapView.swift` | **Create** |
| `Tests/NetMonitor-iOSTests/ARContinuousHeatmapViewModelTests.swift` | **Create** |
| `NetMonitor-iOS/Views/Tools/FloorPlanSelectionView.swift` | **Modify** (2 lines) |
| `NetMonitor-iOS/Platform/ARHeatmapSession.swift` | **Delete** |
| `NetMonitor-iOS/ViewModels/ARHeatmapSurveyViewModel.swift` | **Delete** |
| `NetMonitor-iOS/Views/Tools/ARHeatmapSurveyView.swift` | **Delete** |
| `Tests/NetMonitor-iOSTests/ARHeatmapSurveyViewModelTests.swift` | **Delete** |
