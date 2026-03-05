import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Test Helpers

private func makeTempDirectory() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProjectSaveLoadTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}

private func makeFloorPlan(imageData: Data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) -> FloorPlan {
    FloorPlan(
        imageData: imageData,
        widthMeters: 20.0,
        heightMeters: 15.0,
        pixelWidth: 800,
        pixelHeight: 600,
        origin: .imported,
        calibrationPoints: [
            CalibrationPoint(pixelX: 0, pixelY: 0),
            CalibrationPoint(pixelX: 400, pixelY: 300, realWorldX: 10, realWorldY: 7.5),
        ]
    )
}

private func makeProject(
    name: String = "Test Survey",
    imageData: Data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
    pointCount: Int = 3
) -> SurveyProject {
    let points = (0 ..< pointCount).map { idx in
        MeasurementPoint(
            floorPlanX: Double(idx) / max(Double(pointCount - 1), 1),
            floorPlanY: 0.5,
            rssi: -40 - idx * 10,
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:0\(idx)",
            channel: 6,
            band: .band2_4GHz
        )
    }
    return SurveyProject(
        name: name,
        floorPlan: makeFloorPlan(imageData: imageData),
        measurementPoints: points,
        surveyMode: .blueprint,
        metadata: SurveyMetadata(buildingName: "HQ", floorNumber: "2", notes: "Office survey")
    )
}

// MARK: - Save/Load Round-Trip Tests

@Suite("ProjectSaveLoadManager — Round-Trip")
struct ProjectSaveLoadRoundTripTests {

    @Test("save and load round-trips all project fields")
    func roundTripPreservesAllFields() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let original = makeProject()

        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.id == original.id)
        #expect(loaded.name == "Test Survey")
        #expect(loaded.surveyMode == .blueprint)
        #expect(loaded.metadata.buildingName == "HQ")
        #expect(loaded.metadata.floorNumber == "2")
        #expect(loaded.metadata.notes == "Office survey")
        #expect(loaded.measurementPoints.count == 3)
    }

    @Test("round-trip preserves floor plan image data")
    func roundTripPreservesImageData() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageData = Data(repeating: 0xAB, count: 1024)
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let original = makeProject(imageData: imageData)

        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floorPlan.imageData == imageData)
        #expect(loaded.floorPlan.imageData.count == 1024)
    }

    @Test("round-trip preserves floor plan dimensions and calibration")
    func roundTripPreservesFloorPlanMetadata() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let original = makeProject()

        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floorPlan.widthMeters == 20.0)
        #expect(loaded.floorPlan.heightMeters == 15.0)
        #expect(loaded.floorPlan.pixelWidth == 800)
        #expect(loaded.floorPlan.pixelHeight == 600)
        #expect(loaded.floorPlan.origin == .imported)
        #expect(loaded.floorPlan.calibrationPoints?.count == 2)
    }

    @Test("round-trip preserves measurement point data")
    func roundTripPreservesMeasurementPoints() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let original = makeProject(pointCount: 5)

        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.measurementPoints.count == 5)
        for (orig, load) in zip(original.measurementPoints, loaded.measurementPoints) {
            #expect(load.id == orig.id)
            #expect(load.rssi == orig.rssi)
            #expect(load.floorPlanX == orig.floorPlanX)
            #expect(load.ssid == orig.ssid)
            #expect(load.bssid == orig.bssid)
            #expect(load.channel == orig.channel)
            #expect(load.band == orig.band)
        }
    }

    @Test("round-trip preserves project timestamps")
    func roundTripPreservesTimestamps() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let original = makeProject()

        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        // ISO 8601 loses sub-second precision, so compare to 1s tolerance
        let diff = abs(loaded.createdAt.timeIntervalSince(original.createdAt))
        #expect(diff < 1.0, "createdAt should round-trip within 1s, got \(diff)s difference")
    }

    @Test("round-trip with all survey modes")
    func roundTripAllSurveyModes() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let manager = ProjectSaveLoadManager()

        for mode in SurveyMode.allCases {
            var project = makeProject()
            project = SurveyProject(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                floorPlan: project.floorPlan,
                measurementPoints: project.measurementPoints,
                surveyMode: mode,
                metadata: project.metadata
            )
            let bundleURL = tempDir.appendingPathComponent("\(mode.rawValue).netmonsurvey")
            try manager.save(project: project, to: bundleURL)
            let loaded = try manager.load(from: bundleURL)
            #expect(loaded.surveyMode == mode)
        }
    }
}

// MARK: - Bundle Structure Tests

@Suite("ProjectSaveLoadManager — Bundle Structure")
struct ProjectSaveLoadBundleTests {

    @Test("save creates directory bundle with required files")
    func saveCreatesDirectoryBundle() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue, "Bundle must be a directory")

        let jsonURL = bundleURL.appendingPathComponent("survey.json")
        let imageURL = bundleURL.appendingPathComponent("floorplan.png")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test("save creates heatmap-cache directory")
    func saveCreatesHeatmapCacheDir() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        let cacheURL = bundleURL.appendingPathComponent("heatmap-cache")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cacheURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test("survey.json does not contain floor plan image data")
    func jsonExcludesImageData() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let largeImage = Data(repeating: 0xFF, count: 10_000)
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(imageData: largeImage), to: bundleURL)

        let jsonURL = bundleURL.appendingPathComponent("survey.json")
        let jsonData = try Data(contentsOf: jsonURL)

        // JSON should be much smaller than the image
        #expect(jsonData.count < largeImage.count,
                "survey.json (\(jsonData.count) bytes) should be smaller than image (\(largeImage.count) bytes)")

        // The floor plan image data in JSON should be empty (base64 of empty Data)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        // Empty Data encodes as "" in base64 JSON
        #expect(!jsonString.contains("////"), "JSON should not contain large base64-encoded image data")
    }

    @Test("floor plan image stored as separate file")
    func floorPlanStoredSeparately() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(imageData: imageData), to: bundleURL)

        let imageURL = bundleURL.appendingPathComponent("floorplan.png")
        let loadedImage = try Data(contentsOf: imageURL)
        #expect(loadedImage == imageData)
    }
}

// MARK: - Overwrite Tests

@Suite("ProjectSaveLoadManager — Overwrite Safety")
struct ProjectSaveLoadOverwriteTests {

    @Test("saving to existing bundle replaces it cleanly")
    func saveOverwritesExistingBundle() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()

        // Save first version
        let projectV1 = makeProject(name: "Version 1", imageData: Data([1, 2, 3]))
        try manager.save(project: projectV1, to: bundleURL)

        // Save second version (overwrite)
        let projectV2 = makeProject(name: "Version 2", imageData: Data([4, 5, 6]))
        try manager.save(project: projectV2, to: bundleURL)

        let loaded = try manager.load(from: bundleURL)
        #expect(loaded.name == "Version 2")
        #expect(loaded.floorPlan.imageData == Data([4, 5, 6]))
    }

    @Test("overwrite removes stale files from previous save")
    func overwriteRemovesStaleFiles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()

        // Save and add a cache file
        try manager.save(project: makeProject(), to: bundleURL)
        try manager.saveHeatmapCache(
            imageData: Data([0xCA]),
            named: "signal.png",
            in: bundleURL
        )

        // Overwrite
        try manager.save(project: makeProject(name: "New"), to: bundleURL)

        // Stale cache should be gone (new bundle has empty cache dir)
        let cacheData = manager.loadHeatmapCache(named: "signal.png", from: bundleURL)
        #expect(cacheData == nil, "Stale cache files should be removed on overwrite")
    }
}

// MARK: - Error Handling Tests

@Suite("ProjectSaveLoadManager — Error Handling")
struct ProjectSaveLoadErrorTests {

    @Test("load from non-existent path throws bundleNotFound")
    func loadNonExistentBundle() {
        let manager = ProjectSaveLoadManager()
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.netmonsurvey")

        #expect(throws: SurveyFileError.self) {
            try manager.load(from: fakeURL)
        }
    }

    @Test("load from bundle missing survey.json throws surveyJSONMissing")
    func loadMissingSurveyJSON() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("broken.netmonsurvey")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        // Write only the image, no JSON
        try Data([1, 2, 3]).write(to: bundleURL.appendingPathComponent("floorplan.png"))

        let manager = ProjectSaveLoadManager()
        #expect(throws: SurveyFileError.self) {
            try manager.load(from: bundleURL)
        }
    }

    @Test("load from bundle with corrupted JSON throws corruptedJSON")
    func loadCorruptedJSON() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("corrupt.netmonsurvey")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: bundleURL.appendingPathComponent("survey.json"))
        try Data([1]).write(to: bundleURL.appendingPathComponent("floorplan.png"))

        let manager = ProjectSaveLoadManager()
        #expect(throws: SurveyFileError.self) {
            try manager.load(from: bundleURL)
        }
    }

    @Test("load from bundle missing floorplan.png throws floorPlanImageMissing")
    func loadMissingFloorPlan() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a valid bundle then delete the image
        let bundleURL = tempDir.appendingPathComponent("noimage.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)
        try FileManager.default.removeItem(at: bundleURL.appendingPathComponent("floorplan.png"))

        #expect(throws: SurveyFileError.self) {
            try manager.load(from: bundleURL)
        }
    }
}

// MARK: - Heatmap Cache Tests

@Suite("ProjectSaveLoadManager — Heatmap Cache")
struct ProjectSaveLoadCacheTests {

    @Test("save and load heatmap cache image")
    func cacheRoundTrip() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        let cacheImage = Data(repeating: 0xCC, count: 512)
        try manager.saveHeatmapCache(imageData: cacheImage, named: "signalStrength.png", in: bundleURL)

        let loaded = manager.loadHeatmapCache(named: "signalStrength.png", from: bundleURL)
        #expect(loaded == cacheImage)
    }

    @Test("load non-existent cache returns nil")
    func cacheNotFound() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        let loaded = manager.loadHeatmapCache(named: "nonexistent.png", from: bundleURL)
        #expect(loaded == nil)
    }

    @Test("clear cache removes all cached files")
    func clearCacheRemovesFiles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        try manager.saveHeatmapCache(imageData: Data([1]), named: "a.png", in: bundleURL)
        try manager.saveHeatmapCache(imageData: Data([2]), named: "b.png", in: bundleURL)

        try manager.clearHeatmapCache(in: bundleURL)

        #expect(manager.loadHeatmapCache(named: "a.png", from: bundleURL) == nil)
        #expect(manager.loadHeatmapCache(named: "b.png", from: bundleURL) == nil)

        // Cache directory should still exist (just empty)
        let cacheDir = bundleURL.appendingPathComponent("heatmap-cache")
        #expect(FileManager.default.fileExists(atPath: cacheDir.path))
    }
}

// MARK: - Empty Project Tests

@Suite("ProjectSaveLoadManager — Edge Cases")
struct ProjectSaveLoadEdgeCaseTests {

    @Test("save and load project with zero measurement points")
    func emptyMeasurementPoints() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("empty.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let project = makeProject(pointCount: 0)

        try manager.save(project: project, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.measurementPoints.isEmpty)
        #expect(loaded.name == "Test Survey")
    }

    @Test("save and load project with empty image data")
    func emptyImageData() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("empty-image.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let project = makeProject(imageData: Data())

        try manager.save(project: project, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floorPlan.imageData == Data())
    }

    @Test("save and load project with large image data")
    func largeImageData() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let largeImage = Data(repeating: 0xAB, count: 1_000_000)
        let bundleURL = tempDir.appendingPathComponent("large.netmonsurvey")
        let manager = ProjectSaveLoadManager()
        let project = makeProject(imageData: largeImage)

        try manager.save(project: project, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floorPlan.imageData.count == 1_000_000)
        #expect(loaded.floorPlan.imageData == largeImage)
    }
}

// MARK: - SurveyFileError Tests

@Suite("SurveyFileError")
struct SurveyFileErrorTests {

    @Test("error descriptions are non-empty")
    func errorDescriptions() {
        let errors: [SurveyFileError] = [
            .bundleNotFound(URL(fileURLWithPath: "/fake")),
            .surveyJSONMissing,
            .floorPlanImageMissing,
            .corruptedJSON("test detail"),
            .writeFailed("test detail"),
        ]
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("errors are Equatable")
    func errorsAreEquatable() {
        #expect(SurveyFileError.surveyJSONMissing == SurveyFileError.surveyJSONMissing)
        #expect(SurveyFileError.surveyJSONMissing != SurveyFileError.floorPlanImageMissing)
    }
}
