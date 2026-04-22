import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - MultiRoomBlueprintBuilder Tests

struct MultiRoomBlueprintBuilderTests {

    // MARK: - buildProject

    @Test("buildProject groups rooms on the same story into one floor")
    func singleStoryGroupsIntoOneFloor() {
        let rooms = [
            makeRoom(labelText: "Kitchen", story: 0, offsetX: 0),
            makeRoom(labelText: "Living Room", story: 0, offsetX: 6),
        ]
        let project = MultiRoomBlueprintBuilder.buildProject(
            name: "House",
            rooms: rooms,
            metadata: .init()
        )
        #expect(project.floors.count == 1)
        #expect(project.floors[0].roomLabels.count == 2)
    }

    @Test("buildProject splits rooms on different stories into multiple floors")
    func multiStorySplitsIntoFloors() {
        let rooms = [
            makeRoom(labelText: "Kitchen", story: 0, offsetX: 0),
            makeRoom(labelText: "Bedroom", story: 1, offsetX: 0),
            makeRoom(labelText: "Office", story: 1, offsetX: 6),
        ]
        let project = MultiRoomBlueprintBuilder.buildProject(
            name: "House",
            rooms: rooms,
            metadata: .init()
        )
        #expect(project.floors.count == 2)
        #expect(project.floors[0].floorNumber == 1)
        #expect(project.floors[1].floorNumber == 2)
    }

    @Test("buildProject floors are sorted by story ascending (basement first)")
    func floorsSortedByStoryAscending() {
        let rooms = [
            makeRoom(labelText: "Attic", story: 2, offsetX: 0),
            makeRoom(labelText: "Basement", story: -1, offsetX: 0),
            makeRoom(labelText: "Kitchen", story: 0, offsetX: 0),
        ]
        let project = MultiRoomBlueprintBuilder.buildProject(
            name: "House",
            rooms: rooms,
            metadata: .init()
        )
        #expect(project.floors.count == 3)
        // Basement display floor = -1, ground = 1, attic = 3
        #expect(project.floors[0].floorNumber == -1)
        #expect(project.floors[1].floorNumber == 1)
        #expect(project.floors[2].floorNumber == 3)
    }

    @Test("buildProject preserves project metadata")
    func projectMetadataIsPreserved() {
        let metadata = BlueprintMetadata(
            buildingName: "Tower A",
            scanDeviceModel: "iPhone 15 Pro",
            hasLiDAR: true
        )
        let project = MultiRoomBlueprintBuilder.buildProject(
            name: "Office Scan",
            rooms: [makeRoom(labelText: "Kitchen", story: 0, offsetX: 0)],
            metadata: metadata
        )
        #expect(project.name == "Office Scan")
        #expect(project.metadata.buildingName == "Tower A")
        #expect(project.metadata.hasLiDAR == true)
    }

    @Test("buildProject with zero rooms produces zero floors")
    func zeroRoomsZeroFloors() {
        let project = MultiRoomBlueprintBuilder.buildProject(
            name: "Empty",
            rooms: [],
            metadata: .init()
        )
        #expect(project.floors.isEmpty)
    }

    // MARK: - buildFloor

    @Test("buildFloor merges walls from all rooms on the floor")
    func floorMergesWalls() {
        let rooms = [
            makeRoom(labelText: "Kitchen", story: 0, offsetX: 0),
            makeRoom(labelText: "Living Room", story: 0, offsetX: 6),
        ]
        let floor = MultiRoomBlueprintBuilder.buildFloor(
            rooms: rooms,
            label: "Ground",
            floorNumber: 1
        )
        // Each makeRoom contributes 4 walls → 8 total
        #expect(floor.wallSegments.count == 8)
    }

    @Test("buildFloor normalizes walls so minimum coordinate is non-negative")
    func floorWallsAreShiftedToOrigin() {
        let rooms = [makeRoom(labelText: "Kitchen", story: 0, offsetX: 50)]
        let floor = MultiRoomBlueprintBuilder.buildFloor(
            rooms: rooms,
            label: "Ground",
            floorNumber: 1
        )
        for wall in floor.wallSegments {
            #expect(wall.startX >= 0)
            #expect(wall.startY >= 0)
            #expect(wall.endX >= 0)
            #expect(wall.endY >= 0)
        }
    }

    @Test("buildFloor room labels fall inside the [0, 1] normalized range")
    func roomLabelsAreNormalized() {
        let rooms = [
            makeRoom(labelText: "Kitchen", story: 0, offsetX: 0),
            makeRoom(labelText: "Living Room", story: 0, offsetX: 6),
        ]
        let floor = MultiRoomBlueprintBuilder.buildFloor(
            rooms: rooms,
            label: "Ground",
            floorNumber: 1
        )
        #expect(floor.roomLabels.count == 2)
        for label in floor.roomLabels {
            #expect(label.normalizedX >= 0 && label.normalizedX <= 1)
            #expect(label.normalizedY >= 0 && label.normalizedY <= 1)
        }
    }

    @Test("buildFloor label text comes from the captured room")
    func labelTextPreserved() {
        let rooms = [
            makeRoom(labelText: "Master Bedroom", story: 0, offsetX: 0),
        ]
        let floor = MultiRoomBlueprintBuilder.buildFloor(
            rooms: rooms,
            label: "Ground",
            floorNumber: 1
        )
        #expect(floor.roomLabels.first?.text == "Master Bedroom")
    }

    @Test("buildFloor sizes include a half-meter margin on each side")
    func floorIncludesMargin() {
        // Room spans x: 0..4, z: 0..3 → raw 4×3, with 0.5m margins → 5×4
        let walls = [
            WallSegment(startX: 0, startY: 0, endX: 4, endY: 0, thickness: 0.1),
            WallSegment(startX: 4, startY: 0, endX: 4, endY: 3, thickness: 0.1),
            WallSegment(startX: 4, startY: 3, endX: 0, endY: 3, thickness: 0.1),
            WallSegment(startX: 0, startY: 3, endX: 0, endY: 0, thickness: 0.1),
        ]
        let room = CapturedRoomGeometry(
            walls: walls,
            centroidX: 2,
            centroidZ: 1.5,
            labelText: "Room",
            storyIndex: 0
        )
        let floor = MultiRoomBlueprintBuilder.buildFloor(
            rooms: [room],
            label: "Ground",
            floorNumber: 1
        )
        #expect(abs(floor.widthMeters - 5.0) < 0.01)
        #expect(abs(floor.heightMeters - 4.0) < 0.01)
    }

    // MARK: - calculateBounds

    @Test("calculateBounds returns default unit bounds for empty walls")
    func emptyWallsDefaultBounds() {
        let bounds = MultiRoomBlueprintBuilder.calculateBounds(walls: [])
        #expect(bounds.width == 1.0)
        #expect(bounds.height == 1.0)
    }

    @Test("calculateBounds spans min-to-max with 0.5m margin on both sides")
    func boundsIncludesMargin() {
        let walls = [
            WallSegment(startX: 10, startY: 20, endX: 14, endY: 20, thickness: 0.1),
            WallSegment(startX: 14, startY: 20, endX: 14, endY: 23, thickness: 0.1),
        ]
        let bounds = MultiRoomBlueprintBuilder.calculateBounds(walls: walls)
        // width = (14-10) + 2*0.5 = 5
        #expect(abs(bounds.width - 5.0) < 0.01)
        // height = (23-20) + 2*0.5 = 4
        #expect(abs(bounds.height - 4.0) < 0.01)
        // offsetX = minX - 0.5 = 9.5
        #expect(abs(bounds.offsetX - 9.5) < 0.01)
    }

    // MARK: - groupByStory

    @Test("groupByStory returns one entry per unique story")
    func groupByStoryBuckets() {
        let rooms = [
            makeRoom(labelText: "A", story: 0, offsetX: 0),
            makeRoom(labelText: "B", story: 1, offsetX: 0),
            makeRoom(labelText: "C", story: 0, offsetX: 6),
        ]
        let grouped = MultiRoomBlueprintBuilder.groupByStory(rooms: rooms)
        #expect(grouped[0]?.count == 2)
        #expect(grouped[1]?.count == 1)
    }

    // MARK: - Test helpers

    /// Produces a rectangular 4×3 meter room at an X-axis offset, with the given
    /// label and story. The centroid is positioned at the room's center.
    private func makeRoom(labelText: String, story: Int, offsetX: Double) -> CapturedRoomGeometry {
        let walls = [
            WallSegment(startX: offsetX + 0, startY: 0, endX: offsetX + 4, endY: 0, thickness: 0.1),
            WallSegment(startX: offsetX + 4, startY: 0, endX: offsetX + 4, endY: 3, thickness: 0.1),
            WallSegment(startX: offsetX + 4, startY: 3, endX: offsetX + 0, endY: 3, thickness: 0.1),
            WallSegment(startX: offsetX + 0, startY: 3, endX: offsetX + 0, endY: 0, thickness: 0.1),
        ]
        return CapturedRoomGeometry(
            walls: walls,
            centroidX: offsetX + 2,
            centroidZ: 1.5,
            labelText: labelText,
            storyIndex: story
        )
    }
}
