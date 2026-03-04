import AppKit
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Calibration Accuracy Tests

/// Tests verifying calibration accuracy with landscape, portrait, and square floor plans.
@Suite("CalibrationAccuracy")
@MainActor
struct CalibrationAccuracyTests {

    @Test func calibrationAccurateForLandscapeFloorPlan() {
        // 2000x500 landscape floor plan
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "calib_landscape.png", width: 2000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        // Calibrate: full width horizontal line = 20 meters
        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "20"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 2000 pixels / 20 meters = 100 px/m
        #expect(abs(vm.pixelsPerMeter - 100.0) < 0.01)
        // Width: 2000 / 100 = 20m, Height: 500 / 100 = 5m
        #expect(abs((vm.project?.floorPlan.widthMeters ?? 0) - 20.0) < 0.01)
        #expect(abs((vm.project?.floorPlan.heightMeters ?? 0) - 5.0) < 0.01)
        #expect(vm.scaleBarLabel.isEmpty == false)
        #expect(vm.scaleBarFraction > 0)
    }

    @Test func calibrationAccurateForPortraitFloorPlan() {
        // 500x2000 portrait floor plan
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "calib_portrait.png", width: 500, height: 2000)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        // Calibrate: full height vertical line = 20 meters
        vm.calibrationPoint1 = CGPoint(x: 0.5, y: 0.0)
        vm.calibrationPoint2 = CGPoint(x: 0.5, y: 1.0)
        vm.calibrationDistance = "20"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 2000 pixels / 20 meters = 100 px/m
        #expect(abs(vm.pixelsPerMeter - 100.0) < 0.01)
        // Width: 500 / 100 = 5m, Height: 2000 / 100 = 20m
        #expect(abs((vm.project?.floorPlan.widthMeters ?? 0) - 5.0) < 0.01)
        #expect(abs((vm.project?.floorPlan.heightMeters ?? 0) - 20.0) < 0.01)
        #expect(vm.scaleBarLabel.isEmpty == false)
        #expect(vm.scaleBarFraction > 0)
    }

    @Test func calibrationAccurateForSquareFloorPlan() {
        // 1000x1000 square floor plan
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "calib_square.png", width: 1000, height: 1000)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        // Calibrate: diagonal = 14.142 meters (10*sqrt(2))
        vm.calibrationPoint1 = .zero
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 1.0)
        vm.calibrationDistance = "14.142"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // Diagonal pixels = sqrt(1000^2 + 1000^2) ≈ 1414.2
        // px/m = 1414.2 / 14.142 ≈ 100
        #expect(abs(vm.pixelsPerMeter - 100.0) < 0.5)
        // Both dimensions should be ~10m
        #expect(abs((vm.project?.floorPlan.widthMeters ?? 0) - 10.0) < 0.1)
        #expect(abs((vm.project?.floorPlan.heightMeters ?? 0) - 10.0) < 0.1)
    }

    @Test func scaleBarCorrectAfterCalibrationOnLandscapeImage() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "sb_landscape.png", width: 2000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "20"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        // Scale bar should represent a reasonable fraction of the floor plan width
        #expect(vm.scaleBarFraction > 0)
        #expect(vm.scaleBarFraction < 0.5) // Should be less than half
        #expect(vm.scaleBarLabel.contains("m"))
    }

    @Test func scaleBarCorrectAfterCalibrationOnPortraitImage() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "sb_portrait.png", width: 500, height: 2000)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.5, y: 0.0)
        vm.calibrationPoint2 = CGPoint(x: 0.5, y: 1.0)
        vm.calibrationDistance = "20"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        #expect(vm.scaleBarFraction > 0)
        #expect(vm.scaleBarFraction < 0.5)
        #expect(vm.scaleBarLabel.contains("m"))
    }

    @Test func calibrationPointsStoredCorrectlyForLandscape() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "cp_landscape.png", width: 2000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.1, y: 0.4)
        vm.calibrationPoint2 = CGPoint(x: 0.9, y: 0.6)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        let calibPoints = vm.project?.floorPlan.calibrationPoints
        #expect(calibPoints?.count == 2)
        // Point 1: 0.1 * 2000 = 200, 0.4 * 500 = 200
        #expect(abs((calibPoints?[0].pixelX ?? 0) - 200) < 0.01)
        #expect(abs((calibPoints?[0].pixelY ?? 0) - 200) < 0.01)
        // Point 2: 0.9 * 2000 = 1800, 0.6 * 500 = 300
        #expect(abs((calibPoints?[1].pixelX ?? 0) - 1800) < 0.01)
        #expect(abs((calibPoints?[1].pixelY ?? 0) - 300) < 0.01)
    }

    @Test func calibrationPointsStoredCorrectlyForPortrait() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "cp_portrait.png", width: 500, height: 2000)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.2, y: 0.1)
        vm.calibrationPoint2 = CGPoint(x: 0.8, y: 0.9)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        let calibPoints = vm.project?.floorPlan.calibrationPoints
        #expect(calibPoints?.count == 2)
        // Point 1: 0.2 * 500 = 100, 0.1 * 2000 = 200
        #expect(abs((calibPoints?[0].pixelX ?? 0) - 100) < 0.01)
        #expect(abs((calibPoints?[0].pixelY ?? 0) - 200) < 0.01)
        // Point 2: 0.8 * 500 = 400, 0.9 * 2000 = 1800
        #expect(abs((calibPoints?[1].pixelX ?? 0) - 400) < 0.01)
        #expect(abs((calibPoints?[1].pixelY ?? 0) - 1800) < 0.01)
    }

    @Test func dimensionRatioPreservedForWideFloorPlan() {
        // 1600x900 (16:9) floor plan
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "wide.png", width: 1600, height: 900)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "16"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        let widthMeters = vm.project?.floorPlan.widthMeters ?? 0
        let heightMeters = vm.project?.floorPlan.heightMeters ?? 0

        // Ratio of real-world dimensions should match pixel ratio
        let realRatio = widthMeters / heightMeters
        let pixelRatio = 1600.0 / 900.0
        #expect(abs(realRatio - pixelRatio) < 0.001)
    }
}
