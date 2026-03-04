import CoreGraphics
import Foundation
import os
import simd

// MARK: - MeshClassification

/// Classification of an AR mesh face/vertex for floor plan rendering.
/// Maps to ARMeshClassification values from ARKit.
enum MeshClassification: Int, Sendable, Equatable {
    case none = 0
    case wall = 1
    case floor = 2
    case ceiling = 3
    case table = 4
    case seat = 5
    case window = 6
    case door = 7
}

// MARK: - MeshVertex

/// A 3D vertex from AR mesh data, in world coordinates.
struct MeshVertex: Sendable, Equatable {
    let x: Float
    let y: Float
    let z: Float
    /// Optional mesh classification from LiDAR scene reconstruction.
    let classification: MeshClassification

    init(x: Float, y: Float, z: Float, classification: MeshClassification = .none) {
        self.x = x
        self.y = y
        self.z = z
        self.classification = classification
    }
}

// MARK: - PlaneVertex

/// A vertical plane anchor represented as a line segment in the XZ plane.
/// Used for non-LiDAR floor plan generation from ARPlaneAnchor data.
struct PlaneVertex: Sendable, Equatable {
    let startX: Float
    let startZ: Float
    let endX: Float
    let endZ: Float
    let width: Float
}

// MARK: - FloorPlanGenerationProgress

/// Progress state for floor plan generation pipeline.
struct FloorPlanGenerationProgress: Sendable, Equatable {
    let phase: FloorPlanGenerationPhase
    let fractionComplete: Double
    let message: String
}

// MARK: - FloorPlanGenerationPhase

/// Phases of the floor plan generation pipeline.
enum FloorPlanGenerationPhase: Sendable, Equatable {
    case collectingMesh
    case filteringVertices
    case projecting
    case rasterizing
    case blurring
    case detectingContours
    case complete
}

// MARK: - ScanCoverageInfo

/// Coverage information for the current AR scan.
struct ScanCoverageInfo: Sendable, Equatable {
    /// Estimated scanned area in square meters.
    let scannedAreaM2: Double
    /// Bounding box of scanned area in meters.
    let boundsWidthM: Double
    let boundsHeightM: Double
    /// Coverage percentage (0-100) based on rasterized occupancy.
    let coveragePercent: Double
    /// Cells that have been scanned (for missed area visualization).
    let scannedCells: Int
    /// Total cells in the bounding box.
    let totalCells: Int
}

// MARK: - FloorPlanGenerationResult

/// Result of floor plan generation pipeline.
struct FloorPlanGenerationResult: Sendable {
    let image: CGImage
    let widthMeters: Double
    let heightMeters: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let originX: Double
    let originZ: Double
}

// MARK: - FloorPlanGenerationPipeline

/// Pipeline for generating 2D floor plans from AR mesh data.
///
/// Steps:
/// 1. Collect ARMeshAnchor geometry (vertices)
/// 2. Height-filter vertices (0.5-2.5m above floor)
/// 3. Project to XZ plane (top-down 2D)
/// 4. Rasterize at 10px/m resolution
/// 5. Gaussian blur (sigma=2px) for wall continuity
/// 6. Edge/contour detection for clean wall lines
/// 7. Render as CGImage (black walls on white background)
///
/// All pipeline math is pure functions for testability.
enum FloorPlanGenerationPipeline {

    // MARK: - Configuration

    /// Minimum height above floor to capture walls (meters).
    static let minHeight: Float = 0.5
    /// Maximum height above floor to capture walls (meters).
    static let maxHeight: Float = 2.5
    /// Rasterization resolution in pixels per meter.
    static let pixelsPerMeter: Float = 10.0
    /// Gaussian blur sigma in pixels.
    static let blurSigma: Float = 2.0
    /// Padding around the bounding box in meters.
    static let paddingMeters: Float = 0.5

    // MARK: - Step 1: Height Filtering

    /// Filters vertices to those within the wall height range (0.5-2.5m above floor).
    ///
    /// - Parameters:
    ///   - vertices: Raw 3D vertices from AR mesh.
    ///   - floorY: The Y coordinate of the detected floor plane (default 0).
    ///   - minHeight: Minimum height above floor.
    ///   - maxHeight: Maximum height above floor.
    /// - Returns: Vertices within the specified height range.
    static func heightFilter(
        vertices: [MeshVertex],
        floorY: Float = 0,
        minHeight: Float = FloorPlanGenerationPipeline.minHeight,
        maxHeight: Float = FloorPlanGenerationPipeline.maxHeight
    ) -> [MeshVertex] {
        vertices.filter { vertex in
            let heightAboveFloor = vertex.y - floorY
            return heightAboveFloor >= minHeight && heightAboveFloor <= maxHeight
        }
    }

    // MARK: - Step 2: XZ Projection

    /// Projects 3D vertices to 2D XZ plane (top-down view).
    ///
    /// - Parameter vertices: Height-filtered 3D vertices.
    /// - Returns: Array of (x, z) 2D points in world coordinates.
    static func projectToXZ(vertices: [MeshVertex]) -> [(x: Float, z: Float)] {
        vertices.map { (x: $0.x, z: $0.z) }
    }

    /// Projects 3D vertices to 2D XZ plane preserving classification.
    ///
    /// - Parameter vertices: Height-filtered 3D vertices with classification.
    /// - Returns: Array of classified 2D points.
    static func projectToXZClassified(
        vertices: [MeshVertex]
    ) -> [(x: Float, z: Float, classification: MeshClassification)] {
        vertices.map { (x: $0.x, z: $0.z, classification: $0.classification) }
    }

    // MARK: - Step 3: Compute Bounds

    /// Computes the axis-aligned bounding box of 2D points with padding.
    ///
    /// - Parameters:
    ///   - points: 2D projected points.
    ///   - padding: Padding in meters around the bounding box.
    /// - Returns: (minX, minZ, maxX, maxZ) bounding box, or nil if points is empty.
    static func computeBounds(
        points: [(x: Float, z: Float)],
        padding: Float = FloorPlanGenerationPipeline.paddingMeters
    ) -> (minX: Float, minZ: Float, maxX: Float, maxZ: Float)? {
        guard let first = points.first else { return nil }

        var minX = first.x
        var minZ = first.z
        var maxX = first.x
        var maxZ = first.z

        for point in points {
            minX = min(minX, point.x)
            minZ = min(minZ, point.z)
            maxX = max(maxX, point.x)
            maxZ = max(maxZ, point.z)
        }

        return (
            minX: minX - padding,
            minZ: minZ - padding,
            maxX: maxX + padding,
            maxZ: maxZ + padding
        )
    }

    // MARK: - Step 4: Rasterization

    /// Rasterizes 2D points onto a pixel grid.
    ///
    /// - Parameters:
    ///   - points: 2D projected points in world coordinates.
    ///   - bounds: Bounding box (minX, minZ, maxX, maxZ).
    ///   - pixelsPerMeter: Resolution in pixels per meter.
    /// - Returns: (grid, width, height) where grid is a row-major 2D array of density values.
    static func rasterize(
        points: [(x: Float, z: Float)],
        bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float),
        pixelsPerMeter: Float = FloorPlanGenerationPipeline.pixelsPerMeter
    ) -> (grid: [Float], width: Int, height: Int) {
        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        let pixelWidth = max(1, Int(ceil(worldWidth * pixelsPerMeter)))
        let pixelHeight = max(1, Int(ceil(worldHeight * pixelsPerMeter)))

        var grid = [Float](repeating: 0, count: pixelWidth * pixelHeight)

        for point in points {
            let px = Int((point.x - bounds.minX) * pixelsPerMeter)
            let pz = Int((point.z - bounds.minZ) * pixelsPerMeter)

            guard px >= 0, px < pixelWidth, pz >= 0, pz < pixelHeight else { continue }

            let index = pz * pixelWidth + px
            grid[index] += 1.0
        }

        return (grid: grid, width: pixelWidth, height: pixelHeight)
    }

    // MARK: - Step 5: Gaussian Blur

    /// Applies a Gaussian blur to the rasterized grid for wall continuity.
    ///
    /// - Parameters:
    ///   - grid: Row-major 2D grid of values.
    ///   - width: Grid width in pixels.
    ///   - height: Grid height in pixels.
    ///   - sigma: Gaussian sigma in pixels (default 2.0).
    /// - Returns: Blurred grid of same dimensions.
    static func gaussianBlur(
        grid: [Float],
        width: Int,
        height: Int,
        sigma: Float = FloorPlanGenerationPipeline.blurSigma
    ) -> [Float] {
        guard width > 0, height > 0, !grid.isEmpty else { return grid }

        let kernelRadius = Int(ceil(sigma * 3))
        let kernelSize = kernelRadius * 2 + 1
        var kernel = [Float](repeating: 0, count: kernelSize)

        // Generate 1D Gaussian kernel
        let sigma2 = 2.0 * sigma * sigma
        var kernelSum: Float = 0
        for i in 0 ..< kernelSize {
            let x = Float(i - kernelRadius)
            kernel[i] = exp(-x * x / sigma2)
            kernelSum += kernel[i]
        }
        // Normalize kernel
        for i in 0 ..< kernelSize {
            kernel[i] /= kernelSum
        }

        // Separable blur: horizontal pass
        var temp = [Float](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var sum: Float = 0
                for k in 0 ..< kernelSize {
                    let sx = x + k - kernelRadius
                    let clampedX = max(0, min(width - 1, sx))
                    sum += grid[y * width + clampedX] * kernel[k]
                }
                temp[y * width + x] = sum
            }
        }

        // Separable blur: vertical pass
        var result = [Float](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var sum: Float = 0
                for k in 0 ..< kernelSize {
                    let sy = y + k - kernelRadius
                    let clampedY = max(0, min(height - 1, sy))
                    sum += temp[clampedY * width + x] * kernel[k]
                }
                result[y * width + x] = sum
            }
        }

        return result
    }

    // MARK: - Step 6: Threshold + Contour Detection

    /// Applies threshold to blurred grid and extracts contour edges.
    /// Produces a binary image where walls are detected edges.
    ///
    /// - Parameters:
    ///   - grid: Blurred density grid.
    ///   - width: Grid width in pixels.
    ///   - height: Grid height in pixels.
    ///   - threshold: Minimum density to consider as wall material.
    /// - Returns: Binary grid (0 or 1) representing wall edges.
    static func detectContours(
        grid: [Float],
        width: Int,
        height: Int,
        threshold: Float? = nil
    ) -> [UInt8] {
        guard width > 0, height > 0, !grid.isEmpty else { return [] }

        // Auto-threshold using Otsu-like approach: use a fraction of max value
        let maxVal = grid.max() ?? 0
        let effectiveThreshold = threshold ?? max(maxVal * 0.15, 0.1)

        // Threshold to binary
        var binary = [UInt8](repeating: 0, count: width * height)
        for i in 0 ..< grid.count {
            binary[i] = grid[i] >= effectiveThreshold ? 1 : 0
        }

        // Simple Sobel-like edge detection
        var edges = [UInt8](repeating: 0, count: width * height)
        for y in 1 ..< (height - 1) {
            for x in 1 ..< (width - 1) {
                let center = binary[y * width + x]
                guard center == 1 else { continue }

                // Check if any neighbor is 0 (edge pixel)
                let top = binary[(y - 1) * width + x]
                let bottom = binary[(y + 1) * width + x]
                let left = binary[y * width + (x - 1)]
                let right = binary[y * width + (x + 1)]

                if top == 0 || bottom == 0 || left == 0 || right == 0 {
                    edges[y * width + x] = 1
                }
            }
        }

        return edges
    }

    // MARK: - Step 7: Render CGImage

    /// Renders binary edge data as a CGImage (black walls on white background).
    ///
    /// - Parameters:
    ///   - edges: Binary edge grid (0 = background, 1 = wall).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: CGImage with black walls on white background, or nil on failure.
    static func renderCGImage(
        edges: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0, edges.count == width * height else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let srcIndex = y * width + x
                let dstIndex = y * bytesPerRow + x * 4
                let isWall = edges[srcIndex] == 1

                pixels[dstIndex] = isWall ? 0 : 255     // R
                pixels[dstIndex + 1] = isWall ? 0 : 255 // G
                pixels[dstIndex + 2] = isWall ? 0 : 255 // B
                pixels[dstIndex + 3] = 255               // A (opaque)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    // MARK: - Step 7b: Classified Rendering (P1)

    /// Renders a floor plan with mesh classification: doors as gaps, windows as dashed lines.
    ///
    /// - Parameters:
    ///   - edges: Binary edge grid (0 = background, 1 = wall).
    ///   - classificationGrid: Per-pixel dominant classification (same dimensions as edges).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: CGImage with walls=black, doors=white gaps, windows=grey dashed.
    static func renderClassifiedCGImage(
        edges: [UInt8],
        classificationGrid: [MeshClassification],
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0,
              edges.count == width * height,
              classificationGrid.count == width * height
        else {
            return renderCGImage(edges: edges, width: width, height: height)
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let srcIndex = y * width + x
                let dstIndex = y * bytesPerRow + x * 4
                let isWall = edges[srcIndex] == 1
                let classification = classificationGrid[srcIndex]

                if isWall {
                    switch classification {
                    case .door:
                        // Doors rendered as gaps (white/transparent)
                        pixels[dstIndex] = 255     // R
                        pixels[dstIndex + 1] = 255 // G
                        pixels[dstIndex + 2] = 255 // B
                        pixels[dstIndex + 3] = 255 // A
                    case .window:
                        // Windows rendered as dashed grey (checkerboard pattern)
                        let isDash = (x + y) % 4 < 2
                        let grey: UInt8 = isDash ? 128 : 255
                        pixels[dstIndex] = grey     // R
                        pixels[dstIndex + 1] = grey // G
                        pixels[dstIndex + 2] = grey // B
                        pixels[dstIndex + 3] = 255  // A
                    default:
                        // Regular walls: black
                        pixels[dstIndex] = 0       // R
                        pixels[dstIndex + 1] = 0   // G
                        pixels[dstIndex + 2] = 0   // B
                        pixels[dstIndex + 3] = 255 // A
                    }
                } else {
                    // Background: white
                    pixels[dstIndex] = 255     // R
                    pixels[dstIndex + 1] = 255 // G
                    pixels[dstIndex + 2] = 255 // B
                    pixels[dstIndex + 3] = 255 // A
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    /// Rasterizes classified points onto a grid, tracking dominant classification per cell.
    ///
    /// - Parameters:
    ///   - points: Classified 2D projected points.
    ///   - bounds: Bounding box.
    ///   - pixelsPerMeter: Resolution.
    /// - Returns: (grid, classificationGrid, width, height).
    static func rasterizeClassified(
        points: [(x: Float, z: Float, classification: MeshClassification)],
        bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float),
        pixelsPerMeter: Float = FloorPlanGenerationPipeline.pixelsPerMeter
    ) -> (grid: [Float], classificationGrid: [MeshClassification], width: Int, height: Int) {
        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        let pixelWidth = max(1, Int(ceil(worldWidth * pixelsPerMeter)))
        let pixelHeight = max(1, Int(ceil(worldHeight * pixelsPerMeter)))

        var grid = [Float](repeating: 0, count: pixelWidth * pixelHeight)
        // Track classification votes per cell
        var classVotes = [[Int]](repeating: [Int](repeating: 0, count: 8), count: pixelWidth * pixelHeight)

        for point in points {
            let px = Int((point.x - bounds.minX) * pixelsPerMeter)
            let pz = Int((point.z - bounds.minZ) * pixelsPerMeter)

            guard px >= 0, px < pixelWidth, pz >= 0, pz < pixelHeight else { continue }

            let index = pz * pixelWidth + px
            grid[index] += 1.0
            classVotes[index][point.classification.rawValue] += 1
        }

        // Determine dominant classification per cell
        var classificationGrid = [MeshClassification](
            repeating: .none,
            count: pixelWidth * pixelHeight
        )
        for i in 0 ..< classVotes.count {
            var maxVotes = 0
            var dominant = MeshClassification.none
            for (rawValue, votes) in classVotes[i].enumerated() {
                if votes > maxVotes {
                    maxVotes = votes
                    if let cls = MeshClassification(rawValue: rawValue) {
                        dominant = cls
                    }
                }
            }
            classificationGrid[i] = dominant
        }

        return (grid: grid, classificationGrid: classificationGrid, width: pixelWidth, height: pixelHeight)
    }

    // MARK: - Full Pipeline (LiDAR)

    /// Runs the complete floor plan generation pipeline from mesh vertices.
    ///
    /// - Parameters:
    ///   - vertices: Raw 3D vertices from ARMeshAnchor data.
    ///   - floorY: Y coordinate of the floor (default 0).
    ///   - progressHandler: Optional callback for progress updates.
    /// - Returns: Generated floor plan result, or nil if insufficient data.
    static func generateFromMesh(
        vertices: [MeshVertex],
        floorY: Float = 0,
        progressHandler: ((FloorPlanGenerationProgress) -> Void)? = nil
    ) -> FloorPlanGenerationResult? {
        progressHandler?(FloorPlanGenerationProgress(
            phase: .filteringVertices,
            fractionComplete: 0.1,
            message: "Filtering wall vertices…"
        ))

        // Step 1: Height filter
        let filtered = heightFilter(vertices: vertices, floorY: floorY)
        guard !filtered.isEmpty else { return nil }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .projecting,
            fractionComplete: 0.2,
            message: "Projecting to 2D…"
        ))

        // Step 2: Project to XZ
        let points2D = projectToXZ(vertices: filtered)

        // Step 3: Compute bounds
        guard let bounds = computeBounds(points: points2D) else { return nil }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .rasterizing,
            fractionComplete: 0.4,
            message: "Rasterizing floor plan…"
        ))

        // Step 4: Rasterize
        let (grid, rWidth, rHeight) = rasterize(points: points2D, bounds: bounds)

        progressHandler?(FloorPlanGenerationProgress(
            phase: .blurring,
            fractionComplete: 0.6,
            message: "Smoothing walls…"
        ))

        // Step 5: Gaussian blur
        let blurred = gaussianBlur(grid: grid, width: rWidth, height: rHeight)

        progressHandler?(FloorPlanGenerationProgress(
            phase: .detectingContours,
            fractionComplete: 0.8,
            message: "Detecting wall contours…"
        ))

        // Step 6: Contour detection
        let edges = detectContours(grid: blurred, width: rWidth, height: rHeight)

        // Step 7: Render
        guard let image = renderCGImage(edges: edges, width: rWidth, height: rHeight) else {
            return nil
        }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .complete,
            fractionComplete: 1.0,
            message: "Floor plan generated"
        ))

        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        return FloorPlanGenerationResult(
            image: image,
            widthMeters: Double(worldWidth),
            heightMeters: Double(worldHeight),
            pixelWidth: rWidth,
            pixelHeight: rHeight,
            originX: Double(bounds.minX),
            originZ: Double(bounds.minZ)
        )
    }

    // MARK: - Full Pipeline (Non-LiDAR / Plane Anchors)

    /// Generates a floor plan from ARPlaneAnchor vertical planes (non-LiDAR fallback).
    ///
    /// - Parameters:
    ///   - planes: Vertical plane segments detected by ARKit.
    ///   - progressHandler: Optional callback for progress updates.
    /// - Returns: Generated floor plan result, or nil if insufficient data.
    static func generateFromPlanes(
        planes: [PlaneVertex],
        progressHandler: ((FloorPlanGenerationProgress) -> Void)? = nil
    ) -> FloorPlanGenerationResult? {
        guard !planes.isEmpty else { return nil }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .projecting,
            fractionComplete: 0.2,
            message: "Processing wall planes…"
        ))

        // Collect all segment endpoints and intermediate points as XZ points
        var points2D: [(x: Float, z: Float)] = []
        for plane in planes {
            // Sample points along the plane segment
            let dx = plane.endX - plane.startX
            let dz = plane.endZ - plane.startZ
            let length = sqrt(dx * dx + dz * dz)
            let steps = max(1, Int(ceil(length * pixelsPerMeter)))

            for i in 0 ... steps {
                let t = Float(i) / Float(steps)
                let px = plane.startX + dx * t
                let pz = plane.startZ + dz * t
                points2D.append((x: px, z: pz))

                // Add width perpendicular to the segment for thickness
                if plane.width > 0 {
                    let nx = -dz / length * plane.width * 0.5
                    let nz = dx / length * plane.width * 0.5
                    points2D.append((x: px + nx, z: pz + nz))
                    points2D.append((x: px - nx, z: pz - nz))
                }
            }
        }

        guard !points2D.isEmpty else { return nil }

        // Compute bounds
        guard let bounds = computeBounds(points: points2D) else { return nil }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .rasterizing,
            fractionComplete: 0.4,
            message: "Rasterizing floor plan…"
        ))

        // Rasterize
        let (grid, rWidth, rHeight) = rasterize(points: points2D, bounds: bounds)

        progressHandler?(FloorPlanGenerationProgress(
            phase: .blurring,
            fractionComplete: 0.6,
            message: "Smoothing walls…"
        ))

        // Gaussian blur with larger sigma for plane-based data (less precise)
        let blurred = gaussianBlur(grid: grid, width: rWidth, height: rHeight, sigma: 3.0)

        progressHandler?(FloorPlanGenerationProgress(
            phase: .detectingContours,
            fractionComplete: 0.8,
            message: "Detecting wall contours…"
        ))

        // Contour detection
        let edges = detectContours(grid: blurred, width: rWidth, height: rHeight)

        // Render
        guard let image = renderCGImage(edges: edges, width: rWidth, height: rHeight) else {
            return nil
        }

        progressHandler?(FloorPlanGenerationProgress(
            phase: .complete,
            fractionComplete: 1.0,
            message: "Floor plan generated"
        ))

        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        return FloorPlanGenerationResult(
            image: image,
            widthMeters: Double(worldWidth),
            heightMeters: Double(worldHeight),
            pixelWidth: rWidth,
            pixelHeight: rHeight,
            originX: Double(bounds.minX),
            originZ: Double(bounds.minZ)
        )
    }

    // MARK: - Coverage Computation

    /// Computes scan coverage information from accumulated mesh vertices.
    ///
    /// - Parameters:
    ///   - vertices: All collected vertices (before height filtering).
    ///   - floorY: Floor Y coordinate.
    /// - Returns: Coverage info, or nil if no vertices.
    static func computeCoverage(
        vertices: [MeshVertex],
        floorY: Float = 0
    ) -> ScanCoverageInfo? {
        let filtered = heightFilter(vertices: vertices, floorY: floorY)
        guard !filtered.isEmpty else { return nil }

        let points2D = projectToXZ(vertices: filtered)
        guard let bounds = computeBounds(points: points2D, padding: 0) else { return nil }

        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        // Use a coarser grid (1px/m) for coverage computation
        let coveragePPM: Float = 1.0
        let gridWidth = max(1, Int(ceil(worldWidth * coveragePPM)))
        let gridHeight = max(1, Int(ceil(worldHeight * coveragePPM)))
        let totalCells = gridWidth * gridHeight

        var occupiedCells = Set<Int>()
        for point in points2D {
            let px = Int((point.x - bounds.minX) * coveragePPM)
            let pz = Int((point.z - bounds.minZ) * coveragePPM)
            guard px >= 0, px < gridWidth, pz >= 0, pz < gridHeight else { continue }
            occupiedCells.insert(pz * gridWidth + px)
        }

        let scannedCells = occupiedCells.count
        let coveragePercent = totalCells > 0 ? Double(scannedCells) / Double(totalCells) * 100 : 0

        return ScanCoverageInfo(
            scannedAreaM2: Double(worldWidth * worldHeight),
            boundsWidthM: Double(worldWidth),
            boundsHeightM: Double(worldHeight),
            coveragePercent: min(100, coveragePercent),
            scannedCells: scannedCells,
            totalCells: totalCells
        )
    }

    // MARK: - Real-Time Preview

    /// Generates a quick low-resolution preview image from current vertices.
    /// Used for real-time 2D preview during scanning.
    ///
    /// - Parameters:
    ///   - vertices: Current accumulated vertices.
    ///   - floorY: Floor Y coordinate.
    /// - Returns: Quick preview CGImage, or nil if insufficient data.
    static func generatePreview(
        vertices: [MeshVertex],
        floorY: Float = 0
    ) -> CGImage? {
        let filtered = heightFilter(vertices: vertices, floorY: floorY)
        guard !filtered.isEmpty else { return nil }

        let points2D = projectToXZ(vertices: filtered)
        guard let bounds = computeBounds(points: points2D) else { return nil }

        // Use lower resolution for real-time preview (5px/m instead of 10)
        let previewPPM: Float = 5.0
        let (grid, rWidth, rHeight) = rasterize(
            points: points2D,
            bounds: bounds,
            pixelsPerMeter: previewPPM
        )

        // Lighter blur for speed
        let blurred = gaussianBlur(grid: grid, width: rWidth, height: rHeight, sigma: 1.5)

        // Threshold without full edge detection for speed
        let maxVal = blurred.max() ?? 0
        let thresh = max(maxVal * 0.1, 0.05)
        var binary = [UInt8](repeating: 0, count: rWidth * rHeight)
        for i in 0 ..< blurred.count {
            binary[i] = blurred[i] >= thresh ? 1 : 0
        }

        return renderCGImage(edges: binary, width: rWidth, height: rHeight)
    }

    // MARK: - Missed Area Grid

    /// Generates a grid indicating which areas have NOT been scanned.
    /// Returns a binary grid where 1 = missed, 0 = scanned.
    ///
    /// - Parameters:
    ///   - vertices: All accumulated vertices.
    ///   - floorY: Floor Y coordinate.
    ///   - gridResolution: Resolution for missed area detection (pixels per meter).
    /// - Returns: (missedGrid, width, height, bounds) or nil if insufficient data.
    static func computeMissedAreas(
        vertices: [MeshVertex],
        floorY: Float = 0,
        gridResolution: Float = 2.0
    ) -> (grid: [UInt8], width: Int, height: Int,
          bounds: (minX: Float, minZ: Float, maxX: Float, maxZ: Float))? {
        let filtered = heightFilter(vertices: vertices, floorY: floorY)
        guard !filtered.isEmpty else { return nil }

        let points2D = projectToXZ(vertices: filtered)
        guard let bounds = computeBounds(points: points2D) else { return nil }

        let worldWidth = bounds.maxX - bounds.minX
        let worldHeight = bounds.maxZ - bounds.minZ

        let gridWidth = max(1, Int(ceil(worldWidth * gridResolution)))
        let gridHeight = max(1, Int(ceil(worldHeight * gridResolution)))

        var scanned = [Bool](repeating: false, count: gridWidth * gridHeight)

        // Mark scanned cells and their neighbors within 1m radius
        let radiusCells = Int(ceil(gridResolution)) // 1m radius
        for point in points2D {
            let cx = Int((point.x - bounds.minX) * gridResolution)
            let cz = Int((point.z - bounds.minZ) * gridResolution)

            for dy in -radiusCells ... radiusCells {
                for dx in -radiusCells ... radiusCells {
                    let nx = cx + dx
                    let ny = cz + dy
                    if nx >= 0, nx < gridWidth, ny >= 0, ny < gridHeight {
                        if dx * dx + dy * dy <= radiusCells * radiusCells {
                            scanned[ny * gridWidth + nx] = true
                        }
                    }
                }
            }
        }

        // Invert: missed = not scanned
        var missed = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        for i in 0 ..< scanned.count {
            missed[i] = scanned[i] ? 0 : 1
        }

        return (grid: missed, width: gridWidth, height: gridHeight, bounds: bounds)
    }
}
