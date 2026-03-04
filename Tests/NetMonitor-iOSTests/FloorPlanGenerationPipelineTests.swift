import CoreGraphics
import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - Height Filtering Tests

@Suite("FloorPlanGenerationPipeline — Height Filtering")
struct HeightFilteringTests {

    @Test("filters vertices within wall height range 0.5-2.5m")
    func filtersWithinRange() {
        let vertices = [
            MeshVertex(x: 0, y: 0.0, z: 0),  // Below floor — filtered out
            MeshVertex(x: 1, y: 0.3, z: 1),   // Below min height — filtered out
            MeshVertex(x: 2, y: 0.5, z: 2),   // At min boundary — included
            MeshVertex(x: 3, y: 1.5, z: 3),   // Mid wall — included
            MeshVertex(x: 4, y: 2.5, z: 4),   // At max boundary — included
            MeshVertex(x: 5, y: 3.0, z: 5),   // Above ceiling — filtered out
            MeshVertex(x: 6, y: 5.0, z: 6),   // Way above — filtered out
        ]

        let filtered = FloorPlanGenerationPipeline.heightFilter(vertices: vertices)
        #expect(filtered.count == 3)
        #expect(filtered[0].x == 2)
        #expect(filtered[1].x == 3)
        #expect(filtered[2].x == 4)
    }

    @Test("handles non-zero floor Y coordinate")
    func nonZeroFloorY() {
        let vertices = [
            MeshVertex(x: 0, y: 0.8, z: 0),  // 0.8 - 0.5 = 0.3m above floor → below min
            MeshVertex(x: 1, y: 0.9, z: 1),   // 0.9 - 0.5 = 0.4m above floor → below min
            MeshVertex(x: 2, y: 1.5, z: 2),   // 1.5 - 0.5 = 1.0m above floor → included
            MeshVertex(x: 3, y: 3.0, z: 3),   // 3.0 - 0.5 = 2.5m above floor → included
            MeshVertex(x: 4, y: 3.5, z: 4),   // 3.5 - 0.5 = 3.0m above floor → excluded
        ]

        let filtered = FloorPlanGenerationPipeline.heightFilter(vertices: vertices, floorY: 0.5)
        #expect(filtered.count == 2)
        #expect(filtered[0].x == 2)
        #expect(filtered[1].x == 3)
    }

    @Test("returns empty for empty input")
    func emptyInput() {
        let filtered = FloorPlanGenerationPipeline.heightFilter(vertices: [])
        #expect(filtered.isEmpty)
    }

    @Test("returns empty when no vertices in range")
    func noVerticesInRange() {
        let vertices = [
            MeshVertex(x: 0, y: 0.0, z: 0),
            MeshVertex(x: 1, y: 0.1, z: 1),
            MeshVertex(x: 2, y: 10.0, z: 2),
        ]

        let filtered = FloorPlanGenerationPipeline.heightFilter(vertices: vertices)
        #expect(filtered.isEmpty)
    }

    @Test("custom height range works")
    func customHeightRange() {
        let vertices = [
            MeshVertex(x: 0, y: 0.2, z: 0),
            MeshVertex(x: 1, y: 0.5, z: 1),
            MeshVertex(x: 2, y: 1.0, z: 2),
        ]

        let filtered = FloorPlanGenerationPipeline.heightFilter(
            vertices: vertices,
            minHeight: 0.1,
            maxHeight: 0.6
        )
        #expect(filtered.count == 2)
        #expect(filtered[0].x == 0)
        #expect(filtered[1].x == 1)
    }
}

// MARK: - XZ Projection Tests

@Suite("FloorPlanGenerationPipeline — XZ Projection")
struct XZProjectionTests {

    @Test("projects 3D vertices to 2D XZ plane")
    func projectsToXZ() {
        let vertices = [
            MeshVertex(x: 1.0, y: 1.5, z: 2.0),
            MeshVertex(x: 3.0, y: 2.0, z: 4.0),
        ]

        let projected = FloorPlanGenerationPipeline.projectToXZ(vertices: vertices)
        #expect(projected.count == 2)
        #expect(projected[0].x == 1.0)
        #expect(projected[0].z == 2.0)
        #expect(projected[1].x == 3.0)
        #expect(projected[1].z == 4.0)
    }

    @Test("Y coordinate is discarded during projection")
    func yDiscarded() {
        let v1 = MeshVertex(x: 1.0, y: 100.0, z: 2.0)
        let v2 = MeshVertex(x: 1.0, y: -50.0, z: 2.0)

        let p1 = FloorPlanGenerationPipeline.projectToXZ(vertices: [v1])
        let p2 = FloorPlanGenerationPipeline.projectToXZ(vertices: [v2])

        #expect(p1[0].x == p2[0].x)
        #expect(p1[0].z == p2[0].z)
    }

    @Test("empty input returns empty output")
    func emptyProjection() {
        let projected = FloorPlanGenerationPipeline.projectToXZ(vertices: [])
        #expect(projected.isEmpty)
    }
}

// MARK: - Bounds Computation Tests

@Suite("FloorPlanGenerationPipeline — Bounds Computation")
struct BoundsComputationTests {

    @Test("computes correct bounding box with default padding")
    func correctBounds() {
        let points: [(x: Float, z: Float)] = [
            (x: 1.0, z: 2.0),
            (x: 5.0, z: 8.0),
            (x: 3.0, z: 4.0),
        ]

        let bounds = FloorPlanGenerationPipeline.computeBounds(points: points)
        #expect(bounds != nil)

        // With default 0.5m padding
        #expect(bounds!.minX == 0.5)   // 1.0 - 0.5
        #expect(bounds!.minZ == 1.5)   // 2.0 - 0.5
        #expect(bounds!.maxX == 5.5)   // 5.0 + 0.5
        #expect(bounds!.maxZ == 8.5)   // 8.0 + 0.5
    }

    @Test("returns nil for empty points")
    func emptyBounds() {
        let bounds = FloorPlanGenerationPipeline.computeBounds(points: [])
        #expect(bounds == nil)
    }

    @Test("custom padding works")
    func customPadding() {
        let points: [(x: Float, z: Float)] = [(x: 0, z: 0), (x: 10, z: 10)]
        let bounds = FloorPlanGenerationPipeline.computeBounds(points: points, padding: 1.0)

        #expect(bounds!.minX == -1.0)
        #expect(bounds!.minZ == -1.0)
        #expect(bounds!.maxX == 11.0)
        #expect(bounds!.maxZ == 11.0)
    }

    @Test("single point gets bounded correctly")
    func singlePoint() {
        let points: [(x: Float, z: Float)] = [(x: 5.0, z: 3.0)]
        let bounds = FloorPlanGenerationPipeline.computeBounds(points: points, padding: 0)

        #expect(bounds!.minX == 5.0)
        #expect(bounds!.maxX == 5.0)
        #expect(bounds!.minZ == 3.0)
        #expect(bounds!.maxZ == 3.0)
    }
}

// MARK: - Rasterization Tests

@Suite("FloorPlanGenerationPipeline — Rasterization")
struct RasterizationTests {

    @Test("rasterizes at 10px/m resolution")
    func rasterizesAtCorrectResolution() {
        let points: [(x: Float, z: Float)] = [
            (x: 0, z: 0),
            (x: 5, z: 5),
        ]
        let bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float) = (
            minX: 0, minZ: 0, maxX: 5, maxZ: 5
        )

        let (grid, width, height) = FloorPlanGenerationPipeline.rasterize(
            points: points,
            bounds: bounds,
            pixelsPerMeter: 10.0
        )

        // 5m * 10px/m = 50 pixels
        #expect(width == 50)
        #expect(height == 50)
        #expect(grid.count == 50 * 50)
    }

    @Test("rasterized grid contains correct density values")
    func correctDensity() {
        let points: [(x: Float, z: Float)] = [
            (x: 1.0, z: 1.0),
            (x: 1.0, z: 1.0),  // Same position — density should be 2
            (x: 2.0, z: 2.0),
        ]
        let bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float) = (
            minX: 0, minZ: 0, maxX: 3, maxZ: 3
        )

        let (grid, width, _) = FloorPlanGenerationPipeline.rasterize(
            points: points,
            bounds: bounds,
            pixelsPerMeter: 1.0
        )

        // At pixel (1, 1) there should be density 2
        #expect(grid[1 * width + 1] == 2.0)
        // At pixel (2, 2) there should be density 1
        #expect(grid[2 * width + 2] == 1.0)
        // At pixel (0, 0) there should be density 0
        #expect(grid[0] == 0.0)
    }

    @Test("handles empty points")
    func emptyRasterization() {
        let bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float) = (
            minX: 0, minZ: 0, maxX: 1, maxZ: 1
        )

        let (grid, width, height) = FloorPlanGenerationPipeline.rasterize(
            points: [],
            bounds: bounds
        )

        #expect(width > 0)
        #expect(height > 0)
        #expect(grid.allSatisfy { $0 == 0 })
    }

    @Test("out-of-bounds points are ignored")
    func outOfBoundsIgnored() {
        let points: [(x: Float, z: Float)] = [
            (x: -5, z: -5),  // Outside bounds
            (x: 100, z: 100),  // Outside bounds
            (x: 1, z: 1),  // Inside bounds
        ]
        let bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float) = (
            minX: 0, minZ: 0, maxX: 3, maxZ: 3
        )

        let (grid, _, _) = FloorPlanGenerationPipeline.rasterize(
            points: points,
            bounds: bounds,
            pixelsPerMeter: 1.0
        )

        // Only 1 point should have been rasterized
        let totalDensity = grid.reduce(0, +)
        #expect(totalDensity == 1.0)
    }
}

// MARK: - Gaussian Blur Tests

@Suite("FloorPlanGenerationPipeline — Gaussian Blur")
struct GaussianBlurTests {

    @Test("blur spreads single pixel to neighbors")
    func blurSpreads() {
        let width = 11
        let height = 11
        var grid = [Float](repeating: 0, count: width * height)
        // Place a single point in the center
        grid[5 * width + 5] = 10.0

        let blurred = FloorPlanGenerationPipeline.gaussianBlur(
            grid: grid,
            width: width,
            height: height,
            sigma: 2.0
        )

        // Center should still have the highest value
        let centerVal = blurred[5 * width + 5]
        #expect(centerVal > 0)

        // Adjacent pixels should have non-zero values
        let adjacent = blurred[5 * width + 4]
        #expect(adjacent > 0)

        // Corner far from center should be near zero
        let corner = blurred[0]
        #expect(corner < centerVal)
    }

    @Test("blur preserves total energy approximately")
    func preservesEnergy() {
        let width = 21
        let height = 21
        var grid = [Float](repeating: 0, count: width * height)
        grid[10 * width + 10] = 100.0

        let blurred = FloorPlanGenerationPipeline.gaussianBlur(
            grid: grid,
            width: width,
            height: height,
            sigma: 2.0
        )

        let inputSum = grid.reduce(0, +)
        let outputSum = blurred.reduce(0, +)

        // Energy should be approximately preserved (within 10% for a finite grid)
        let ratio = outputSum / inputSum
        #expect(ratio > 0.9)
        #expect(ratio < 1.1)
    }

    @Test("handles empty grid")
    func emptyGrid() {
        let result = FloorPlanGenerationPipeline.gaussianBlur(
            grid: [],
            width: 0,
            height: 0
        )
        #expect(result.isEmpty)
    }

    @Test("uniform grid stays uniform after blur")
    func uniformGrid() {
        let width = 10
        let height = 10
        let grid = [Float](repeating: 5.0, count: width * height)

        let blurred = FloorPlanGenerationPipeline.gaussianBlur(
            grid: grid,
            width: width,
            height: height,
            sigma: 2.0
        )

        // Interior pixels should remain approximately 5.0
        let centerVal = blurred[5 * width + 5]
        #expect(abs(centerVal - 5.0) < 0.1)
    }
}

// MARK: - Contour Detection Tests

@Suite("FloorPlanGenerationPipeline — Contour Detection")
struct ContourDetectionTests {

    @Test("detects edges at density boundaries")
    func detectsEdges() {
        let width = 5
        let height = 5
        // Create a grid with a filled square in the center
        var grid = [Float](repeating: 0, count: width * height)
        // Fill center 3x3 block
        for y in 1 ... 3 {
            for x in 1 ... 3 {
                grid[y * width + x] = 5.0
            }
        }

        let edges = FloorPlanGenerationPipeline.detectContours(
            grid: grid,
            width: width,
            height: height,
            threshold: 1.0
        )

        #expect(edges.count == width * height)

        // Center pixel (2,2) is NOT an edge — all neighbors are filled
        #expect(edges[2 * width + 2] == 0)

        // Pixel (1,1) IS an edge — neighbor at (0,0) is empty
        #expect(edges[1 * width + 1] == 1)
    }

    @Test("returns empty for empty grid")
    func emptyGrid() {
        let edges = FloorPlanGenerationPipeline.detectContours(
            grid: [],
            width: 0,
            height: 0
        )
        #expect(edges.isEmpty)
    }

    @Test("all-zero grid produces no edges")
    func zeroGrid() {
        let width = 5
        let height = 5
        let grid = [Float](repeating: 0, count: width * height)

        let edges = FloorPlanGenerationPipeline.detectContours(
            grid: grid,
            width: width,
            height: height,
            threshold: 1.0
        )

        #expect(edges.allSatisfy { $0 == 0 })
    }
}

// MARK: - CGImage Rendering Tests

@Suite("FloorPlanGenerationPipeline — CGImage Rendering")
struct CGImageRenderingTests {

    @Test("renders valid CGImage from edges")
    func rendersValidImage() {
        let width = 10
        let height = 10
        var edges = [UInt8](repeating: 0, count: width * height)
        edges[5 * width + 5] = 1  // One wall pixel

        let image = FloorPlanGenerationPipeline.renderCGImage(
            edges: edges,
            width: width,
            height: height
        )

        #expect(image != nil)
        #expect(image?.width == 10)
        #expect(image?.height == 10)
    }

    @Test("returns nil for mismatched dimensions")
    func nilForMismatch() {
        let edges = [UInt8](repeating: 0, count: 5)  // Too few for 10x10
        let image = FloorPlanGenerationPipeline.renderCGImage(
            edges: edges,
            width: 10,
            height: 10
        )
        #expect(image == nil)
    }

    @Test("returns nil for zero dimensions")
    func nilForZero() {
        let image = FloorPlanGenerationPipeline.renderCGImage(
            edges: [],
            width: 0,
            height: 0
        )
        #expect(image == nil)
    }
}

// MARK: - Full Pipeline Tests

@Suite("FloorPlanGenerationPipeline — Full Pipeline")
struct FullPipelineTests {

    @Test("generates floor plan from mesh vertices")
    func generatesFromMesh() {
        // Create a simple rectangular room (4m x 3m) with wall vertices
        var vertices: [MeshVertex] = []

        // North wall (z = 0)
        for i in 0 ..< 40 {
            let x = Float(i) * 0.1
            vertices.append(MeshVertex(x: x, y: 1.0, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 0))
            vertices.append(MeshVertex(x: x, y: 2.0, z: 0))
        }

        // South wall (z = 3)
        for i in 0 ..< 40 {
            let x = Float(i) * 0.1
            vertices.append(MeshVertex(x: x, y: 1.0, z: 3))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 3))
            vertices.append(MeshVertex(x: x, y: 2.0, z: 3))
        }

        // East wall (x = 4)
        for i in 0 ..< 30 {
            let z = Float(i) * 0.1
            vertices.append(MeshVertex(x: 4, y: 1.0, z: z))
            vertices.append(MeshVertex(x: 4, y: 1.5, z: z))
            vertices.append(MeshVertex(x: 4, y: 2.0, z: z))
        }

        // West wall (x = 0)
        for i in 0 ..< 30 {
            let z = Float(i) * 0.1
            vertices.append(MeshVertex(x: 0, y: 1.0, z: z))
            vertices.append(MeshVertex(x: 0, y: 1.5, z: z))
            vertices.append(MeshVertex(x: 0, y: 2.0, z: z))
        }

        var progressPhases: [FloorPlanGenerationPhase] = []
        let result = FloorPlanGenerationPipeline.generateFromMesh(
            vertices: vertices,
            floorY: 0
        ) { progress in
            progressPhases.append(progress.phase)
        }

        #expect(result != nil)
        #expect(result!.pixelWidth > 0)
        #expect(result!.pixelHeight > 0)
        #expect(result!.widthMeters > 3.0)  // At least 4m + padding
        #expect(result!.heightMeters > 2.0)  // At least 3m + padding

        // Progress phases should have been reported
        #expect(!progressPhases.isEmpty)
        #expect(progressPhases.contains(.filteringVertices))
        #expect(progressPhases.contains(.complete))
    }

    @Test("returns nil for insufficient data")
    func nilForInsufficientData() {
        let result = FloorPlanGenerationPipeline.generateFromMesh(vertices: [])
        #expect(result == nil)
    }

    @Test("returns nil when all vertices outside height range")
    func nilForWrongHeight() {
        let vertices = [
            MeshVertex(x: 0, y: 10, z: 0),  // Too high
            MeshVertex(x: 1, y: 10, z: 1),
        ]

        let result = FloorPlanGenerationPipeline.generateFromMesh(vertices: vertices)
        #expect(result == nil)
    }

    @Test("generates floor plan from plane anchors (non-LiDAR)")
    func generatesFromPlanes() {
        let planes = [
            PlaneVertex(startX: 0, startZ: 0, endX: 4, endZ: 0, width: 0.15),  // North wall
            PlaneVertex(startX: 4, startZ: 0, endX: 4, endZ: 3, width: 0.15),  // East wall
            PlaneVertex(startX: 4, startZ: 3, endX: 0, endZ: 3, width: 0.15),  // South wall
            PlaneVertex(startX: 0, startZ: 3, endX: 0, endZ: 0, width: 0.15),  // West wall
        ]

        let result = FloorPlanGenerationPipeline.generateFromPlanes(planes: planes)

        #expect(result != nil)
        #expect(result!.pixelWidth > 0)
        #expect(result!.pixelHeight > 0)
        #expect(result!.widthMeters > 3.0)
        #expect(result!.heightMeters > 2.0)
    }

    @Test("plane generation returns nil for empty planes")
    func nilForEmptyPlanes() {
        let result = FloorPlanGenerationPipeline.generateFromPlanes(planes: [])
        #expect(result == nil)
    }

    @Test("correct real-world dimensions from mesh")
    func correctDimensions() {
        // Create a 5m x 3m room
        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 5.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.5, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 3))
        }
        for z in stride(from: Float(0), through: 3.0, by: 0.1) {
            vertices.append(MeshVertex(x: 0, y: 1.5, z: z))
            vertices.append(MeshVertex(x: 5, y: 1.5, z: z))
        }

        let result = FloorPlanGenerationPipeline.generateFromMesh(vertices: vertices)
        #expect(result != nil)

        // Width should be close to 5m + 2*0.5m padding = 6m
        #expect(abs(result!.widthMeters - 6.0) < 0.2)
        // Height should be close to 3m + 2*0.5m padding = 4m
        #expect(abs(result!.heightMeters - 4.0) < 0.2)
    }

    @Test("10px/m rasterization resolution")
    func correctResolution() {
        // Create a simple 2m x 2m room at wall height
        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 2.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.0, z: 2))
        }

        let result = FloorPlanGenerationPipeline.generateFromMesh(vertices: vertices)
        #expect(result != nil)

        // With 0.5m padding: 3m * 10px/m = 30px each dimension
        // Pixel dimensions should be approximately width/height * 10
        let expectedWidth = Int(result!.widthMeters * 10)
        let expectedHeight = Int(result!.heightMeters * 10)
        #expect(abs(result!.pixelWidth - expectedWidth) <= 1)
        #expect(abs(result!.pixelHeight - expectedHeight) <= 1)
    }
}

// MARK: - Coverage Computation Tests

@Suite("FloorPlanGenerationPipeline — Coverage")
struct CoverageTests {

    @Test("computes coverage for scanned area")
    func computesCoverage() {
        var vertices: [MeshVertex] = []
        // Fill a 5m x 5m area
        for x in stride(from: Float(0), through: 5.0, by: 0.5) {
            for z in stride(from: Float(0), through: 5.0, by: 0.5) {
                vertices.append(MeshVertex(x: x, y: 1.5, z: z))
            }
        }

        let coverage = FloorPlanGenerationPipeline.computeCoverage(vertices: vertices)
        #expect(coverage != nil)
        #expect(coverage!.scannedAreaM2 > 0)
        #expect(coverage!.coveragePercent > 0)
        #expect(coverage!.scannedCells > 0)
    }

    @Test("returns nil for empty vertices")
    func nilForEmpty() {
        let coverage = FloorPlanGenerationPipeline.computeCoverage(vertices: [])
        #expect(coverage == nil)
    }

    @Test("returns nil when all vertices outside height range")
    func nilForWrongHeight() {
        let vertices = [MeshVertex(x: 0, y: 10, z: 0)]
        let coverage = FloorPlanGenerationPipeline.computeCoverage(vertices: vertices)
        #expect(coverage == nil)
    }
}

// MARK: - Preview Generation Tests

@Suite("FloorPlanGenerationPipeline — Preview")
struct PreviewTests {

    @Test("generates preview image from vertices")
    func generatesPreview() {
        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 5.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.5, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 5))
        }

        let preview = FloorPlanGenerationPipeline.generatePreview(vertices: vertices)
        #expect(preview != nil)
        #expect(preview!.width > 0)
        #expect(preview!.height > 0)
    }

    @Test("returns nil for empty vertices")
    func nilForEmpty() {
        let preview = FloorPlanGenerationPipeline.generatePreview(vertices: [])
        #expect(preview == nil)
    }
}

// MARK: - Missed Area Tests

@Suite("FloorPlanGenerationPipeline — Missed Areas")
struct MissedAreaTests {

    @Test("identifies missed areas")
    func identifiesMissedAreas() {
        // Scan only a few isolated points in a large area.
        // The bounding box extends 0-20m on both axes but only a few corners have data.
        let vertices: [MeshVertex] = [
            MeshVertex(x: 0, y: 1.5, z: 0),
            MeshVertex(x: 20, y: 1.5, z: 0),
            MeshVertex(x: 0, y: 1.5, z: 20),
            MeshVertex(x: 20, y: 1.5, z: 20),
        ]

        let result = FloorPlanGenerationPipeline.computeMissedAreas(
            vertices: vertices,
            gridResolution: 1.0 // 1 cell/m → 21x21 grid
        )
        #expect(result != nil)
        #expect(result!.width > 0)
        #expect(result!.height > 0)

        // Interior cells far from the 4 corners should be missed
        let missedCount = result!.grid.filter { $0 == 1 }.count
        #expect(missedCount > 0)
    }

    @Test("returns nil for empty vertices")
    func nilForEmpty() {
        let result = FloorPlanGenerationPipeline.computeMissedAreas(vertices: [])
        #expect(result == nil)
    }
}

// MARK: - FloorPlanGenerationViewModel Tests

@Suite("FloorPlanGenerationViewModel")
@MainActor
struct FloorPlanGenerationViewModelTests {

    @Test("initial state is correct")
    func initialState() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)
        #expect(!vm.isGenerating)
        #expect(vm.generationResult == nil)
        #expect(vm.previewImage == nil)
        #expect(vm.coverageInfo == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.vertexCount == 0)
        #expect(vm.planeCount == 0)
        #expect(!vm.hasEnoughData)
    }

    @Test("hasEnoughData requires 100+ vertices for LiDAR")
    func hasEnoughDataLiDAR() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Add 99 vertices — not enough
        var vertices: [MeshVertex] = []
        for i in 0 ..< 99 {
            vertices.append(MeshVertex(x: Float(i), y: 1.5, z: 0))
        }
        vm.addVertices(vertices)
        #expect(!vm.hasEnoughData)

        // Add one more — now enough
        vm.addVertices([MeshVertex(x: 100, y: 1.5, z: 0)])
        #expect(vm.hasEnoughData)
    }

    @Test("hasEnoughData requires 3+ planes for non-LiDAR")
    func hasEnoughDataNonLiDAR() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: false)

        // Add 2 planes — not enough
        vm.addPlanes([
            PlaneVertex(startX: 0, startZ: 0, endX: 1, endZ: 0, width: 0.1),
            PlaneVertex(startX: 1, startZ: 0, endX: 1, endZ: 1, width: 0.1),
        ])
        #expect(!vm.hasEnoughData)

        // Add one more — now enough
        vm.addPlanes([
            PlaneVertex(startX: 1, startZ: 1, endX: 0, endZ: 1, width: 0.1),
        ])
        #expect(vm.hasEnoughData)
    }

    @Test("generates floor plan from accumulated vertices")
    func generatesFloorPlan() async {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Add vertices for a rectangular room
        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 5.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.0, z: 3))
            vertices.append(MeshVertex(x: x, y: 1.5, z: 3))
        }
        for z in stride(from: Float(0), through: 3.0, by: 0.1) {
            vertices.append(MeshVertex(x: 0, y: 1.0, z: z))
            vertices.append(MeshVertex(x: 0, y: 1.5, z: z))
            vertices.append(MeshVertex(x: 5, y: 1.0, z: z))
            vertices.append(MeshVertex(x: 5, y: 1.5, z: z))
        }
        vm.addVertices(vertices)

        await vm.generateFloorPlan()

        #expect(vm.generationResult != nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isGenerating)
    }

    @Test("createFloorPlan produces FloorPlan with arGenerated origin")
    func createFloorPlanOrigin() async {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 3.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.0, z: 2))
        }
        for z in stride(from: Float(0), through: 2.0, by: 0.1) {
            vertices.append(MeshVertex(x: 0, y: 1.0, z: z))
            vertices.append(MeshVertex(x: 3, y: 1.0, z: z))
        }
        vm.addVertices(vertices)

        await vm.generateFloorPlan()

        let floorPlan = vm.createFloorPlan()
        #expect(floorPlan != nil)
        #expect(floorPlan?.origin == .arGenerated)
        #expect(floorPlan!.widthMeters > 0)
        #expect(floorPlan!.heightMeters > 0)
        #expect(floorPlan!.pixelWidth > 0)
        #expect(floorPlan!.pixelHeight > 0)
        #expect(!floorPlan!.imageData.isEmpty)
    }

    @Test("createSurveyProject produces project with arAssisted mode")
    func createSurveyProjectMode() async {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        var vertices: [MeshVertex] = []
        for x in stride(from: Float(0), through: 3.0, by: 0.1) {
            vertices.append(MeshVertex(x: x, y: 1.0, z: 0))
            vertices.append(MeshVertex(x: x, y: 1.0, z: 2))
        }
        vm.addVertices(vertices)

        await vm.generateFloorPlan()

        let project = vm.createSurveyProject(name: "Test Scan")
        #expect(project != nil)
        #expect(project?.name == "Test Scan")
        #expect(project?.surveyMode == .arAssisted)
        #expect(project?.floorPlan.origin == .arGenerated)
    }

    @Test("reset clears all state")
    func resetClearsState() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        vm.addVertices([MeshVertex(x: 0, y: 1.0, z: 0)])

        vm.reset()

        #expect(vm.vertexCount == 0)
        #expect(vm.planeCount == 0)
        #expect(!vm.isGenerating)
        #expect(vm.generationResult == nil)
        #expect(vm.previewImage == nil)
        #expect(vm.coverageInfo == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test("generation with insufficient data sets error message")
    func insufficientDataError() async {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)

        // Don't add any vertices
        await vm.generateFloorPlan()

        #expect(vm.generationResult == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("discardRawMeshData frees vertex memory")
    func discardRawData() {
        let vm = FloorPlanGenerationViewModel(isLiDAR: true)
        vm.addVertices([MeshVertex(x: 0, y: 1.0, z: 0)])
        #expect(vm.vertexCount == 1)

        vm.discardRawMeshData()
        #expect(vm.vertexCount == 0)
    }
}

// MARK: - MeshVertex Tests

@Suite("MeshVertex")
struct MeshVertexTests {

    @Test("equality works correctly")
    func equality() {
        let v1 = MeshVertex(x: 1.0, y: 2.0, z: 3.0)
        let v2 = MeshVertex(x: 1.0, y: 2.0, z: 3.0)
        let v3 = MeshVertex(x: 1.0, y: 2.0, z: 4.0)
        #expect(v1 == v2)
        #expect(v1 != v3)
    }
}

// MARK: - PlaneVertex Tests

@Suite("PlaneVertex")
struct PlaneVertexTests {

    @Test("equality works correctly")
    func equality() {
        let p1 = PlaneVertex(startX: 0, startZ: 0, endX: 1, endZ: 0, width: 0.1)
        let p2 = PlaneVertex(startX: 0, startZ: 0, endX: 1, endZ: 0, width: 0.1)
        #expect(p1 == p2)
    }
}
