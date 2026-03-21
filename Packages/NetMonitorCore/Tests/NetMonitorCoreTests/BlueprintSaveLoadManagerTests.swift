import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Test Helpers

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("BlueprintTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeWall(
    startX: Double = 0, startY: Double = 0,
    endX: Double = 5, endY: Double = 0,
    thickness: Double = 0.15
) -> WallSegment {
    WallSegment(startX: startX, startY: startY, endX: endX, endY: endY, thickness: thickness)
}

private func makeFloor(
    label: String = "Floor 1",
    floorNumber: Int = 1,
    svgContent: String = "<svg>test</svg>",
    widthMeters: Double = 10.0,
    heightMeters: Double = 8.0,
    roomLabels: [RoomLabel] = [],
    wallSegments: [WallSegment] = []
) -> BlueprintFloor {
    BlueprintFloor(
        label: label,
        floorNumber: floorNumber,
        svgData: Data(svgContent.utf8),
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        roomLabels: roomLabels,
        wallSegments: wallSegments
    )
}

private func makeProject(
    name: String = "Test Blueprint",
    floors: [BlueprintFloor]? = nil,
    metadata: BlueprintMetadata = BlueprintMetadata(buildingName: "HQ", hasLiDAR: true)
) -> BlueprintProject {
    let defaultFloors = floors ?? [
        makeFloor(label: "Ground", floorNumber: 1, svgContent: "<svg>ground-floor</svg>")
    ]
    return BlueprintProject(
        name: name,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        floors: defaultFloors,
        metadata: metadata
    )
}

// MARK: - Save Tests

struct BlueprintSaveTests {

    @Test("save creates bundle directory at URL")
    func saveCreatesDirectory() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue, "Bundle must be a directory")
    }

    @Test("save creates blueprint.json file")
    func saveCreatesBlueprintJSON() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: makeProject(), to: bundleURL)

        let jsonURL = bundleURL.appendingPathComponent("blueprint.json")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
    }

    @Test("save creates floor SVG files for each floor")
    func saveCreatesFloorSVGs() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let floors = [
            makeFloor(label: "Ground", floorNumber: 1, svgContent: "<svg>floor1</svg>"),
            makeFloor(label: "Upper", floorNumber: 2, svgContent: "<svg>floor2</svg>"),
        ]
        let project = makeProject(floors: floors)

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: project, to: bundleURL)

        let svg1URL = bundleURL.appendingPathComponent("floor-1.svg")
        let svg2URL = bundleURL.appendingPathComponent("floor-2.svg")
        #expect(FileManager.default.fileExists(atPath: svg1URL.path))
        #expect(FileManager.default.fileExists(atPath: svg2URL.path))

        let svg1Data = try Data(contentsOf: svg1URL)
        let svg2Data = try Data(contentsOf: svg2URL)
        #expect(String(data: svg1Data, encoding: .utf8) == "<svg>floor1</svg>")
        #expect(String(data: svg2Data, encoding: .utf8) == "<svg>floor2</svg>")
    }

    @Test("save strips SVG data from JSON (not inlined)")
    func saveStripsSVGFromJSON() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let largeSVG = String(repeating: "x", count: 10_000)
        let floor = makeFloor(svgContent: largeSVG)
        let project = makeProject(floors: [floor])

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: project, to: bundleURL)

        let jsonURL = bundleURL.appendingPathComponent("blueprint.json")
        let jsonData = try Data(contentsOf: jsonURL)
        // JSON should be much smaller than the SVG
        #expect(jsonData.count < largeSVG.utf8.count,
                "blueprint.json should not contain inlined SVG data")
    }

    @Test("save overwrites existing bundle")
    func saveOverwritesExisting() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()

        let v1 = makeProject(name: "Version 1")
        try manager.save(project: v1, to: bundleURL)

        let v2 = makeProject(name: "Version 2")
        try manager.save(project: v2, to: bundleURL)

        let loaded = try manager.load(from: bundleURL)
        #expect(loaded.name == "Version 2")
    }
}

// MARK: - Load Round-Trip Tests

struct BlueprintLoadRoundTripTests {

    @Test("round-trip preserves all BlueprintProject fields")
    func roundTripPreservesAllFields() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wall = makeWall(startX: 1, startY: 2, endX: 3, endY: 4)
        let label = RoomLabel(text: "Kitchen", normalizedX: 0.5, normalizedY: 0.5)
        let floor = makeFloor(
            label: "Main",
            floorNumber: 1,
            svgContent: "<svg>main-floor</svg>",
            widthMeters: 12.0,
            heightMeters: 9.0,
            roomLabels: [label],
            wallSegments: [wall]
        )
        let meta = BlueprintMetadata(
            buildingName: "Office",
            address: "123 Main",
            notes: "Test scan",
            scanDeviceModel: "iPhone 15 Pro",
            hasLiDAR: true
        )
        let original = makeProject(name: "Full Test", floors: [floor], metadata: meta)

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: original, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.id == original.id)
        #expect(loaded.name == "Full Test")
        #expect(loaded.metadata.buildingName == "Office")
        #expect(loaded.metadata.address == "123 Main")
        #expect(loaded.metadata.notes == "Test scan")
        #expect(loaded.metadata.scanDeviceModel == "iPhone 15 Pro")
        #expect(loaded.metadata.hasLiDAR == true)
        #expect(loaded.floors.count == 1)
        #expect(loaded.floors[0].label == "Main")
        #expect(loaded.floors[0].floorNumber == 1)
        #expect(loaded.floors[0].widthMeters == 12.0)
        #expect(loaded.floors[0].heightMeters == 9.0)
        #expect(loaded.floors[0].roomLabels.count == 1)
        #expect(loaded.floors[0].roomLabels[0].text == "Kitchen")
        #expect(loaded.floors[0].wallSegments.count == 1)
    }

    @Test("round-trip restores SVG data from separate files")
    func roundTripRestoresSVGData() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let svgContent = "<svg xmlns='http://www.w3.org/2000/svg'><rect/></svg>"
        let floor = makeFloor(svgContent: svgContent)
        let project = makeProject(floors: [floor])

        let bundleURL = tempDir.appendingPathComponent("test.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: project, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floors[0].svgData == Data(svgContent.utf8))
    }

    @Test("multi-floor save/load preserves all floors")
    func multiFloorRoundTrip() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let floors = [
            makeFloor(label: "Basement", floorNumber: 0, svgContent: "<svg>basement</svg>",
                      widthMeters: 20.0, heightMeters: 15.0),
            makeFloor(label: "Ground", floorNumber: 1, svgContent: "<svg>ground</svg>",
                      widthMeters: 25.0, heightMeters: 18.0),
            makeFloor(label: "Upper", floorNumber: 2, svgContent: "<svg>upper</svg>",
                      widthMeters: 22.0, heightMeters: 16.0),
        ]
        let project = makeProject(name: "Multi-Floor", floors: floors)

        let bundleURL = tempDir.appendingPathComponent("multi.netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: project, to: bundleURL)
        let loaded = try manager.load(from: bundleURL)

        #expect(loaded.floors.count == 3)
        #expect(loaded.floors[0].label == "Basement")
        #expect(loaded.floors[0].svgData == Data("<svg>basement</svg>".utf8))
        #expect(loaded.floors[1].label == "Ground")
        #expect(loaded.floors[1].svgData == Data("<svg>ground</svg>".utf8))
        #expect(loaded.floors[2].label == "Upper")
        #expect(loaded.floors[2].svgData == Data("<svg>upper</svg>".utf8))
    }
}

// MARK: - Error Handling Tests

struct BlueprintLoadErrorTests {

    @Test("load from non-existent bundle throws bundleNotFound")
    func loadNonExistentBundle() {
        let manager = BlueprintSaveLoadManager()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).netmonblueprint")

        #expect(throws: BlueprintFileError.self) {
            try manager.load(from: fakeURL)
        }
    }

    @Test("load from bundle missing blueprint.json throws blueprintJSONMissing")
    func loadMissingBlueprintJSON() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("broken.netmonblueprint")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        // Create an SVG file but no blueprint.json
        try Data("<svg/>".utf8).write(to: bundleURL.appendingPathComponent("floor-1.svg"))

        let manager = BlueprintSaveLoadManager()
        #expect {
            try manager.load(from: bundleURL)
        } throws: { error in
            (error as? BlueprintFileError) == .blueprintJSONMissing
        }
    }

    @Test("load from bundle with missing floor SVG throws svgMissing")
    func loadMissingSVG() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("nosvg.netmonblueprint")
        let manager = BlueprintSaveLoadManager()

        // Save a valid project, then delete the SVG
        let project = makeProject()
        try manager.save(project: project, to: bundleURL)
        try FileManager.default.removeItem(
            at: bundleURL.appendingPathComponent("floor-1.svg")
        )

        #expect {
            try manager.load(from: bundleURL)
        } throws: { error in
            (error as? BlueprintFileError) == .svgMissing("floor-1.svg")
        }
    }

    @Test("load from bundle with invalid JSON throws corruptedJSON")
    func loadCorruptedJSON() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("corrupt.netmonblueprint")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(
            to: bundleURL.appendingPathComponent("blueprint.json")
        )

        let manager = BlueprintSaveLoadManager()
        #expect(throws: BlueprintFileError.self) {
            try manager.load(from: bundleURL)
        }
    }
}

// MARK: - floorPlanFromBlueprint Tests

struct FloorPlanFromBlueprintTests {

    @Test("returns FloorPlan with correct dimensions")
    func correctDimensions() {
        let floor = makeFloor(widthMeters: 15.0, heightMeters: 10.0)
        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor, renderWidth: 1024)

        #expect(floorPlan.widthMeters == 15.0)
        #expect(floorPlan.heightMeters == 10.0)
        #expect(floorPlan.pixelWidth == 1024)
        // Height should be proportional: 1024 * (10/15) = 682.666... -> 682
        let expectedHeight = Int(Double(1024) * (10.0 / 15.0))
        #expect(floorPlan.pixelHeight == expectedHeight)
    }

    @Test("sets origin to .arGenerated")
    func originIsARGenerated() {
        let floor = makeFloor(widthMeters: 10.0, heightMeters: 8.0)
        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor)
        #expect(floorPlan.origin == .arGenerated)
    }

    @Test("preserves wall segments")
    func preservesWalls() {
        let walls = [
            makeWall(startX: 0, startY: 0, endX: 10, endY: 0),
            makeWall(startX: 10, startY: 0, endX: 10, endY: 8),
        ]
        let floor = makeFloor(widthMeters: 10.0, heightMeters: 8.0, wallSegments: walls)
        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor)

        #expect(floorPlan.walls?.count == 2)
        #expect(floorPlan.walls?[0].startX == 0)
        #expect(floorPlan.walls?[0].endX == 10)
        #expect(floorPlan.walls?[1].startY == 0)
        #expect(floorPlan.walls?[1].endY == 8)
    }

    @Test("with empty SVG still produces FloorPlan (empty imageData)")
    func emptySVGProducesFloorPlan() {
        let floor = BlueprintFloor(
            svgData: Data(),
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor)

        // SVGRenderer returns empty Data for empty svgData
        #expect(floorPlan.imageData.isEmpty)
        #expect(floorPlan.widthMeters == 10.0)
        #expect(floorPlan.heightMeters == 8.0)
        #expect(floorPlan.origin == .arGenerated)
    }
}
