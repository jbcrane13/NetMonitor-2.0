import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("FloorPlanImportViewModel")
@MainActor
struct FloorPlanImportViewModelTests {

    // MARK: - Helpers

    /// Creates a minimal valid PNG image data for testing.
    private func makeTestPNGData(width: Int = 200, height: Int = 150) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }

        // Fill with blue
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else { return Data() }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func makeVM() -> FloorPlanImportViewModel {
        FloorPlanImportViewModel()
    }

    // MARK: - Initial State

    @Test func initialStateIsEmpty() {
        let vm = makeVM()
        #expect(vm.projectName.isEmpty)
        #expect(!vm.hasFloorPlan)
        #expect(vm.floorPlanImage == nil)
        #expect(vm.importResult == nil)
        #expect(!vm.isImporting)
        #expect(vm.errorMessage == nil)
        #expect(!vm.showCalibrationSheet)
        #expect(!vm.isCalibrated)
        #expect(vm.pixelsPerMeter == 0)
        #expect(vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction == 0)
        #expect(!vm.isReadyToSurvey)
        #expect(vm.createdProject == nil)
    }

    // MARK: - Photo Library Import

    @Test func handlePhotoLibraryResultWithNilDataSetsError() async {
        let vm = makeVM()
        await vm.handlePhotoLibraryResult(nil)
        #expect(vm.errorMessage != nil)
        #expect(!vm.hasFloorPlan)
    }

    @Test func handlePhotoLibraryResultWithInvalidDataSetsError() async {
        let vm = makeVM()
        await vm.handlePhotoLibraryResult(Data("not an image".utf8))
        #expect(vm.errorMessage != nil)
        #expect(!vm.hasFloorPlan)
    }

    @Test func handlePhotoLibraryResultWithValidPNGSucceeds() async {
        let vm = makeVM()
        let pngData = makeTestPNGData()
        await vm.handlePhotoLibraryResult(pngData)
        #expect(vm.hasFloorPlan)
        #expect(vm.floorPlanImage != nil)
        #expect(vm.importResult != nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isImporting)
    }

    @Test func handlePhotoLibraryResultSetsCorrectDimensions() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 300, height: 200)
        await vm.handlePhotoLibraryResult(pngData)
        #expect(vm.importResult?.pixelWidth == 300)
        #expect(vm.importResult?.pixelHeight == 200)
    }

    // MARK: - Document Picker Import

    @Test func handleDocumentPickerResultWithValidFileSucceeds() async throws {
        let vm = makeVM()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloorPlanImportTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngData = makeTestPNGData()
        let fileURL = tempDir.appendingPathComponent("test.png")
        try pngData.write(to: fileURL)

        await vm.handleDocumentPickerResult(fileURL)
        #expect(vm.hasFloorPlan)
        #expect(vm.floorPlanImage != nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func handleDocumentPickerResultWithUnsupportedFormatSetsError() async throws {
        let vm = makeVM()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloorPlanImportTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.webp")
        try Data("data".utf8).write(to: fileURL)

        await vm.handleDocumentPickerResult(fileURL)
        #expect(!vm.hasFloorPlan)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("Unsupported") == true)
    }

    // MARK: - Calibration

    @Test func applyCalibrationWithValidDistanceSucceeds() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)

        vm.calibrationPoint1 = CGPoint(x: 0.1, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 0.6, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated)
        #expect(vm.pixelsPerMeter > 0)
        #expect(!vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction > 0)
        #expect(!vm.showCalibrationSheet)
    }

    @Test func applyCalibrationWithEmptyDistanceSetsError() async {
        let vm = makeVM()
        let pngData = makeTestPNGData()
        await vm.handlePhotoLibraryResult(pngData)

        vm.calibrationDistance = ""
        vm.applyCalibration()

        #expect(!vm.isCalibrated)
        #expect(vm.errorMessage != nil)
    }

    @Test func applyCalibrationWithZeroDistanceSetsError() async {
        let vm = makeVM()
        let pngData = makeTestPNGData()
        await vm.handlePhotoLibraryResult(pngData)

        vm.calibrationDistance = "0"
        vm.applyCalibration()

        #expect(!vm.isCalibrated)
        #expect(vm.errorMessage != nil)
    }

    @Test func applyCalibrationFeetConversion() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)

        vm.calibrationPoint1 = CGPoint(x: 0.1, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 0.6, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .feet

        vm.applyCalibration()

        #expect(vm.isCalibrated)
        #expect(vm.pixelsPerMeter > 0)
        // Feet-based calibration should result in higher pixels per meter
        // (10 feet = ~3.048 meters, so PPM is larger than meters)
        #expect(vm.scaleBarLabel.contains("ft"))
    }

    @Test func skipCalibrationClearsState() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)

        // First apply calibration
        vm.calibrationPoint1 = CGPoint(x: 0.1, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 0.6, y: 0.5)
        vm.calibrationDistance = "10"
        vm.applyCalibration()
        #expect(vm.isCalibrated)

        // Now skip
        vm.skipCalibration()
        #expect(!vm.isCalibrated)
        #expect(vm.pixelsPerMeter == 0)
        #expect(vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction == 0)
        #expect(!vm.showCalibrationSheet)
    }

    @Test func beginCalibrationResetsMarkersAndShowsSheet() {
        let vm = makeVM()
        vm.calibrationPoint1 = CGPoint(x: 0.9, y: 0.9)
        vm.calibrationPoint2 = CGPoint(x: 0.1, y: 0.1)
        vm.calibrationDistance = "5"

        vm.beginCalibration()

        #expect(vm.showCalibrationSheet)
        #expect(vm.calibrationPoint1 == CGPoint(x: 0.25, y: 0.5))
        #expect(vm.calibrationPoint2 == CGPoint(x: 0.75, y: 0.5))
        #expect(vm.calibrationDistance.isEmpty)
    }

    // MARK: - CalibrationUnit

    @Test func calibrationUnitMetersConversion() {
        #expect(CalibrationUnit.meters.toMeters == 1.0)
    }

    @Test func calibrationUnitFeetConversion() {
        #expect(CalibrationUnit.feet.toMeters == 0.3048)
    }

    @Test func calibrationUnitAllCases() {
        #expect(CalibrationUnit.allCases.count == 2)
        #expect(CalibrationUnit.allCases.contains(.meters))
        #expect(CalibrationUnit.allCases.contains(.feet))
    }

    // MARK: - Create Project

    @Test func createProjectWithoutFloorPlanDoesNothing() {
        let vm = makeVM()
        vm.projectName = "Test"
        vm.createProject()
        #expect(vm.createdProject == nil)
        #expect(!vm.isReadyToSurvey)
    }

    @Test func createProjectWithEmptyNameSetsError() async {
        let vm = makeVM()
        let pngData = makeTestPNGData()
        await vm.handlePhotoLibraryResult(pngData)
        vm.projectName = "   "

        vm.createProject()

        #expect(vm.createdProject == nil)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("name") == true)
    }

    @Test func createProjectWithValidDataSucceeds() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)
        vm.projectName = "Test Survey"

        vm.createProject()

        #expect(vm.createdProject != nil)
        #expect(vm.isReadyToSurvey)
        #expect(vm.createdProject?.name == "Test Survey")
        #expect(vm.createdProject?.surveyMode == .blueprint)
        #expect(vm.createdProject?.measurementPoints.isEmpty == true)
    }

    @Test func createProjectWithCalibrationSetsFloorPlanDimensions() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)
        vm.projectName = "Calibrated Survey"

        // Apply calibration
        vm.calibrationPoint1 = CGPoint(x: 0.1, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 0.6, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters
        vm.applyCalibration()

        vm.createProject()

        #expect(vm.createdProject != nil)
        let floorPlan = vm.createdProject?.floorPlan
        #expect(floorPlan != nil)
        #expect(floorPlan?.widthMeters ?? 0 > 0)
        #expect(floorPlan?.heightMeters ?? 0 > 0)
        #expect(floorPlan?.calibrationPoints?.count == 2)
    }

    @Test func createProjectWithoutCalibrationHasZeroDimensions() async {
        let vm = makeVM()
        let pngData = makeTestPNGData(width: 400, height: 300)
        await vm.handlePhotoLibraryResult(pngData)
        vm.projectName = "Uncalibrated"

        vm.createProject()

        let floorPlan = vm.createdProject?.floorPlan
        #expect(floorPlan?.widthMeters == 0)
        #expect(floorPlan?.heightMeters == 0)
        #expect(floorPlan?.calibrationPoints == nil)
    }

    // MARK: - FloorPlanImporter Tests

    @Test func floorPlanImporterFromDataWithValidPNG() async throws {
        let pngData = makeTestPNGData(width: 100, height: 80)
        let result = try await FloorPlanImporter.importFloorPlan(from: pngData)
        #expect(result.pixelWidth == 100)
        #expect(result.pixelHeight == 80)
        #expect(!result.imageData.isEmpty)
        #expect(result.sourceURL == nil)
    }

    @Test func floorPlanImporterFromDataWithInvalidDataThrows() async {
        do {
            _ = try await FloorPlanImporter.importFloorPlan(from: Data("not image".utf8))
            Issue.record("Expected FloorPlanImportError to be thrown")
        } catch is FloorPlanImportError {
            // Expected
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func floorPlanImporterFromURLWithValidPNG() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloorPlanImporterTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngData = makeTestPNGData(width: 250, height: 200)
        let fileURL = tempDir.appendingPathComponent("floor.png")
        try pngData.write(to: fileURL)

        let result = try await FloorPlanImporter.importFloorPlan(from: fileURL)
        #expect(result.pixelWidth == 250)
        #expect(result.pixelHeight == 200)
        #expect(result.sourceURL == fileURL)
    }

    @Test func floorPlanImporterUnsupportedExtensionThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloorPlanImporterTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.bmp")
        try Data("data".utf8).write(to: fileURL)

        do {
            _ = try await FloorPlanImporter.importFloorPlan(from: fileURL)
            Issue.record("Expected FloorPlanImportError to be thrown")
        } catch is FloorPlanImportError {
            // Expected
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
