import Foundation

// MARK: - CapturedRoomGeometry

/// A single room's geometry in world-space coordinates (not yet normalized to a floor).
///
/// This is the plain-data representation of one room produced by RoomPlan, stripped
/// of any platform-specific types. Consumers on the iOS target extract this from
/// `CapturedRoom`/`CapturedStructure` and hand it to `MultiRoomBlueprintBuilder`.
public struct CapturedRoomGeometry: Sendable, Equatable {
    public let walls: [WallSegment]
    public let centroidX: Double
    public let centroidZ: Double
    public let labelText: String
    /// 0 = ground floor, 1 = second floor, -1 = basement, etc.
    public let storyIndex: Int

    public init(
        walls: [WallSegment],
        centroidX: Double,
        centroidZ: Double,
        labelText: String,
        storyIndex: Int
    ) {
        self.walls = walls
        self.centroidX = centroidX
        self.centroidZ = centroidZ
        self.labelText = labelText
        self.storyIndex = storyIndex
    }
}

// MARK: - MultiRoomBlueprintBuilder

/// Pure builder that assembles a `BlueprintProject` from an arbitrary set of
/// captured rooms, grouping by story and producing one `BlueprintFloor` per floor.
///
/// All methods are deterministic and free of RoomPlan imports, so they're directly
/// unit-testable without needing a live scanning session.
public enum MultiRoomBlueprintBuilder: Sendable {

    /// Builds a full `BlueprintProject`, one floor per unique `storyIndex`.
    public static func buildProject(
        name: String,
        rooms: [CapturedRoomGeometry],
        defaultFloorLabelPrefix: String = "Floor",
        metadata: BlueprintMetadata
    ) -> BlueprintProject {
        let byStory = Dictionary(grouping: rooms, by: \.storyIndex)
        let sortedStories = byStory.keys.sorted()

        let floors = sortedStories.map { story -> BlueprintFloor in
            let roomsOnFloor = byStory[story] ?? []
            return buildFloor(
                rooms: roomsOnFloor,
                label: "\(defaultFloorLabelPrefix) \(displayFloorNumber(for: story))",
                floorNumber: displayFloorNumber(for: story)
            )
        }

        return BlueprintProject(
            name: name,
            floors: floors,
            metadata: metadata
        )
    }

    /// Builds a single `BlueprintFloor` from all rooms on one story.
    /// Shifts all coordinates so the floor's top-left corner is (0, 0) and
    /// normalizes room-label positions to [0, 1].
    public static func buildFloor(
        rooms: [CapturedRoomGeometry],
        label: String,
        floorNumber: Int
    ) -> BlueprintFloor {
        let allWalls = rooms.flatMap(\.walls)
        let bounds = calculateBounds(walls: allWalls)

        let normalizedWalls = allWalls.map { wall in
            WallSegment(
                id: wall.id,
                startX: wall.startX - bounds.offsetX,
                startY: wall.startY - bounds.offsetZ,
                endX: wall.endX - bounds.offsetX,
                endY: wall.endY - bounds.offsetZ,
                thickness: wall.thickness
            )
        }

        var labels: [RoomLabel] = []
        if bounds.width > 0, bounds.height > 0 {
            for room in rooms {
                let localX = room.centroidX - bounds.offsetX
                let localZ = room.centroidZ - bounds.offsetZ
                let normX = clamp01(localX / bounds.width)
                let normY = clamp01(localZ / bounds.height)
                labels.append(RoomLabel(text: room.labelText, normalizedX: normX, normalizedY: normY))
            }
        }

        let svgData = SVGFloorPlanGenerator.generateSVG(
            walls: normalizedWalls,
            roomLabels: labels,
            widthMeters: bounds.width,
            heightMeters: bounds.height
        )

        return BlueprintFloor(
            label: label,
            floorNumber: floorNumber,
            svgData: svgData,
            widthMeters: bounds.width,
            heightMeters: bounds.height,
            roomLabels: labels,
            wallSegments: normalizedWalls
        )
    }

    // MARK: - Geometry helpers

    public struct Bounds: Sendable, Equatable {
        public let width: Double
        public let height: Double
        public let offsetX: Double
        public let offsetZ: Double
    }

    public static func calculateBounds(walls: [WallSegment]) -> Bounds {
        guard !walls.isEmpty else {
            return Bounds(width: 1.0, height: 1.0, offsetX: 0, offsetZ: 0)
        }

        var minX = Double.infinity
        var maxX = -Double.infinity
        var minZ = Double.infinity
        var maxZ = -Double.infinity

        for wall in walls {
            minX = min(minX, wall.startX, wall.endX)
            maxX = max(maxX, wall.startX, wall.endX)
            minZ = min(minZ, wall.startY, wall.endY)
            maxZ = max(maxZ, wall.startY, wall.endY)
        }

        let margin = 0.5
        let width = max(maxX - minX + margin * 2, 1.0)
        let height = max(maxZ - minZ + margin * 2, 1.0)

        return Bounds(
            width: width,
            height: height,
            offsetX: minX - margin,
            offsetZ: minZ - margin
        )
    }

    /// Groups rooms by their detected `storyIndex`.
    public static func groupByStory(rooms: [CapturedRoomGeometry]) -> [Int: [CapturedRoomGeometry]] {
        Dictionary(grouping: rooms, by: \.storyIndex)
    }

    // MARK: - Story → user-facing floor number

    /// Converts a detected `storyIndex` (relative to ground = 0) to a user-facing
    /// floor number. Ground floor is "1", second floor "2", basement "-1".
    static func displayFloorNumber(for storyIndex: Int) -> Int {
        storyIndex >= 0 ? storyIndex + 1 : storyIndex
    }

    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
