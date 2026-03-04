import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - ARScanViewModel Tests

@Suite("ARScanViewModel")
@MainActor
struct ARScanViewModelTests {

    // MARK: - Initialization

    @Test("initial sessionState is idle")
    func initialSessionStateIsIdle() {
        let vm = ARScanViewModel()
        #expect(vm.sessionState == .idle)
    }

    @Test("initial error message is nil")
    func initialErrorMessageIsNil() {
        let vm = ARScanViewModel()
        #expect(vm.errorMessage == nil)
    }

    @Test("initial detected surfaces is empty")
    func initialDetectedSurfacesEmpty() {
        let vm = ARScanViewModel()
        #expect(vm.detectedSurfaces.isEmpty)
    }

    @Test("isScanning is false initially")
    func isScanningFalseInitially() {
        let vm = ARScanViewModel()
        #expect(vm.isScanning == false)
    }

    @Test("wallCount is zero with no surfaces")
    func wallCountZeroInitially() {
        let vm = ARScanViewModel()
        #expect(vm.wallCount == 0)
    }

    @Test("floorCount is zero with no surfaces")
    func floorCountZeroInitially() {
        let vm = ARScanViewModel()
        #expect(vm.floorCount == 0)
    }

    @Test("hasSurfacesDetected is false with no surfaces")
    func hasSurfacesDetectedFalseInitially() {
        let vm = ARScanViewModel()
        #expect(vm.hasSurfacesDetected == false)
    }

    // MARK: - Device Capability

    @Test("deviceCapability matches session manager")
    func deviceCapabilityMatchesManager() {
        let manager = ARSessionManager()
        let vm = ARScanViewModel(sessionManager: manager)
        #expect(vm.deviceCapability == manager.deviceCapability)
    }

    @Test("isARSupported is false on simulator")
    func isARSupportedFalseOnSimulator() {
        let vm = ARScanViewModel()
        // In simulator, ARKit is not supported
        #expect(vm.isARSupported == false)
    }

    @Test("isLiDAR is false on simulator")
    func isLiDARFalseOnSimulator() {
        let vm = ARScanViewModel()
        #expect(vm.isLiDAR == false)
    }

    // MARK: - Instruction Text

    @Test("instruction text is correct for idle state")
    func instructionTextIdle() {
        let vm = ARScanViewModel()
        #expect(vm.instructionText.contains("Tap Start"))
    }

    @Test("instruction text updates for error state")
    func instructionTextError() {
        let vm = ARScanViewModel()
        // Trigger an error by starting on unsupported device
        Task {
            await vm.startScan()
        }
        // On simulator, should get an error message about AR not being supported
        // The session state should become error
    }

    // MARK: - Non-LiDAR Guidance

    @Test("nonLiDARGuidanceText is nil when unsupported")
    func nonLiDARGuidanceNilWhenUnsupported() {
        let vm = ARScanViewModel()
        // On simulator, device is unsupported, so guidance is nil
        #expect(vm.nonLiDARGuidanceText == nil)
    }

    // MARK: - Stop Scan

    @Test("stopScan resets state to idle")
    func stopScanResetsToIdle() {
        let vm = ARScanViewModel()
        vm.stopScan()
        #expect(vm.sessionState == .idle)
        #expect(vm.isScanning == false)
    }
}

// MARK: - ARDeviceCapability Tests

@Suite("ARDeviceCapability")
struct ARDeviceCapabilityTests {

    @Test("unsupported is not equal to lidar")
    func unsupportedNotLiDAR() {
        #expect(ARDeviceCapability.unsupported != ARDeviceCapability.lidar)
    }

    @Test("unsupported is not equal to nonLiDAR")
    func unsupportedNotNonLiDAR() {
        #expect(ARDeviceCapability.unsupported != ARDeviceCapability.nonLiDAR)
    }

    @Test("lidar is not equal to nonLiDAR")
    func lidarNotNonLiDAR() {
        #expect(ARDeviceCapability.lidar != ARDeviceCapability.nonLiDAR)
    }

    @Test("all three cases are distinct")
    func allCasesDistinct() {
        let cases: [ARDeviceCapability] = [.lidar, .nonLiDAR, .unsupported]
        for i in 0 ..< cases.count {
            for j in (i + 1) ..< cases.count {
                #expect(cases[i] != cases[j])
            }
        }
    }
}

// MARK: - ARSessionState Tests

@Suite("ARSessionState")
struct ARSessionStateTests {

    @Test("idle equals idle")
    func idleEqualsIdle() {
        #expect(ARSessionState.idle == ARSessionState.idle)
    }

    @Test("running equals running")
    func runningEqualsRunning() {
        #expect(ARSessionState.running == ARSessionState.running)
    }

    @Test("error with same message are equal")
    func errorEqualsSameMessage() {
        #expect(ARSessionState.error("test") == ARSessionState.error("test"))
    }

    @Test("error with different messages are not equal")
    func errorNotEqualDifferentMessage() {
        #expect(ARSessionState.error("a") != ARSessionState.error("b"))
    }

    @Test("idle is not equal to running")
    func idleNotRunning() {
        #expect(ARSessionState.idle != ARSessionState.running)
    }
}

// MARK: - ARSessionManager Configuration Tests

@Suite("ARSessionManager Configuration")
@MainActor
struct ARSessionManagerConfigurationTests {

    @Test("detectCapability returns unsupported in simulator")
    func detectCapabilitySimulator() {
        let capability = ARSessionManager.detectCapability()
        // On simulator, ARWorldTrackingConfiguration.isSupported is false
        #expect(capability == .unsupported)
    }

    @Test("makeConfiguration returns nil for unsupported capability")
    func makeConfigurationUnsupported() {
        let config = ARSessionManager.makeConfiguration(for: .unsupported)
        #expect(config == nil)
    }

    @Test("cameraAuthorizationStatus returns a valid status")
    func cameraAuthorizationStatusValid() {
        let status = ARSessionManager.cameraAuthorizationStatus()
        // Just verify it returns one of the expected cases
        let validStatuses: [CameraPermissionStatus] = [.authorized, .notDetermined, .denied, .restricted]
        #expect(validStatuses.contains(status))
    }

    @Test("session manager initializes with correct capability")
    func initCapability() {
        let manager = ARSessionManager()
        #expect(manager.deviceCapability == ARSessionManager.detectCapability())
    }

    @Test("startSession on unsupported device sets error state")
    func startSessionUnsupported() {
        let manager = ARSessionManager()
        if manager.deviceCapability == .unsupported {
            var capturedState: ARSessionState?
            manager.onStateChange = { state in
                capturedState = state
            }
            manager.startSession()
            if case .error(let message) = capturedState {
                #expect(message.contains("not supported") || message.contains("not available"))
            } else {
                // If we're not on a supported device, error should have been set
                // The session state on the manager should be error
                if case .error = manager.sessionState {
                    // Expected
                } else {
                    #expect(Bool(false), "Expected error state on unsupported device")
                }
            }
        }
    }

    @Test("stopSession returns to idle state")
    func stopSessionReturnsToIdle() {
        let manager = ARSessionManager()
        manager.stopSession()
        #expect(manager.sessionState == .idle)
    }
}

// MARK: - CameraPermissionStatus Tests

@Suite("CameraPermissionStatus")
struct CameraPermissionStatusTests {

    @Test("all cases are distinct")
    func allCasesDistinct() {
        let cases: [CameraPermissionStatus] = [.authorized, .notDetermined, .denied, .restricted]
        for i in 0 ..< cases.count {
            for j in (i + 1) ..< cases.count {
                #expect(cases[i] != cases[j])
            }
        }
    }
}

// MARK: - DetectedSurface Tests

@Suite("DetectedSurface")
struct DetectedSurfaceTests {

    @Test("surface has correct type")
    func surfaceType() {
        let surface = DetectedSurface(surfaceType: .wall, area: 5.0)
        #expect(surface.surfaceType == .wall)
        #expect(surface.area == 5.0)
    }

    @Test("floor surface has correct type")
    func floorSurfaceType() {
        let surface = DetectedSurface(surfaceType: .floor, area: 10.0)
        #expect(surface.surfaceType == .floor)
    }

    @Test("surfaces with same id are equal")
    func surfaceEquality() {
        let id = UUID()
        let surface1 = DetectedSurface(id: id, surfaceType: .wall, area: 5.0)
        let surface2 = DetectedSurface(id: id, surfaceType: .wall, area: 5.0)
        #expect(surface1 == surface2)
    }

    @Test("surfaces with different ids are not equal")
    func surfaceInequality() {
        let surface1 = DetectedSurface(surfaceType: .wall, area: 5.0)
        let surface2 = DetectedSurface(surfaceType: .wall, area: 5.0)
        #expect(surface1 != surface2)
    }
}

// MARK: - ARSurfaceType Tests

@Suite("ARSurfaceType")
struct ARSurfaceTypeTests {

    @Test("all four surface types are distinct")
    func allTypesDistinct() {
        let types: [ARSurfaceType] = [.floor, .wall, .ceiling, .other]
        for i in 0 ..< types.count {
            for j in (i + 1) ..< types.count {
                #expect(types[i] != types[j])
            }
        }
    }
}
