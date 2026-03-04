import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - HeatmapMetalRendererTests

@Suite("HeatmapMetalRenderer — Pure Logic")
struct HeatmapMetalRendererTests {

    // MARK: - Gaussian Splat

    @Test func gaussianSplatCenterHasMaxWeight() {
        // At center distance=0, weight should be 1.0
        let weight = GaussianSplat.weight(distance: 0, radius: 1.5)
        #expect(weight == 1.0, "Center of splat should have weight 1.0")
    }

    @Test func gaussianSplatEdgeHasReducedWeight() {
        // At distance=radius, weight should be ~0.1 (exp(-2.0) ≈ 0.135)
        let weight = GaussianSplat.weight(distance: 1.5, radius: 1.5)
        #expect(weight > 0.05, "Edge should still have some weight")
        #expect(weight < 0.5, "Edge weight should be significantly reduced")
    }

    @Test func gaussianSplatBeyondRadiusIsZero() {
        // Beyond 2x radius, weight should be effectively zero
        let weight = GaussianSplat.weight(distance: 5.0, radius: 1.5)
        #expect(weight < 0.001, "Far beyond radius should have near-zero weight")
    }

    @Test func gaussianSplatPixelRadiusCalculation() {
        // At 10 px/m, 1.5m radius → 15 pixels
        let pixelRadius = GaussianSplat.pixelRadius(metersRadius: 1.5, pixelsPerMeter: 10.0)
        #expect(pixelRadius == 15, "1.5m at 10px/m should be 15 pixels")
    }

    // MARK: - WiFiman Color Mapping

    @Test func wifimanExcellentSignalIsBlue() {
        // -35 dBm (excellent) should have strong blue component
        let color = WiFimanColorMapper.color(forRSSI: -35)
        #expect(color.blue > 0.3, "Excellent signal (-35) should have blue component")
    }

    @Test func wifimanGoodSignalIsGreen() {
        // -55 dBm (good) should have strong green component
        let color = WiFimanColorMapper.color(forRSSI: -55)
        #expect(color.green > 0.3, "Good signal (-55) should have green component")
    }

    @Test func wifimanFairSignalIsYellow() {
        // -65 dBm (fair) should have both red and green
        let color = WiFimanColorMapper.color(forRSSI: -65)
        #expect(color.red > 0.3, "Fair signal should have red component")
        #expect(color.green > 0.3, "Fair signal should have green component")
    }

    @Test func wifimanWeakSignalIsOrange() {
        // -75 dBm (weak) should be warm-toned
        let color = WiFimanColorMapper.color(forRSSI: -75)
        #expect(color.red > color.blue, "Weak signal should be warm-toned")
    }

    @Test func wifimanDeadZoneIsRed() {
        // -90 dBm (dead zone) should be red-dominant
        let color = WiFimanColorMapper.color(forRSSI: -90)
        #expect(color.red > color.green, "Dead zone should be red-dominant")
        #expect(color.red > color.blue, "Dead zone should have more red than blue")
    }

    @Test func wifimanColorsClamped() {
        // Extreme values should not crash or produce out-of-range colors
        let veryStrong = WiFimanColorMapper.color(forRSSI: 0)
        #expect(veryStrong.red >= 0 && veryStrong.red <= 1)
        #expect(veryStrong.green >= 0 && veryStrong.green <= 1)
        #expect(veryStrong.blue >= 0 && veryStrong.blue <= 1)

        let veryWeak = WiFimanColorMapper.color(forRSSI: -120)
        #expect(veryWeak.red >= 0 && veryWeak.red <= 1)
        #expect(veryWeak.green >= 0 && veryWeak.green <= 1)
        #expect(veryWeak.blue >= 0 && veryWeak.blue <= 1)
    }

    // MARK: - Texture Coordinate Mapping

    @Test func worldToTextureCoordinatesCenterMap() {
        // Center of a 10m x 10m map should map to center of texture
        let coord = TextureCoordinateMapper.worldToTexture(
            worldX: 5.0,
            worldZ: 5.0,
            mapMinX: 0.0,
            mapMinZ: 0.0,
            mapWidth: 10.0,
            mapHeight: 10.0,
            textureSize: 2048
        )
        #expect(coord.texX == 1024, "Center X should map to texture center")
        #expect(coord.texY == 1024, "Center Z should map to texture center")
    }

    @Test func worldToTextureCoordinatesOrigin() {
        let coord = TextureCoordinateMapper.worldToTexture(
            worldX: 0.0,
            worldZ: 0.0,
            mapMinX: 0.0,
            mapMinZ: 0.0,
            mapWidth: 10.0,
            mapHeight: 10.0,
            textureSize: 2048
        )
        #expect(coord.texX == 0, "Origin X should map to 0")
        #expect(coord.texY == 0, "Origin Z should map to 0")
    }

    @Test func worldToTextureCoordinatesClampOutOfBounds() {
        let coord = TextureCoordinateMapper.worldToTexture(
            worldX: -5.0,
            worldZ: 15.0,
            mapMinX: 0.0,
            mapMinZ: 0.0,
            mapWidth: 10.0,
            mapHeight: 10.0,
            textureSize: 2048
        )
        #expect(coord.texX == 0, "Negative X should clamp to 0")
        #expect(coord.texY == 2047, "Beyond-max Z should clamp to max")
    }

    // MARK: - Map Bounds Tracking

    @Test func mapBoundsExpandWithNewPoints() {
        var bounds = DynamicMapBounds()
        bounds.expand(x: 1.0, z: 2.0)
        bounds.expand(x: -1.0, z: -2.0)
        bounds.expand(x: 3.0, z: 0.0)

        #expect(bounds.minX == -1.0)
        #expect(bounds.maxX == 3.0)
        #expect(bounds.minZ == -2.0)
        #expect(bounds.maxZ == 2.0)
    }

    @Test func mapBoundsWidth() {
        var bounds = DynamicMapBounds()
        bounds.expand(x: -5.0, z: 0.0)
        bounds.expand(x: 5.0, z: 0.0)

        #expect(bounds.width == 10.0)
    }

    @Test func mapBoundsPixelsPerMeter() {
        var bounds = DynamicMapBounds()
        bounds.expand(x: 0.0, z: 0.0)
        bounds.expand(x: 20.0, z: 10.0)

        // Texture 2048, map width 20m → ~102.4 px/m (limited by largest dimension)
        let ppm = bounds.pixelsPerMeter(textureSize: 2048)
        #expect(ppm > 90 && ppm < 110, "Pixels per meter should be reasonable for 20m in 2048px")
    }

    // MARK: - Walking Path

    @Test func walkingPathAccumulatesPoints() {
        var path = WalkingPath()
        path.addPoint(x: 0.0, z: 0.0)
        path.addPoint(x: 1.0, z: 1.0)
        path.addPoint(x: 2.0, z: 0.5)

        #expect(path.points.count == 3)
    }

    @Test func walkingPathMinimumDistanceFilter() {
        var path = WalkingPath(minimumDistance: 0.1)
        path.addPoint(x: 0.0, z: 0.0)
        path.addPoint(x: 0.01, z: 0.01) // Too close, should be filtered
        path.addPoint(x: 1.0, z: 1.0) // Far enough

        #expect(path.points.count == 2, "Points too close together should be filtered")
    }
}
