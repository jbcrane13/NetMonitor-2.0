import Foundation
import NetMonitorCore
import RoomPlan
import simd

// MARK: - RoomPlanGeometryAdapter

/// Converts RoomPlan types (`CapturedRoom`, `CapturedStructure`) into the pure
/// `CapturedRoomGeometry` data consumed by `MultiRoomBlueprintBuilder`.
///
/// This is the thin adapter layer between Apple's RoomPlan framework and our
/// platform-independent blueprint core. All methods are static, nonisolated,
/// and free of UI concerns.
enum RoomPlanGeometryAdapter {

    /// Extract one `CapturedRoomGeometry` per room in a merged `CapturedStructure`.
    static func extractRooms(from structure: CapturedStructure) -> [CapturedRoomGeometry] {
        structure.rooms.enumerated().map { index, room in
            extractRoom(room, fallbackIndex: index)
        }
    }

    /// Extract geometry for a single `CapturedRoom`. The `fallbackIndex` is used
    /// to generate a default label ("Room 1", "Room 2", …) when the room has no
    /// semantic section category.
    static func extractRoom(_ room: CapturedRoom, fallbackIndex: Int) -> CapturedRoomGeometry {
        let walls = extractWalls(room: room)
        let centroid = computeCentroid(of: room.walls)
        let story = inferStoryIndex(room: room)
        let label = inferLabel(room: room, fallbackIndex: fallbackIndex)

        return CapturedRoomGeometry(
            walls: walls,
            centroidX: centroid.x,
            centroidZ: centroid.z,
            labelText: label,
            storyIndex: story
        )
    }

    // MARK: - Walls

    /// Extract all wall + door segments in world-space coordinates.
    /// Wall thickness comes from the detected geometry; doors use a thin fixed stroke
    /// so they render as visible gaps in the floor plan.
    private static func extractWalls(room: CapturedRoom) -> [WallSegment] {
        var segments: [WallSegment] = []
        segments.reserveCapacity(room.walls.count + room.doors.count)

        for wall in room.walls {
            segments.append(segment(from: wall, thickness: max(Double(wall.dimensions.z), 0.1)))
        }

        for door in room.doors {
            segments.append(segment(from: door, thickness: 0.03))
        }

        return segments
    }

    private static func segment(from surface: CapturedRoom.Surface, thickness: Double) -> WallSegment {
        let transform = surface.transform
        let halfWidth = surface.dimensions.x / 2

        let localStart = simd_float4(-halfWidth, 0, 0, 1)
        let localEnd = simd_float4(halfWidth, 0, 0, 1)

        let worldStart = simd_mul(transform, localStart)
        let worldEnd = simd_mul(transform, localEnd)

        return WallSegment(
            startX: Double(worldStart.x),
            startY: Double(worldStart.z),
            endX: Double(worldEnd.x),
            endY: Double(worldEnd.z),
            thickness: thickness
        )
    }

    // MARK: - Centroid

    private static func computeCentroid(of walls: [CapturedRoom.Surface]) -> (x: Double, z: Double) {
        guard !walls.isEmpty else { return (0, 0) }
        let count = Double(walls.count)
        var sumX = 0.0
        var sumZ = 0.0
        for wall in walls {
            sumX += Double(wall.transform.columns.3.x)
            sumZ += Double(wall.transform.columns.3.z)
        }
        return (sumX / count, sumZ / count)
    }

    // MARK: - Story inference

    /// Infer a floor number from the vertical translation of the first wall.
    /// Ground floor (≈ 0m) → 0, second floor (≈ 3m) → 1, basement (≈ –3m) → –1.
    private static func inferStoryIndex(room: CapturedRoom) -> Int {
        let y: Float
        if let firstWall = room.walls.first {
            y = firstWall.transform.columns.3.y
        } else if let firstFloor = room.floors.first {
            y = firstFloor.transform.columns.3.y
        } else {
            return 0
        }
        // A typical residential story is ~2.5–3.0 m. Split at 1.5 m.
        let storyHeight: Float = 3.0
        return Int((Double(y) / Double(storyHeight)).rounded())
    }

    // MARK: - Label inference

    /// Generic "Room N" label — the user can rename each room after export in Mac.
    /// RoomPlan does provide semantic section labels via `CapturedRoom.Section.label`
    /// on newer SDKs, but we keep the default generic to avoid SDK-version divergence
    /// and give the user control over naming.
    private static func inferLabel(room: CapturedRoom, fallbackIndex: Int) -> String {
        return "Room \(fallbackIndex + 1)"
    }
}
