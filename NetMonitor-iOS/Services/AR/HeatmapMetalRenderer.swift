import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

#if os(iOS)
import Metal
import MetalKit
#endif

// MARK: - GaussianSplat

/// Pure-function Gaussian splat math for heatmap coloring.
/// Each measurement paints a circular Gaussian splat of radius ~1.5m.
enum GaussianSplat {

    /// Default splat radius in meters.
    static let defaultRadius: Float = 1.5

    /// Sigma for the Gaussian (chosen so that at distance=radius, weight ≈ 0.135).
    /// sigma = radius / sqrt(4.0) = radius / 2
    static let sigmaFactor: Float = 2.0

    /// Calculates the Gaussian weight at a given distance from the splat center.
    ///
    /// - Parameters:
    ///   - distance: Distance from center in meters.
    ///   - radius: Splat radius in meters.
    /// - Returns: Weight in [0, 1] where 1 is at center.
    static func weight(distance: Float, radius: Float) -> Float {
        guard radius > 0 else { return 0 }
        let sigma = radius / sigmaFactor
        let exponent = -(distance * distance) / (2.0 * sigma * sigma)
        return exp(exponent)
    }

    /// Converts a meter-based radius to pixel radius.
    ///
    /// - Parameters:
    ///   - metersRadius: Radius in meters.
    ///   - pixelsPerMeter: The texture's pixels-per-meter scale.
    /// - Returns: Radius in pixels (integer).
    static func pixelRadius(metersRadius: Float, pixelsPerMeter: Float) -> Int {
        Int(metersRadius * pixelsPerMeter)
    }
}

// MARK: - WiFimanColorMapper

/// Maps RSSI values to WiFiman color scheme (blue→cyan→green→yellow→orange→red).
///
/// Color bands:
/// - Blue/Cyan: -30 to -50 dBm (excellent)
/// - Green: -50 to -60 dBm (good)
/// - Yellow: -60 to -70 dBm (fair)
/// - Orange: -70 to -80 dBm (weak)
/// - Red: -80 to -90+ dBm (dead zone)
enum WiFimanColorMapper {

    /// RGBA color with Float components in [0, 1].
    struct RGBAColor: Sendable, Equatable {
        let red: Float
        let green: Float
        let blue: Float
        let alpha: Float

        init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    /// Maps an RSSI value to the WiFiman color scheme.
    ///
    /// - Parameter rssi: Signal strength in dBm (typically -30 to -90).
    /// - Returns: An RGBA color following the WiFiman gradient.
    static func color(forRSSI rssi: Int) -> RGBAColor {
        // Normalize to 0.0 (worst, -90) – 1.0 (best, -30)
        let clamped = min(-30, max(-90, rssi))
        let ratio = Float(clamped - -90) / Float(-30 - -90) // 0=worst, 1=best

        return wifimanGradient(ratio: ratio)
    }

    /// Maps a normalized ratio through the WiFiman 6-color gradient.
    /// 0→red, 0.2→orange, 0.4→yellow, 0.6→green, 0.8→cyan, 1.0→blue.
    static func wifimanGradient(ratio: Float) -> RGBAColor {
        let r = max(0, min(1, ratio))

        if r <= 0.2 {
            // Red (1,0,0) → Orange (1,0.5,0)
            let seg = r / 0.2
            return RGBAColor(red: 1.0, green: 0.5 * seg, blue: 0.0)
        } else if r <= 0.4 {
            // Orange (1,0.5,0) → Yellow (1,1,0)
            let seg = (r - 0.2) / 0.2
            return RGBAColor(red: 1.0, green: 0.5 + 0.5 * seg, blue: 0.0)
        } else if r <= 0.6 {
            // Yellow (1,1,0) → Green (0,1,0)
            let seg = (r - 0.4) / 0.2
            return RGBAColor(red: 1.0 - seg, green: 1.0, blue: 0.0)
        } else if r <= 0.8 {
            // Green (0,1,0) → Cyan (0,1,1)
            let seg = (r - 0.6) / 0.2
            return RGBAColor(red: 0.0, green: 1.0, blue: seg)
        } else {
            // Cyan (0,1,1) → Blue (0,0.4,1)
            let seg = (r - 0.8) / 0.2
            return RGBAColor(red: 0.0, green: 1.0 - 0.6 * seg, blue: 1.0)
        }
    }

    /// Converts an RGBA color to a packed UInt32 (RGBA8 format).
    static func packRGBA(_ color: RGBAColor, alpha: Float = 0.85) -> UInt32 {
        let r = UInt32(max(0, min(255, color.red * 255)))
        let g = UInt32(max(0, min(255, color.green * 255)))
        let b = UInt32(max(0, min(255, color.blue * 255)))
        let a = UInt32(max(0, min(255, alpha * 255)))
        return r | (g << 8) | (b << 16) | (a << 24)
    }
}

// MARK: - TextureCoordinateMapper

/// Maps world coordinates (meters) to texture pixel coordinates.
enum TextureCoordinateMapper {

    /// Result of a coordinate mapping.
    struct TextureCoord: Sendable, Equatable {
        let texX: Int
        let texY: Int
    }

    /// Maps a world-space position to texture coordinates.
    ///
    /// - Parameters:
    ///   - worldX: X position in world meters.
    ///   - worldZ: Z position in world meters.
    ///   - mapMinX: Minimum X of the tracked map area.
    ///   - mapMinZ: Minimum Z of the tracked map area.
    ///   - mapWidth: Width of the tracked map area in meters.
    ///   - mapHeight: Height of the tracked map area in meters.
    ///   - textureSize: Texture dimension (square).
    /// - Returns: Clamped texture coordinates.
    static func worldToTexture(
        worldX: Float,
        worldZ: Float,
        mapMinX: Float,
        mapMinZ: Float,
        mapWidth: Float,
        mapHeight: Float,
        textureSize: Int
    ) -> TextureCoord {
        let maxDimension = max(mapWidth, mapHeight)
        guard maxDimension > 0 else {
            return TextureCoord(texX: textureSize / 2, texY: textureSize / 2)
        }

        let scale = Float(textureSize) / maxDimension
        let rawX = Int((worldX - mapMinX) * scale)
        let rawY = Int((worldZ - mapMinZ) * scale)

        let clampedX = max(0, min(textureSize - 1, rawX))
        let clampedY = max(0, min(textureSize - 1, rawY))

        return TextureCoord(texX: clampedX, texY: clampedY)
    }
}

// MARK: - DynamicMapBounds

/// Tracks the growing bounds of the scanned area.
struct DynamicMapBounds: Sendable {
    var minX: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var minZ: Float = .greatestFiniteMagnitude
    var maxZ: Float = -.greatestFiniteMagnitude
    var hasData: Bool = false

    /// Expand bounds to include a new world-space point.
    mutating func expand(x: Float, z: Float) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minZ = min(minZ, z)
        maxZ = max(maxZ, z)
        hasData = true
    }

    /// Map width in meters.
    var width: Float {
        guard hasData else { return 0 }
        return maxX - minX
    }

    /// Map height in meters.
    var height: Float {
        guard hasData else { return 0 }
        return maxZ - minZ
    }

    /// Calculates pixels per meter for fitting the map into the texture.
    func pixelsPerMeter(textureSize: Int) -> Float {
        let maxDim = max(width, height)
        guard maxDim > 0 else { return 1.0 }
        return Float(textureSize) / maxDim
    }
}

// MARK: - WalkingPath

/// Tracks the user's walking path as a series of world-space points.
struct WalkingPath: Sendable {
    /// Minimum distance between consecutive path points (meters).
    let minimumDistance: Float

    /// All path points as (x, z) pairs.
    private(set) var points: [(x: Float, z: Float)] = []

    init(minimumDistance: Float = 0.1) {
        self.minimumDistance = minimumDistance
    }

    /// Adds a point to the path if it's far enough from the last point.
    mutating func addPoint(x: Float, z: Float) {
        if let last = points.last {
            let dx = x - last.x
            let dz = z - last.z
            let dist = sqrt(dx * dx + dz * dz)
            guard dist >= minimumDistance else { return }
        }
        points.append((x: x, z: z))
    }
}

// MARK: - HeatmapTextureRenderer

/// Manages persistent Metal textures for real-time map and heatmap rendering.
///
/// Architecture:
/// - Two persistent 2048x2048 RGBA textures: map (walls/floors) and heatmap (signal colors)
/// - Incremental updates only: new mesh triangles rasterized to map texture,
///   new measurements painted as Gaussian splats on heatmap texture
/// - 10Hz render loop composites both textures into a display-ready UIImage
///
/// Falls back to CPU-based rendering when Metal is unavailable (simulator).
@MainActor
final class HeatmapTextureRenderer {

    // MARK: - Constants

    static let textureSize = 2048
    static let renderHz: Double = 10.0
    static let darkGrey: UInt32 = 0xFF333333 // Unmapped area color (RGBA)
    static let wallColor: UInt32 = 0xFFE0E0E0 // Light grey walls
    static let floorColor: UInt32 = 0xFF555555 // Darker grey floor

    // MARK: - State

    /// The current map bounds as scanned area grows.
    private(set) var mapBounds = DynamicMapBounds()

    /// Walking path accumulator.
    private(set) var walkingPath = WalkingPath()

    /// Number of mesh segments rasterized to the map texture.
    private(set) var meshSegmentsRendered = 0

    /// Number of measurement splats painted on the heatmap texture.
    private(set) var measurementSplatsRendered = 0

    /// Current user position in world coordinates.
    private(set) var userPosition: (x: Float, z: Float)?

    // MARK: - Texture Buffers (CPU fallback)

    /// Map texture pixel buffer (2048 x 2048, RGBA8).
    private var mapPixels: [UInt32]

    /// Heatmap texture pixel buffer (2048 x 2048, RGBA8).
    private var heatmapPixels: [UInt32]

    /// Combined composite buffer for display.
    private var compositePixels: [UInt32]

    #if os(iOS)
    /// Metal device (nil in simulator).
    private var metalDevice: MTLDevice?

    /// Map texture on GPU.
    private var mapTexture: MTLTexture?

    /// Heatmap texture on GPU.
    private var heatmapTexture: MTLTexture?

    /// Command queue for GPU operations.
    private var commandQueue: MTLCommandQueue?
    #endif

    // MARK: - Render Timer

    private var renderTimer: Timer?

    /// Callback invoked each render tick with the composited UIImage.
    var onFrameReady: ((UIImage) -> Void)?

    // MARK: - Init

    init() {
        let pixelCount = Self.textureSize * Self.textureSize
        mapPixels = [UInt32](repeating: Self.darkGrey, count: pixelCount)
        heatmapPixels = [UInt32](repeating: 0x00000000, count: pixelCount) // Transparent
        compositePixels = [UInt32](repeating: Self.darkGrey, count: pixelCount)

        #if os(iOS)
        setupMetal()
        #endif
    }

    // MARK: - Metal Setup

    #if os(iOS)
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Logger.heatmap.info("Metal not available, using CPU rendering")
            return
        }
        metalDevice = device
        commandQueue = device.makeCommandQueue()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Self.textureSize,
            height: Self.textureSize,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        mapTexture = device.makeTexture(descriptor: descriptor)
        heatmapTexture = device.makeTexture(descriptor: descriptor)

        // Initialize map texture with dark grey
        let region = MTLRegionMake2D(0, 0, Self.textureSize, Self.textureSize)
        mapTexture?.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: mapPixels,
            bytesPerRow: Self.textureSize * 4
        )

        Logger.heatmap.info("Metal textures initialized (\(Self.textureSize)x\(Self.textureSize))")
    }
    #endif

    // MARK: - Render Loop

    /// Starts the 10Hz render loop.
    func startRenderLoop() {
        stopRenderLoop()
        renderTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / Self.renderHz,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderFrame()
            }
        }
    }

    /// Stops the render loop.
    func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    // MARK: - Incremental Map Updates

    /// Rasterizes a wall segment onto the map texture.
    ///
    /// - Parameters:
    ///   - x1: Start X in world meters.
    ///   - z1: Start Z in world meters.
    ///   - x2: End X in world meters.
    ///   - z2: End Z in world meters.
    ///   - thickness: Wall thickness in pixels.
    func rasterizeWallSegment(x1: Float, z1: Float, x2: Float, z2: Float, thickness: Int = 3) {
        // Expand bounds
        mapBounds.expand(x: x1, z: z1)
        mapBounds.expand(x: x2, z: z2)

        let start = worldToTexture(worldX: x1, worldZ: z1)
        let end = worldToTexture(worldX: x2, worldZ: z2)

        // Bresenham's line with thickness
        drawThickLine(
            buffer: &mapPixels,
            x0: start.texX,
            y0: start.texY,
            x1: end.texX,
            y1: end.texY,
            color: Self.wallColor,
            thickness: thickness
        )

        meshSegmentsRendered += 1
    }

    /// Rasterizes a floor area (filled rectangle) onto the map texture.
    ///
    /// - Parameters:
    ///   - centerX: Center X in world meters.
    ///   - centerZ: Center Z in world meters.
    ///   - halfExtentX: Half-width in meters.
    ///   - halfExtentZ: Half-depth in meters.
    func rasterizeFloorArea(centerX: Float, centerZ: Float, halfExtentX: Float, halfExtentZ: Float) {
        mapBounds.expand(x: centerX - halfExtentX, z: centerZ - halfExtentZ)
        mapBounds.expand(x: centerX + halfExtentX, z: centerZ + halfExtentZ)

        let topLeft = worldToTexture(worldX: centerX - halfExtentX, worldZ: centerZ - halfExtentZ)
        let bottomRight = worldToTexture(worldX: centerX + halfExtentX, worldZ: centerZ + halfExtentZ)

        for y in topLeft.texY...bottomRight.texY {
            for x in topLeft.texX...bottomRight.texX {
                let idx = y * Self.textureSize + x
                if idx >= 0 && idx < mapPixels.count {
                    // Only fill if still dark grey (don't overwrite walls)
                    if mapPixels[idx] == Self.darkGrey {
                        mapPixels[idx] = Self.floorColor
                    }
                }
            }
        }
    }

    // MARK: - Incremental Heatmap Updates

    /// Paints a Gaussian splat onto the heatmap texture at the given world position.
    ///
    /// - Parameters:
    ///   - worldX: Measurement X in world meters.
    ///   - worldZ: Measurement Z in world meters.
    ///   - rssi: RSSI value in dBm.
    func paintMeasurementSplat(worldX: Float, worldZ: Float, rssi: Int) {
        let center = worldToTexture(worldX: worldX, worldZ: worldZ)
        let ppm = mapBounds.pixelsPerMeter(textureSize: Self.textureSize)
        let pixRadius = GaussianSplat.pixelRadius(
            metersRadius: GaussianSplat.defaultRadius,
            pixelsPerMeter: ppm
        )

        let color = WiFimanColorMapper.color(forRSSI: rssi)

        // Paint Gaussian splat
        for dy in -pixRadius...pixRadius {
            for dx in -pixRadius...pixRadius {
                let px = center.texX + dx
                let py = center.texY + dy

                guard px >= 0 && px < Self.textureSize
                    && py >= 0 && py < Self.textureSize
                else { continue }

                let distPixels = sqrt(Float(dx * dx + dy * dy))
                let distMeters = distPixels / max(1.0, ppm)
                let weight = GaussianSplat.weight(
                    distance: distMeters,
                    radius: GaussianSplat.defaultRadius
                )

                guard weight > 0.01 else { continue }

                let idx = py * Self.textureSize + px
                let packed = WiFimanColorMapper.packRGBA(color, alpha: weight * 0.85)

                // Alpha blend: new over existing
                heatmapPixels[idx] = alphaBlend(src: packed, dst: heatmapPixels[idx])
            }
        }

        measurementSplatsRendered += 1
    }

    // MARK: - User Position

    /// Updates the current user position for the position dot.
    func updateUserPosition(x: Float, z: Float) {
        userPosition = (x: x, z: z)
        walkingPath.addPoint(x: x, z: z)
    }

    // MARK: - Frame Rendering

    /// Composites the map and heatmap textures and produces a UIImage.
    private func renderFrame() {
        // Composite: map + heatmap overlay
        for i in 0..<(Self.textureSize * Self.textureSize) {
            let mapPx = mapPixels[i]
            let heatPx = heatmapPixels[i]

            // If heatmap has non-zero alpha, blend over map
            let heatAlpha = (heatPx >> 24) & 0xFF
            if heatAlpha > 0 {
                compositePixels[i] = alphaBlend(src: heatPx, dst: mapPx)
            } else {
                compositePixels[i] = mapPx
            }
        }

        // Draw walking path
        drawWalkingPath()

        // Draw user position dot
        if let pos = userPosition {
            drawPositionDot(worldX: pos.x, worldZ: pos.z)
        }

        // Convert to UIImage
        if let image = createUIImage(from: compositePixels) {
            onFrameReady?(image)
        }
    }

    /// Generates a single frame image on demand (for snapshot).
    func renderSnapshot() -> UIImage? {
        renderFrame()
        return createUIImage(from: compositePixels)
    }

    // MARK: - Walking Path Drawing

    private func drawWalkingPath() {
        let points = walkingPath.points
        guard points.count >= 2 else { return }

        let pathColor: UInt32 = 0xCC00D4FF // Cyan with some transparency

        for i in 0..<(points.count - 1) {
            let start = worldToTexture(worldX: points[i].x, worldZ: points[i].z)
            let end = worldToTexture(worldX: points[i + 1].x, worldZ: points[i + 1].z)
            drawThickLine(
                buffer: &compositePixels,
                x0: start.texX,
                y0: start.texY,
                x1: end.texX,
                y1: end.texY,
                color: pathColor,
                thickness: 2
            )
        }
    }

    // MARK: - Position Dot

    private func drawPositionDot(worldX: Float, worldZ: Float) {
        let center = worldToTexture(worldX: worldX, worldZ: worldZ)
        let dotRadius = 8
        let dotColor: UInt32 = 0xFF4488FF // Blue position dot

        for dy in -dotRadius...dotRadius {
            for dx in -dotRadius...dotRadius {
                let dist = sqrt(Float(dx * dx + dy * dy))
                guard dist <= Float(dotRadius) else { continue }

                let px = center.texX + dx
                let py = center.texY + dy

                guard px >= 0 && px < Self.textureSize
                    && py >= 0 && py < Self.textureSize
                else { continue }

                let idx = py * Self.textureSize + px
                compositePixels[idx] = dotColor
            }
        }
    }

    // MARK: - Coordinate Helpers

    private func worldToTexture(worldX: Float, worldZ: Float) -> TextureCoordinateMapper.TextureCoord {
        TextureCoordinateMapper.worldToTexture(
            worldX: worldX,
            worldZ: worldZ,
            mapMinX: mapBounds.minX,
            mapMinZ: mapBounds.minZ,
            mapWidth: mapBounds.width,
            mapHeight: mapBounds.height,
            textureSize: Self.textureSize
        )
    }

    // MARK: - Drawing Primitives

    /// Draws a thick line using Bresenham's algorithm with perpendicular expansion.
    private func drawThickLine(
        buffer: inout [UInt32],
        x0: Int,
        y0: Int,
        x1: Int,
        y1: Int,
        color: UInt32,
        thickness: Int
    ) {
        let halfThick = thickness / 2

        // Bresenham's line algorithm
        var cx = x0
        var cy = y0
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy

        while true {
            // Draw thickness around the line point
            for ty in (cy - halfThick)...(cy + halfThick) {
                for tx in (cx - halfThick)...(cx + halfThick) {
                    if tx >= 0 && tx < Self.textureSize && ty >= 0 && ty < Self.textureSize {
                        let idx = ty * Self.textureSize + tx
                        buffer[idx] = color
                    }
                }
            }

            if cx == x1 && cy == y1 { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                cx += sx
            }
            if e2 <= dx {
                err += dx
                cy += sy
            }
        }
    }

    // MARK: - Alpha Blending

    /// Blends source pixel over destination (premultiplied alpha).
    private func alphaBlend(src: UInt32, dst: UInt32) -> UInt32 {
        let srcR = Float(src & 0xFF) / 255.0
        let srcG = Float((src >> 8) & 0xFF) / 255.0
        let srcB = Float((src >> 16) & 0xFF) / 255.0
        let srcA = Float((src >> 24) & 0xFF) / 255.0

        let dstR = Float(dst & 0xFF) / 255.0
        let dstG = Float((dst >> 8) & 0xFF) / 255.0
        let dstB = Float((dst >> 16) & 0xFF) / 255.0
        let dstA = Float((dst >> 24) & 0xFF) / 255.0

        let outA = srcA + dstA * (1.0 - srcA)
        guard outA > 0 else { return 0 }

        let outR = (srcR * srcA + dstR * dstA * (1.0 - srcA)) / outA
        let outG = (srcG * srcA + dstG * dstA * (1.0 - srcA)) / outA
        let outB = (srcB * srcA + dstB * dstA * (1.0 - srcA)) / outA

        let r = UInt32(max(0, min(255, outR * 255)))
        let g = UInt32(max(0, min(255, outG * 255)))
        let b = UInt32(max(0, min(255, outB * 255)))
        let a = UInt32(max(0, min(255, outA * 255)))

        return r | (g << 8) | (b << 16) | (a << 24)
    }

    // MARK: - Image Conversion

    /// Creates a UIImage from the pixel buffer.
    private func createUIImage(from pixels: [UInt32]) -> UIImage? {
        let width = Self.textureSize
        let height = Self.textureSize
        let bytesPerRow = width * 4

        return pixels.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    // MARK: - Cleanup

    /// Releases all resources.
    func cleanup() {
        stopRenderLoop()
        #if os(iOS)
        mapTexture = nil
        heatmapTexture = nil
        commandQueue = nil
        metalDevice = nil
        #endif
    }
}
