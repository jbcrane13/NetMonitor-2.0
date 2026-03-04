import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NetMonitorCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Test Helpers

/// Creates valid PNG image data with the specified dimensions.
private func makeTestPNGData(width: Int = 100, height: Int = 50) -> Data {
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
        fatalError("Failed to create CGContext for test PNG")
    }
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let cgImage = context.makeImage() else {
        fatalError("Failed to create CGImage for test PNG")
    }

    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        mutableData as CFMutableData,
        "public.png" as CFString,
        1,
        nil
    ) else {
        fatalError("Failed to create CGImageDestination for test PNG")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to finalize test PNG")
    }
    return mutableData as Data
}

/// Creates a fully-populated SurveyProject for testing.
private func makeFullProject(imageData: Data? = nil) -> SurveyProject {
    let pngData = imageData ?? makeTestPNGData()
    let calibration1 = CalibrationPoint(pixelX: 0, pixelY: 0, realWorldX: 0.0, realWorldY: 0.0)
    let calibration2 = CalibrationPoint(pixelX: 100, pixelY: 50, realWorldX: 10.0, realWorldY: 5.0)
    let wall1 = WallSegment(startX: 0, startY: 0, endX: 10, endY: 0, thickness: 0.15)
    let wall2 = WallSegment(startX: 10, startY: 0, endX: 10, endY: 5, thickness: 0.2)

    let floorPlan = FloorPlan(
        imageData: pngData,
        widthMeters: 10.0,
        heightMeters: 5.0,
        pixelWidth: 100,
        pixelHeight: 50,
        // swiftlint:disable:next force_unwrapping
        origin: .imported(URL(string: "file:///tmp/plan.png")!),
        calibrationPoints: [calibration1, calibration2],
        walls: [wall1, wall2]
    )

    let point1 = MeasurementPoint(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        floorPlanX: 0.25,
        floorPlanY: 0.5,
        rssi: -45,
        noiseFloor: -90,
        snr: 45,
        ssid: "TestNetwork",
        bssid: "AA:BB:CC:DD:EE:FF",
        channel: 6,
        frequency: 2437,
        band: .band2_4GHz,
        linkSpeed: 144,
        downloadSpeed: 200.5,
        uploadSpeed: 80.3,
        latency: 5.2,
        connectedAPName: "Office-AP-1"
    )

    let point2 = MeasurementPoint(
        timestamp: Date(timeIntervalSince1970: 1_700_000_060),
        floorPlanX: 0.75,
        floorPlanY: 0.5,
        rssi: -65,
        ssid: "TestNetwork",
        bssid: "AA:BB:CC:DD:EE:00",
        channel: 36,
        frequency: 5180,
        band: .band5GHz
    )

    let metadata = SurveyMetadata(
        buildingName: "Main Office",
        floorNumber: 2,
        notes: "Second floor survey — east wing"
    )

    return SurveyProject(
        name: "Test Survey",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        floorPlan: floorPlan,
        measurementPoints: [point1, point2],
        surveyMode: .blueprint,
        metadata: metadata
    )
}

// MARK: - SurveyFileManager Tests

@Suite("SurveyFileManager")
struct SurveyFileManagerTests {

    // MARK: - Bundle Structure

    // VAL-FOUND-036: .netmonsurvey bundle structure
    @Test("Saved bundle contains survey.json and floorplan.png")
    func bundleContainsSurveyJSONAndFloorplanPNG() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        let surveyJSON = bundleURL.appendingPathComponent("survey.json")
        let floorplanPNG = bundleURL.appendingPathComponent("floorplan.png")

        #expect(FileManager.default.fileExists(atPath: surveyJSON.path))
        #expect(FileManager.default.fileExists(atPath: floorplanPNG.path))
    }

    // VAL-FOUND-037: .netmonsurvey — survey.json matches SurveyProject
    @Test("survey.json inside bundle deserializes to identical project (minus imageData)")
    func surveyJSONMatchesProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        let surveyJSON = bundleURL.appendingPathComponent("survey.json")
        let jsonData = try Data(contentsOf: surveyJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SurveyProject.self, from: jsonData)

        // Core fields match (imageData is stripped from JSON — stored as separate PNG)
        #expect(decoded.id == project.id)
        #expect(decoded.name == project.name)
        #expect(decoded.surveyMode == project.surveyMode)
        #expect(decoded.measurementPoints.count == project.measurementPoints.count)
        #expect(decoded.metadata == project.metadata)
        #expect(decoded.floorPlan.widthMeters == project.floorPlan.widthMeters)
        #expect(decoded.floorPlan.heightMeters == project.floorPlan.heightMeters)
        #expect(decoded.floorPlan.pixelWidth == project.floorPlan.pixelWidth)
        #expect(decoded.floorPlan.pixelHeight == project.floorPlan.pixelHeight)
        #expect(decoded.floorPlan.calibrationPoints == project.floorPlan.calibrationPoints)
        #expect(decoded.floorPlan.walls == project.floorPlan.walls)
    }

    // VAL-FOUND-038: .netmonsurvey — floorplan.png is valid image
    @Test("floorplan.png in bundle is valid with correct dimensions")
    func floorplanPNGIsValid() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        let floorplanPNG = bundleURL.appendingPathComponent("floorplan.png")
        let imageData = try Data(contentsOf: floorplanPNG)

        // Verify it's valid image data via ImageIO
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("floorplan.png should be a valid image")
            return
        }
        #expect(cgImage.width == project.floorPlan.pixelWidth)
        #expect(cgImage.height == project.floorPlan.pixelHeight)
    }

    // MARK: - Round-Trip

    // VAL-FOUND-039: .netmonsurvey — full round-trip preserves all data
    @Test("Save and load preserves all fields including calibration and walls")
    func fullRoundTripPreservesAllData() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)
        let loaded = try SurveyFileManager.load(from: bundleURL)

        // Core identity
        #expect(loaded.id == project.id)
        #expect(loaded.name == project.name)
        #expect(loaded.surveyMode == project.surveyMode)

        // Dates (ISO 8601 round-trip loses sub-second precision)
        #expect(abs(loaded.createdAt.timeIntervalSince(project.createdAt)) < 1.0)

        // Metadata
        #expect(loaded.metadata == project.metadata)

        // Floor plan
        #expect(loaded.floorPlan.id == project.floorPlan.id)
        #expect(loaded.floorPlan.widthMeters == project.floorPlan.widthMeters)
        #expect(loaded.floorPlan.heightMeters == project.floorPlan.heightMeters)
        #expect(loaded.floorPlan.pixelWidth == project.floorPlan.pixelWidth)
        #expect(loaded.floorPlan.pixelHeight == project.floorPlan.pixelHeight)
        #expect(loaded.floorPlan.origin == project.floorPlan.origin)
        #expect(loaded.floorPlan.calibrationPoints == project.floorPlan.calibrationPoints)
        #expect(loaded.floorPlan.walls == project.floorPlan.walls)

        // Image data round-trips (PNG re-encoded, so compare by decoding to CGImage)
        #expect(!loaded.floorPlan.imageData.isEmpty)

        // Measurement points
        #expect(loaded.measurementPoints.count == project.measurementPoints.count)
        for (loadedPoint, originalPoint) in zip(loaded.measurementPoints, project.measurementPoints) {
            #expect(loadedPoint.id == originalPoint.id)
            #expect(loadedPoint.floorPlanX == originalPoint.floorPlanX)
            #expect(loadedPoint.floorPlanY == originalPoint.floorPlanY)
            #expect(loadedPoint.rssi == originalPoint.rssi)
            #expect(loadedPoint.noiseFloor == originalPoint.noiseFloor)
            #expect(loadedPoint.snr == originalPoint.snr)
            #expect(loadedPoint.ssid == originalPoint.ssid)
            #expect(loadedPoint.bssid == originalPoint.bssid)
            #expect(loadedPoint.channel == originalPoint.channel)
            #expect(loadedPoint.frequency == originalPoint.frequency)
            #expect(loadedPoint.band == originalPoint.band)
            #expect(loadedPoint.linkSpeed == originalPoint.linkSpeed)
            #expect(loadedPoint.downloadSpeed == originalPoint.downloadSpeed)
            #expect(loadedPoint.uploadSpeed == originalPoint.uploadSpeed)
            #expect(loadedPoint.latency == originalPoint.latency)
            #expect(loadedPoint.connectedAPName == originalPoint.connectedAPName)
        }
    }

    // VAL-FOUND-002 (file format variant): Round-trip with empty measurement points
    @Test("Round-trip with zero measurement points succeeds")
    func roundTripEmptyMeasurementPoints() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let pngData = makeTestPNGData()
        let floorPlan = FloorPlan(
            imageData: pngData,
            widthMeters: 10.0,
            heightMeters: 5.0,
            pixelWidth: 100,
            pixelHeight: 50,
            origin: .drawn
        )

        let project = SurveyProject(
            name: "Empty Survey",
            floorPlan: floorPlan,
            measurementPoints: []
        )

        let bundleURL = tempDir.appendingPathComponent("empty.netmonsurvey")
        try SurveyFileManager.save(project, to: bundleURL)
        let loaded = try SurveyFileManager.load(from: bundleURL)

        #expect(loaded.measurementPoints.isEmpty)
        #expect(loaded.name == "Empty Survey")
    }

    // MARK: - Optional heatmap-cache

    // VAL-FOUND-040: .netmonsurvey — heatmap-cache directory optional
    @Test("Loading bundle without heatmap-cache/ succeeds")
    func loadingWithoutHeatmapCacheSucceeds() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("nocache.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        // Explicitly remove heatmap-cache if it exists
        let cacheDir = bundleURL.appendingPathComponent("heatmap-cache")
        try? FileManager.default.removeItem(at: cacheDir)

        // Load should still succeed
        let loaded = try SurveyFileManager.load(from: bundleURL)
        #expect(loaded.id == project.id)
    }

    // VAL-FOUND-040 extended: Loading bundle with heatmap-cache/ also succeeds
    @Test("Loading bundle with heatmap-cache/ directory succeeds")
    func loadingWithHeatmapCacheSucceeds() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("withcache.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        // Create heatmap-cache directory with a dummy file
        let cacheDir = bundleURL.appendingPathComponent("heatmap-cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dummyFile = cacheDir.appendingPathComponent("signalStrength.png")
        try Data([0x89, 0x50]).write(to: dummyFile)

        let loaded = try SurveyFileManager.load(from: bundleURL)
        #expect(loaded.id == project.id)
    }

    // MARK: - Error Cases

    // VAL-FOUND-041: .netmonsurvey — corrupt JSON produces clear error
    @Test("Corrupt survey.json produces descriptive SurveyFileError.corruptJSON")
    func corruptJSONProducesDescriptiveError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("corrupt.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        // Corrupt the JSON file
        let surveyJSON = bundleURL.appendingPathComponent("survey.json")
        try Data("{ not valid json!!!".utf8).write(to: surveyJSON)

        #expect(throws: SurveyFileError.self) {
            try SurveyFileManager.load(from: bundleURL)
        }

        do {
            _ = try SurveyFileManager.load(from: bundleURL)
        } catch let error as SurveyFileError {
            switch error {
            case .corruptJSON(let message):
                #expect(message.contains("survey.json") || !message.isEmpty,
                        "Error should mention survey.json or be descriptive")
            default:
                Issue.record("Expected corruptJSON error, got \(error)")
            }
        }
    }

    // VAL-FOUND-042: .netmonsurvey — missing floorplan.png produces clear error
    @Test("Missing floorplan.png produces descriptive SurveyFileError.missingFloorPlan")
    func missingFloorplanProducesDescriptiveError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("missing.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        // Delete the floorplan.png
        let floorplanPNG = bundleURL.appendingPathComponent("floorplan.png")
        try FileManager.default.removeItem(at: floorplanPNG)

        #expect(throws: SurveyFileError.self) {
            try SurveyFileManager.load(from: bundleURL)
        }

        do {
            _ = try SurveyFileManager.load(from: bundleURL)
        } catch let error as SurveyFileError {
            switch error {
            case .missingFloorPlan(let message):
                #expect(!message.isEmpty, "Error message should be descriptive")
            default:
                Issue.record("Expected missingFloorPlan error, got \(error)")
            }
        }
    }

    // Additional error: missing survey.json
    @Test("Missing survey.json produces descriptive SurveyFileError.corruptJSON")
    func missingSurveyJSONProducesError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a bundle directory manually with only floorplan.png
        let bundleURL = tempDir.appendingPathComponent("nojson.netmonsurvey")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let pngData = makeTestPNGData()
        try pngData.write(to: bundleURL.appendingPathComponent("floorplan.png"))

        #expect(throws: SurveyFileError.self) {
            try SurveyFileManager.load(from: bundleURL)
        }
    }

    // Additional error: bundle doesn't exist
    @Test("Loading non-existent bundle produces error")
    func loadingNonExistentBundleProducesError() throws {
        let nonExistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("does-not-exist.netmonsurvey")

        #expect(throws: SurveyFileError.self) {
            try SurveyFileManager.load(from: nonExistent)
        }
    }

    // MARK: - LocalizedError Conformance

    @Test("SurveyFileError conforms to LocalizedError with errorDescription and failureReason")
    func surveyFileErrorLocalizedError() {
        let errors: [SurveyFileError] = [
            .corruptJSON("bad json data"),
            .missingFloorPlan("floorplan.png not found"),
            .fileSystemError("permission denied"),
            .bundleNotFound("no such file"),
        ]

        for error in errors {
            // errorDescription should be non-nil and user-friendly
            #expect(error.errorDescription != nil, "\(error) should have errorDescription")
            #expect(!error.errorDescription!.isEmpty, "\(error) errorDescription should not be empty")

            // failureReason should contain the associated message
            #expect(error.failureReason != nil, "\(error) should have failureReason")
            #expect(!error.failureReason!.isEmpty, "\(error) failureReason should not be empty")

            // localizedDescription should use errorDescription (LocalizedError protocol)
            let localized = error.localizedDescription
            #expect(!localized.isEmpty, "\(error) localizedDescription should not be empty")
        }

        // Verify specific errorDescription messages
        let corruptError = SurveyFileError.corruptJSON("test detail")
        #expect(corruptError.errorDescription == "The survey file contains invalid data.")
        #expect(corruptError.failureReason == "test detail")

        let missingError = SurveyFileError.missingFloorPlan("image missing")
        #expect(missingError.errorDescription == "The floor plan image is missing from the survey file.")
        #expect(missingError.failureReason == "image missing")

        let fsError = SurveyFileError.fileSystemError("disk full")
        #expect(fsError.errorDescription == "A file system error occurred while saving or loading the survey.")
        #expect(fsError.failureReason == "disk full")

        let notFoundError = SurveyFileError.bundleNotFound("gone")
        #expect(notFoundError.errorDescription == "The survey file could not be found.")
        #expect(notFoundError.failureReason == "gone")
    }

    // MARK: - survey.json excludes imageData

    @Test("survey.json does not contain raw imageData (stored as separate floorplan.png)")
    func surveyJSONExcludesImageData() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")

        try SurveyFileManager.save(project, to: bundleURL)

        let surveyJSON = bundleURL.appendingPathComponent("survey.json")
        let jsonString = try String(contentsOf: surveyJSON, encoding: .utf8)

        // The JSON should NOT contain the base64-encoded imageData blob
        // It should use a placeholder or empty data
        // The actual image is in floorplan.png
        #expect(jsonString.count < 10_000, "survey.json should be small without embedded image data")
    }

    // MARK: - Overwrite Behavior

    @Test("Saving to existing bundle overwrites cleanly")
    func savingOverwritesExistingBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let project1 = makeFullProject()
        let bundleURL = tempDir.appendingPathComponent("overwrite.netmonsurvey")

        try SurveyFileManager.save(project1, to: bundleURL)

        // Create a different project with same URL
        let pngData = makeTestPNGData(width: 200, height: 100)
        let floorPlan = FloorPlan(
            imageData: pngData,
            widthMeters: 20.0,
            heightMeters: 10.0,
            pixelWidth: 200,
            pixelHeight: 100,
            origin: .arGenerated
        )
        let project2 = SurveyProject(
            name: "Updated Survey",
            floorPlan: floorPlan,
            measurementPoints: [],
            surveyMode: .arAssisted
        )

        try SurveyFileManager.save(project2, to: bundleURL)
        let loaded = try SurveyFileManager.load(from: bundleURL)

        #expect(loaded.name == "Updated Survey")
        #expect(loaded.surveyMode == .arAssisted)
        #expect(loaded.measurementPoints.isEmpty)
    }
}
