import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - BlueprintProject Tests

struct BlueprintProjectTests {

    @Test("init with defaults produces valid project")
    func initWithDefaults() {
        let project = BlueprintProject(name: "Office")
        #expect(project.name == "Office")
        #expect(project.floors.isEmpty)
        #expect(project.metadata == BlueprintMetadata())
    }

    @Test("init preserves all provided values")
    func initPreservesValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let floor = BlueprintFloor(label: "Ground", floorNumber: 0)
        let meta = BlueprintMetadata(buildingName: "HQ", hasLiDAR: true)

        let project = BlueprintProject(
            id: id,
            name: "Campus",
            createdAt: date,
            floors: [floor],
            metadata: meta
        )

        #expect(project.id == id)
        #expect(project.name == "Campus")
        #expect(project.createdAt == date)
        #expect(project.floors.count == 1)
        #expect(project.floors[0].label == "Ground")
        #expect(project.metadata.buildingName == "HQ")
        #expect(project.metadata.hasLiDAR == true)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let wall = WallSegment(startX: 0, startY: 0, endX: 5, endY: 0, thickness: 0.2)
        let label = RoomLabel(text: "Kitchen", normalizedX: 0.5, normalizedY: 0.5)
        let floor = BlueprintFloor(
            label: "First",
            floorNumber: 1,
            svgData: Data("svg-content".utf8),
            widthMeters: 10.0,
            heightMeters: 8.0,
            roomLabels: [label],
            wallSegments: [wall]
        )
        let meta = BlueprintMetadata(
            buildingName: "HQ",
            address: "123 Main",
            notes: "Test",
            scanDeviceModel: "iPhone 15 Pro",
            hasLiDAR: true
        )
        let original = BlueprintProject(
            name: "Test Project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            floors: [floor],
            metadata: meta
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BlueprintProject.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(abs(decoded.createdAt.timeIntervalSince(original.createdAt)) < 1.0)
        #expect(decoded.floors.count == 1)
        #expect(decoded.floors[0].label == "First")
        #expect(decoded.floors[0].widthMeters == 10.0)
        #expect(decoded.floors[0].heightMeters == 8.0)
        #expect(decoded.floors[0].svgData == Data("svg-content".utf8))
        #expect(decoded.floors[0].wallSegments.count == 1)
        #expect(decoded.floors[0].roomLabels.count == 1)
        #expect(decoded.metadata == meta)
    }

    @Test("multi-floor project preserves floor order")
    func multiFloorProject() {
        let floor1 = BlueprintFloor(label: "Basement", floorNumber: 0)
        let floor2 = BlueprintFloor(label: "Ground", floorNumber: 1)
        let floor3 = BlueprintFloor(label: "Upper", floorNumber: 2)

        let project = BlueprintProject(name: "Multi", floors: [floor1, floor2, floor3])
        #expect(project.floors.count == 3)
        #expect(project.floors[0].label == "Basement")
        #expect(project.floors[1].label == "Ground")
        #expect(project.floors[2].label == "Upper")
    }

    @Test("Equatable compares by value")
    func equatable() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let a = BlueprintProject(id: id, name: "A", createdAt: date)
        let b = BlueprintProject(id: id, name: "A", createdAt: date)
        let c = BlueprintProject(id: id, name: "B", createdAt: date)

        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - BlueprintFloor Tests

struct BlueprintFloorTests {

    @Test("init with defaults")
    func initWithDefaults() {
        let floor = BlueprintFloor()
        #expect(floor.label == "Floor 1")
        #expect(floor.floorNumber == 1)
        #expect(floor.svgData.isEmpty)
        #expect(floor.widthMeters == 0)
        #expect(floor.heightMeters == 0)
        #expect(floor.roomLabels.isEmpty)
        #expect(floor.wallSegments.isEmpty)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let wall = WallSegment(startX: 1, startY: 2, endX: 3, endY: 4, thickness: 0.1)
        let label = RoomLabel(text: "Office", normalizedX: 0.3, normalizedY: 0.7)
        let floor = BlueprintFloor(
            label: "Second",
            floorNumber: 2,
            svgData: Data("test-svg".utf8),
            widthMeters: 15.5,
            heightMeters: 12.3,
            roomLabels: [label],
            wallSegments: [wall]
        )

        let data = try JSONEncoder().encode(floor)
        let decoded = try JSONDecoder().decode(BlueprintFloor.self, from: data)

        #expect(decoded.id == floor.id)
        #expect(decoded.label == "Second")
        #expect(decoded.floorNumber == 2)
        #expect(decoded.svgData == Data("test-svg".utf8))
        #expect(decoded.widthMeters == 15.5)
        #expect(decoded.heightMeters == 12.3)
        #expect(decoded.roomLabels.count == 1)
        #expect(decoded.wallSegments.count == 1)
    }

    @Test("wall segments preserved through encode/decode")
    func wallSegmentsPreserved() throws {
        let walls = [
            WallSegment(startX: 0, startY: 0, endX: 10, endY: 0),
            WallSegment(startX: 10, startY: 0, endX: 10, endY: 8),
            WallSegment(startX: 10, startY: 8, endX: 0, endY: 8),
        ]
        let floor = BlueprintFloor(wallSegments: walls)

        let data = try JSONEncoder().encode(floor)
        let decoded = try JSONDecoder().decode(BlueprintFloor.self, from: data)

        #expect(decoded.wallSegments.count == 3)
        for (orig, dec) in zip(walls, decoded.wallSegments) {
            #expect(dec.id == orig.id)
            #expect(dec.startX == orig.startX)
            #expect(dec.startY == orig.startY)
            #expect(dec.endX == orig.endX)
            #expect(dec.endY == orig.endY)
            #expect(dec.thickness == orig.thickness)
        }
    }
}

// MARK: - RoomLabel Tests

struct RoomLabelTests {

    @Test("init preserves coordinate values")
    func initPreservesValues() {
        let id = UUID()
        let label = RoomLabel(id: id, text: "Living Room", normalizedX: 0.25, normalizedY: 0.75)
        #expect(label.id == id)
        #expect(label.text == "Living Room")
        #expect(label.normalizedX == 0.25)
        #expect(label.normalizedY == 0.75)
    }

    @Test("Codable round-trip preserves values")
    func codableRoundTrip() throws {
        let label = RoomLabel(text: "Bedroom", normalizedX: 0.1, normalizedY: 0.9)
        let data = try JSONEncoder().encode(label)
        let decoded = try JSONDecoder().decode(RoomLabel.self, from: data)

        #expect(decoded.id == label.id)
        #expect(decoded.text == "Bedroom")
        #expect(decoded.normalizedX == 0.1)
        #expect(decoded.normalizedY == 0.9)
    }

    @Test("boundary coordinate values (0.0 and 1.0)")
    func boundaryCoordinates() {
        let labelMin = RoomLabel(text: "Corner", normalizedX: 0.0, normalizedY: 0.0)
        let labelMax = RoomLabel(text: "Corner", normalizedX: 1.0, normalizedY: 1.0)

        #expect(labelMin.normalizedX == 0.0)
        #expect(labelMin.normalizedY == 0.0)
        #expect(labelMax.normalizedX == 1.0)
        #expect(labelMax.normalizedY == 1.0)
    }
}

// MARK: - BlueprintMetadata Tests

struct BlueprintMetadataTests {

    @Test("init with defaults has all optionals nil and hasLiDAR false")
    func initWithDefaults() {
        let meta = BlueprintMetadata()
        #expect(meta.buildingName == nil)
        #expect(meta.address == nil)
        #expect(meta.notes == nil)
        #expect(meta.scanDeviceModel == nil)
        #expect(meta.hasLiDAR == false)
    }

    @Test("init with all fields populated")
    func initWithAllFields() {
        let meta = BlueprintMetadata(
            buildingName: "Main Office",
            address: "456 Elm St",
            notes: "Second scan attempt",
            scanDeviceModel: "iPad Pro 12.9",
            hasLiDAR: true
        )
        #expect(meta.buildingName == "Main Office")
        #expect(meta.address == "456 Elm St")
        #expect(meta.notes == "Second scan attempt")
        #expect(meta.scanDeviceModel == "iPad Pro 12.9")
        #expect(meta.hasLiDAR == true)
    }

    @Test("hasLiDAR flag toggles correctly")
    func hasLiDARFlag() {
        let withLiDAR = BlueprintMetadata(hasLiDAR: true)
        let withoutLiDAR = BlueprintMetadata(hasLiDAR: false)

        #expect(withLiDAR.hasLiDAR == true)
        #expect(withoutLiDAR.hasLiDAR == false)
        #expect(withLiDAR != withoutLiDAR)
    }

    @Test("Equatable compares all fields")
    func equatable() {
        let a = BlueprintMetadata(buildingName: "A", hasLiDAR: true)
        let b = BlueprintMetadata(buildingName: "A", hasLiDAR: true)
        let c = BlueprintMetadata(buildingName: "B", hasLiDAR: true)

        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - BlueprintFileError Tests

struct BlueprintFileErrorTests {

    @Test("all cases have non-empty localizedDescription")
    func allCasesHaveDescription() {
        let errors: [BlueprintFileError] = [
            .bundleNotFound(URL(fileURLWithPath: "/fake/path.netmonblueprint")),
            .blueprintJSONMissing,
            .svgMissing("floor-1.svg"),
            .corruptedJSON("unexpected token"),
            .writeFailed("permission denied"),
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty,
                    "localizedDescription should not be empty for \(error)")
        }
    }

    @Test("bundleNotFound includes path component")
    func bundleNotFoundIncludesPath() {
        let error = BlueprintFileError.bundleNotFound(
            URL(fileURLWithPath: "/tmp/test.netmonblueprint")
        )
        #expect(error.localizedDescription.contains("test.netmonblueprint"))
    }

    @Test("svgMissing includes filename")
    func svgMissingIncludesFilename() {
        let error = BlueprintFileError.svgMissing("floor-3.svg")
        #expect(error.localizedDescription.contains("floor-3.svg"))
    }

    @Test("corruptedJSON includes detail message")
    func corruptedJSONIncludesDetail() {
        let error = BlueprintFileError.corruptedJSON("unexpected EOF")
        #expect(error.localizedDescription.contains("unexpected EOF"))
    }

    @Test("errors are Equatable")
    func errorsAreEquatable() {
        #expect(BlueprintFileError.blueprintJSONMissing == BlueprintFileError.blueprintJSONMissing)
        #expect(BlueprintFileError.svgMissing("a") != BlueprintFileError.svgMissing("b"))
        #expect(BlueprintFileError.blueprintJSONMissing != BlueprintFileError.svgMissing("x"))
    }
}
