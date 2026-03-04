import AppKit
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Test Helpers

/// Creates a minimal valid PNG image data for testing.
private func makeTestPNGData(width: Int = 100, height: Int = 80) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImage = context.makeImage()
    else {
        return Data()
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:]) ?? Data()
}

/// Writes test PNG data to a temporary file and returns the URL.
private func makeTestPNGFile(name: String = "test_floorplan.png", width: Int = 100, height: Int = 80) -> URL {
    let data = makeTestPNGData(width: width, height: height)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

/// Writes test data to a temporary file with the given extension.
private func makeTestFile(name: String, data: Data = Data([0x00, 0x01, 0x02])) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

// MARK: - HeatmapSurveyViewModel Tests

@Suite("HeatmapSurveyViewModel")
@MainActor
struct HeatmapSurveyViewModelTests {

    // MARK: - Initial State

    @Test func initialStateHasNoFloorPlan() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.hasFloorPlan == false)
        #expect(vm.floorPlanImage == nil)
        #expect(vm.importResult == nil)
        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
        #expect(vm.project == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.showingError == false)
    }

    // MARK: - Floor Plan Import

    @Test func loadFloorPlanFromPNG() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 200, height: 150)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == true)
        #expect(vm.floorPlanImage != nil)
        #expect(vm.importResult != nil)
        #expect(vm.importResult?.pixelWidth == 200)
        #expect(vm.importResult?.pixelHeight == 150)
        #expect(vm.project != nil)
        #expect(vm.project?.floorPlan.pixelWidth == 200)
        #expect(vm.project?.floorPlan.pixelHeight == 150)
    }

    @Test func loadFloorPlanFromJPEG() throws {
        let vm = HeatmapSurveyViewModel()
        // Create JPEG data from a CGImage
        let pngData = makeTestPNGData(width: 120, height: 90)
        let image = try #require(NSImage(data: pngData))
        let tiffData = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiffData))
        let jpegData = try #require(rep.representation(using: .jpeg, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.jpg")
        try jpegData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == true)
        #expect(vm.importResult != nil)
    }

    @Test func loadFloorPlanUnsupportedFormatShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestFile(name: "test.bmp")
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == false)
        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("bmp") == true)
    }

    @Test func loadFloorPlanResetsCalibration() {
        let vm = HeatmapSurveyViewModel()
        let url1 = makeTestPNGFile(name: "first.png")
        defer { try? FileManager.default.removeItem(at: url1) }
        vm.loadFloorPlan(from: url1)

        // Simulate calibration
        vm.calibrationDistance = "10"
        vm.applyCalibration()
        #expect(vm.isCalibrated == true)

        // Import new floor plan
        let url2 = makeTestPNGFile(name: "second.png", width: 300, height: 200)
        defer { try? FileManager.default.removeItem(at: url2) }
        vm.loadFloorPlan(from: url2)

        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
    }

    @Test func loadFloorPlanCreatesProjectWithCorrectName() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "Office_Plan.png")
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.project?.name == "Office_Plan")
    }

    @Test func loadFloorPlanSetsImportedOrigin() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        if case .imported(let sourceURL) = vm.project?.floorPlan.origin {
            #expect(sourceURL == url)
        } else {
            Issue.record("Expected .imported origin")
        }
    }

    // MARK: - Calibration

    @Test func startCalibrationPresentsSheet() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.startCalibration()

        #expect(vm.isCalibrationSheetPresented == true)
    }

    @Test func startCalibrationWithoutFloorPlanDoesNothing() {
        let vm = HeatmapSurveyViewModel()

        vm.startCalibration()

        #expect(vm.isCalibrationSheetPresented == false)
    }

    @Test func applyCalibrationComputesPixelsPerMeter() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        // Set calibration: points are at 25% and 75% width, same height
        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 1000 pixels across / 10 meters = 100 px/m
        #expect(vm.pixelsPerMeter == 100.0)
    }

    @Test func applyCalibrationWithFeetConverts() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "32.8084" // ~10 meters in feet
        vm.calibrationUnit = .feet

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 1000 pixels / (32.8084 * 0.3048) meters ≈ 100 px/m
        #expect(abs(vm.pixelsPerMeter - 100.0) < 1.0)
    }

    @Test func applyCalibrationUpdatesProjectDimensions() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.project?.floorPlan.widthMeters == 10.0)
        #expect(vm.project?.floorPlan.heightMeters == 5.0)
    }

    @Test func applyCalibrationStoresCalibrationPoints() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.2, y: 0.3)
        vm.calibrationPoint2 = CGPoint(x: 0.8, y: 0.7)
        vm.calibrationDistance = "5"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        let calibPoints = vm.project?.floorPlan.calibrationPoints
        #expect(calibPoints != nil)
        #expect(calibPoints?.count == 2)
        // Point 1: 0.2 * 1000 = 200, 0.3 * 500 = 150
        #expect(calibPoints?[0].pixelX == 200)
        #expect(calibPoints?[0].pixelY == 150)
    }

    @Test func applyCalibrationShowsScaleBar() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.scaleBarLabel.isEmpty == false)
        #expect(vm.scaleBarFraction > 0)
    }

    @Test func applyCalibrationInvalidDistanceShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationDistance = "abc"

        vm.applyCalibration()

        #expect(vm.isCalibrated == false)
        #expect(vm.showingError == true)
    }

    @Test func applyCalibrationZeroDistanceShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationDistance = "0"

        vm.applyCalibration()

        #expect(vm.isCalibrated == false)
        #expect(vm.showingError == true)
    }

    @Test func skipCalibrationDismissesSheet() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)
        vm.startCalibration()
        #expect(vm.isCalibrationSheetPresented == true)

        vm.skipCalibration()

        #expect(vm.isCalibrationSheetPresented == false)
        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
    }

    @Test func skipCalibrationClearsScaleBar() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.skipCalibration()

        #expect(vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction == 0)
    }

    // MARK: - Error Handling

    @Test func showErrorSetsMessageAndFlag() {
        let vm = HeatmapSurveyViewModel()

        vm.showError("Something went wrong")

        #expect(vm.errorMessage == "Something went wrong")
        #expect(vm.showingError == true)
    }

    @Test func clearErrorResetsState() {
        let vm = HeatmapSurveyViewModel()
        vm.showError("Error")

        vm.clearError()

        #expect(vm.errorMessage == nil)
        #expect(vm.showingError == false)
    }

    // MARK: - CalibrationUnit

    @Test func calibrationUnitMetersConversion() {
        #expect(CalibrationUnit.meters.toMeters == 1.0)
    }

    @Test func calibrationUnitFeetConversion() {
        #expect(CalibrationUnit.feet.toMeters == 0.3048)
    }
}

// MARK: - FloorPlanImporter Tests

@Suite("FloorPlanImporter")
struct FloorPlanImporterTests {

    @Test func importPNGSucceeds() throws {
        let url = makeTestPNGFile(width: 200, height: 150)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        #expect(result.pixelWidth == 200)
        #expect(result.pixelHeight == 150)
        #expect(result.imageData.isEmpty == false)
        #expect(result.sourceURL == url)
    }

    @Test func importUnsupportedFormatThrows() {
        let url = makeTestFile(name: "test.svg")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: FloorPlanImportError.self) {
            try FloorPlanImporter.importFloorPlan(from: url)
        }
    }

    @Test func isSupportedReturnsTrueForValidExtensions() {
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.png")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.jpg")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.jpeg")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.heic")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.pdf")) == true)
    }

    @Test func isSupportedReturnsFalseForInvalidExtensions() {
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.bmp")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.svg")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.txt")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.gif")) == false)
    }

    @Test func largeImageDownsampled() throws {
        // Create a large image (5000x5000)
        let url = makeTestPNGFile(name: "large.png", width: 5000, height: 5000)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        // Should be downsampled to 4096 max dimension
        #expect(result.pixelWidth <= FloorPlanImporter.maxPixelDimension)
        #expect(result.pixelHeight <= FloorPlanImporter.maxPixelDimension)
    }

    @Test func smallImageNotDownsampled() throws {
        let url = makeTestPNGFile(name: "small.png", width: 800, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        #expect(result.pixelWidth == 800)
        #expect(result.pixelHeight == 600)
    }

    @Test func importCorruptFileThrows() {
        let url = makeTestFile(name: "corrupt.png", data: Data([0xFF, 0xFE, 0xFD]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: FloorPlanImportError.self) {
            try FloorPlanImporter.importFloorPlan(from: url)
        }
    }
}
