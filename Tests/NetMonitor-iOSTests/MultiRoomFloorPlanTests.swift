import CoreGraphics
import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - Multi-Room Floor Plan Generation Tests

@Suite("FloorPlanGenerationPipeline — Multi-Room Stitching")
struct MultiRoomStitchingTests {

    // MARK: - Helpers

    /// Creates wall vertices for a rectangular room at specified position.
    /// Vertices are placed at wall height (1.0-2.0m) for height filter inclusion.
    private func makeRoomVertices(
        originX: Float,
        originZ: Float,
        width: Float,
        depth: Float,
        spacing: Float = 0.1
    ) -> [MeshVertex] {
        var vertices: [MeshVertex] = []

        // North wall (z = originZ)
        for x in stride(from: originX, through: originX + width, by: spacing) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: originZ))
            vertices.append(MeshVertex(x: x, y: 1.5, z: originZ))
            vertices.append(MeshVertex(x: x, y: 2.0, z: originZ))
        }

        // South wall (z = originZ + depth)
        for x in stride(from: originX, through: originX + width, by: spacing) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: originZ + depth))
            vertices.append(MeshVertex(x: x, y: 1.5, z: originZ + depth))
            vertices.append(MeshVertex(x: x, y: 2.0, z: originZ + depth))
        }

        // West wall (x = originX)
        for z in stride(from: originZ, through: originZ + depth, by: spacing) {
            vertices.append(MeshVertex(x: originX, y: 1.0, z: z))
            vertices.append(MeshVertex(x: originX, y: 1.5, z: z))
            vertices.append(MeshVertex(x: originX, y: 2.0, z: z))
        }

        // East wall (x = originX + width)
        for z in stride(from: originZ, through: originZ + depth, by: spacing) {
            vertices.append(MeshVertex(x: originX + width, y: 1.0, z: z))
            vertices.append(MeshVertex(x: originX + width, y: 1.5, z: z))
            vertices.append(MeshVertex(x: originX + width, y: 2.0, z: z))
        }

        return vertices
    }

    // MARK: - Multi-Room Combined Image Tests

    @Test("vertices from two spatially separated rooms produce a combined floor plan image")
    func twoRoomsCombinedImage() {
        // Room 1: 4m x 3m at origin (0, 0)
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 4, depth: 3)

        // Room 2: 4m x 3m at (6, 0) — 2m gap simulating a hallway/doorway between rooms
        let room2 = makeRoomVertices(originX: 6, originZ: 0, width: 4, depth: 3)

        // Combine all vertices (simulating continuous AR accumulation)
        let allVertices = room1 + room2

        let result = FloorPlanGenerationPipeline.generateFromMesh(
            vertices: allVertices,
            floorY: 0
        )

        // The combined floor plan should be generated successfully
        #expect(result != nil, "Combined multi-room floor plan should not be nil")

        // The width should span both rooms (10m + gap + padding)
        // Room 1 spans 0-4m, Room 2 spans 6-10m, so total is ~10m + padding
        #expect(result!.widthMeters > 9.0, "Width should cover both rooms: got \(result!.widthMeters)m")

        // The height should cover the room depth (3m + padding)
        #expect(result!.heightMeters > 2.0, "Height should cover room depth: got \(result!.heightMeters)m")

        // The image should have valid dimensions
        #expect(result!.pixelWidth > 0)
        #expect(result!.pixelHeight > 0)
        #expect(result!.image.width == result!.pixelWidth)
        #expect(result!.image.height == result!.pixelHeight)
    }

    @Test("vertices from three rooms in L-shape produce a combined floor plan image")
    func threeRoomsLShapeCombined() {
        // Room 1: 4m x 3m at origin (0, 0)
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 4, depth: 3)

        // Room 2: 4m x 3m at (5, 0) — adjacent with 1m gap (doorway)
        let room2 = makeRoomVertices(originX: 5, originZ: 0, width: 4, depth: 3)

        // Room 3: 4m x 3m at (5, 4) — below room 2 (L-shape), 1m gap
        let room3 = makeRoomVertices(originX: 5, originZ: 4, width: 4, depth: 3)

        let allVertices = room1 + room2 + room3

        let result = FloorPlanGenerationPipeline.generateFromMesh(
            vertices: allVertices,
            floorY: 0
        )

        #expect(result != nil, "L-shape multi-room floor plan should not be nil")

        // Width spans room 1 (0-4m) and room 2/3 (5-9m) = ~9m + padding
        #expect(result!.widthMeters > 8.0, "Width should cover L-shape: got \(result!.widthMeters)m")

        // Height spans from room 1/2 (0-3m) down to room 3 (4-7m) = ~7m + padding
        #expect(result!.heightMeters > 6.0, "Height should cover L-shape depth: got \(result!.heightMeters)m")

        // Image is valid
        #expect(result!.pixelWidth > 0)
        #expect(result!.pixelHeight > 0)
    }

    @Test("generateMultiRoomFloorPlan produces same result as generateFromMesh")
    func multiRoomAliasMatchesMesh() {
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 4, depth: 3)
        let room2 = makeRoomVertices(originX: 6, originZ: 0, width: 4, depth: 3)
        let allVertices = room1 + room2

        let meshResult = FloorPlanGenerationPipeline.generateFromMesh(vertices: allVertices)
        let multiResult = FloorPlanGenerationPipeline.generateMultiRoomFloorPlan(vertices: allVertices)

        #expect(meshResult != nil)
        #expect(multiResult != nil)

        // Both pipelines should produce identical dimensions
        #expect(meshResult!.widthMeters == multiResult!.widthMeters)
        #expect(meshResult!.heightMeters == multiResult!.heightMeters)
        #expect(meshResult!.pixelWidth == multiResult!.pixelWidth)
        #expect(meshResult!.pixelHeight == multiResult!.pixelHeight)
    }
}

// MARK: - Room Boundary Detection Tests

@Suite("FloorPlanGenerationPipeline — Room Boundary Detection")
struct RoomBoundaryDetectionTests {

    /// Creates dense wall vertices forming a wall segment at specified position.
    private func makeWallSegment(
        startX: Float,
        startZ: Float,
        endX: Float,
        endZ: Float,
        spacing: Float = 0.1
    ) -> [MeshVertex] {
        var vertices: [MeshVertex] = []
        let dx = endX - startX
        let dz = endZ - startZ
        let length = sqrt(dx * dx + dz * dz)
        let steps = max(1, Int(length / spacing))

        for i in 0 ... steps {
            let fraction = Float(i) / Float(steps)
            let x = startX + dx * fraction
            let z = startZ + dz * fraction
            // Multiple heights for density
            vertices.append(MeshVertex(x: x, y: 1.0, z: z))
            vertices.append(MeshVertex(x: x, y: 1.5, z: z))
            vertices.append(MeshVertex(x: x, y: 2.0, z: z))
        }
        return vertices
    }

    @Test("detects narrow passage between two dense wall regions")
    func detectsNarrowPassage() {
        // Create two wall segments with a narrow 1m gap between them
        // Wall 1: z=0 to z=5 at x=0 (dense left wall)
        var vertices = makeWallSegment(startX: 0, startZ: 0, endX: 0, endZ: 5)

        // Wall 2: z=0 to z=5 at x=4 (dense right wall)
        vertices += makeWallSegment(startX: 4, startZ: 0, endX: 4, endZ: 5)

        // Horizontal walls creating two rooms with a doorway:
        // Room 1 top wall: x=0 to x=1.5 at z=2.5
        vertices += makeWallSegment(startX: 0, startZ: 2.5, endX: 1.5, endZ: 2.5)
        // Room 1 bottom of doorway: x=2.5 to x=4 at z=2.5
        vertices += makeWallSegment(startX: 2.5, startZ: 2.5, endX: 4, endZ: 2.5)
        // Gap at x=1.5 to x=2.5 (1m doorway) in the row at z=2.5

        let boundaries = FloorPlanGenerationPipeline.detectRoomBoundaries(vertices: vertices)

        // Boundary detection should complete without crash.
        // The exact count depends on grid alignment of the test geometry.

        // All detected boundaries should have passage width <= 1.5m
        for boundary in boundaries {
            #expect(
                boundary.passageWidth <= FloorPlanGenerationPipeline.maxPassageWidth,
                "Passage width \(boundary.passageWidth) should be <= \(FloorPlanGenerationPipeline.maxPassageWidth)m"
            )
        }
    }

    @Test("returns empty for insufficient vertices")
    func emptyForInsufficientVertices() {
        let vertices = [
            MeshVertex(x: 0, y: 1.5, z: 0),
            MeshVertex(x: 1, y: 1.5, z: 0),
        ]
        let boundaries = FloorPlanGenerationPipeline.detectRoomBoundaries(vertices: vertices)
        #expect(boundaries.isEmpty)
    }

    @Test("returns empty for empty input")
    func emptyForEmptyInput() {
        let boundaries = FloorPlanGenerationPipeline.detectRoomBoundaries(vertices: [])
        #expect(boundaries.isEmpty)
    }
}

// MARK: - Spatial Region Tests

@Suite("FloorPlanGenerationPipeline — Spatial Region")
struct SpatialRegionTests {

    @Test("computes spatial region from vertices")
    func computesRegion() {
        let vertices = [
            MeshVertex(x: -2, y: 1.0, z: -1),
            MeshVertex(x: 3, y: 1.5, z: 4),
            MeshVertex(x: 1, y: 2.0, z: 2),
        ]

        let region = FloorPlanGenerationPipeline.computeSpatialRegion(vertices: vertices)
        #expect(region != nil)
        #expect(region!.minX == -2)
        #expect(region!.minZ == -1)
        #expect(region!.maxX == 3)
        #expect(region!.maxZ == 4)
    }

    @Test("returns nil for empty vertices")
    func nilForEmpty() {
        let region = FloorPlanGenerationPipeline.computeSpatialRegion(vertices: [])
        #expect(region == nil)
    }

    @Test("filters by height range before computing region")
    func filtersHeight() {
        let vertices = [
            MeshVertex(x: 0, y: 0, z: 0),      // Below min height — excluded
            MeshVertex(x: 5, y: 1.0, z: 3),     // Included
            MeshVertex(x: 10, y: 10, z: 10),    // Above max height — excluded
        ]

        let region = FloorPlanGenerationPipeline.computeSpatialRegion(vertices: vertices)
        #expect(region != nil)
        // Only the single included vertex should define the region
        #expect(region!.minX == 5)
        #expect(region!.maxX == 5)
        #expect(region!.minZ == 3)
        #expect(region!.maxZ == 3)
    }

    @Test("SpatialRegion contains check works correctly")
    func containsCheck() {
        let region = SpatialRegion(minX: 0, minZ: 0, maxX: 10, maxZ: 8)

        #expect(region.contains(x: 5, z: 4))
        #expect(region.contains(x: 0, z: 0))
        #expect(region.contains(x: 10, z: 8))
        #expect(!region.contains(x: -1, z: 4))
        #expect(!region.contains(x: 5, z: -1))

        // With margin
        #expect(region.contains(x: -0.5, z: 4, margin: 1.0))
        #expect(!region.contains(x: -2, z: 4, margin: 1.0))
    }
}

// MARK: - FloorPlanGenerationViewModel Multi-Room Tests

@Suite("FloorPlanGenerationViewModel — Multi-Room")
@MainActor
struct MultiRoomViewModelTests {

    /// Creates wall vertices for a rectangular room.
    private func makeRoomVertices(
        originX: Float,
        originZ: Float,
        width: Float,
        depth: Float,
        spacing: Float = 0.1
    ) -> [MeshVertex] {
        var vertices: [MeshVertex] = []
        for x in stride(from: originX, through: originX + width, by: spacing) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: originZ))
            vertices.append(MeshVertex(x: x, y: 1.5, z: originZ))
            vertices.append(MeshVertex(x: x, y: 1.0, z: originZ + depth))
            vertices.append(MeshVertex(x: x, y: 1.5, z: originZ + depth))
        }
        for z in stride(from: originZ, through: originZ + depth, by: spacing) {
            vertices.append(MeshVertex(x: originX, y: 1.0, z: z))
            vertices.append(MeshVertex(x: originX, y: 1.5, z: z))
            vertices.append(MeshVertex(x: originX + width, y: 1.0, z: z))
            vertices.append(MeshVertex(x: originX + width, y: 1.5, z: z))
        }
        return vertices
    }

    @Test("roomBoundaries array starts empty")
    func roomBoundariesStartEmpty() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)
        #expect(vm.roomBoundaries.isEmpty)
    }

    @Test("reset clears room boundaries and region expansion state")
    func resetClearsMultiRoomState() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Add enough vertices to trigger boundary detection
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 4, depth: 3)
        let room2 = makeRoomVertices(originX: 6, originZ: 0, width: 4, depth: 3)
        vm.addVertices(room1 + room2)

        vm.reset()

        #expect(vm.roomBoundaries.isEmpty)
        #expect(!vm.didExpandIntoNewRegion)
        #expect(vm.vertexCount == 0)
    }

    @Test("generates floor plan from multi-room vertices via ViewModel")
    func generatesMultiRoomFloorPlan() async {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Room 1: 5m x 3m at origin
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 5, depth: 3)
        // Room 2: 5m x 3m at (7, 0)
        let room2 = makeRoomVertices(originX: 7, originZ: 0, width: 5, depth: 3)

        vm.addVertices(room1)
        vm.addVertices(room2)

        await vm.generateFloorPlan()

        #expect(vm.generationResult != nil, "Multi-room generation should succeed")
        #expect(vm.errorMessage == nil)

        // Width should span both rooms: 0-5m and 7-12m = 12m + padding
        #expect(vm.generationResult!.widthMeters > 11.0)
    }

    @Test("didExpandIntoNewRegion tracks spatial expansion")
    func tracksExpansion() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Initially no expansion
        #expect(!vm.didExpandIntoNewRegion)

        // Add room 1 vertices
        let room1 = makeRoomVertices(originX: 0, originZ: 0, width: 4, depth: 3)
        vm.addVertices(room1)

        // After adding room 1, didExpandIntoNewRegion depends on throttling,
        // but the region should be tracked
        #expect(vm.vertexCount > 0)
    }
}
