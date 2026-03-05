import CoreGraphics
import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - IDW Interpolation Tests

@Suite("HeatmapRenderer — IDW Interpolation")
struct HeatmapRendererIDWTests {

    private func makeRenderer(
        gridWidth: Int = 10,
        gridHeight: Int = 10,
        power: Double = 2.0,
        opacity: Double = 0.7
    ) -> HeatmapRenderer {
        HeatmapRenderer(configuration: .init(
            powerParameter: power,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            opacity: opacity
        ))
    }

    private func makePoint(
        x: Double,
        y: Double,
        rssi: Int = -50
    ) -> MeasurementPoint {
        MeasurementPoint(
            floorPlanX: x,
            floorPlanY: y,
            rssi: rssi
        )
    }

    // MARK: - Empty Input

    @Test("empty points returns zero grid")
    func emptyPointsReturnsZeroGrid() {
        let renderer = makeRenderer()
        let grid = renderer.interpolateGrid(
            points: [],
            visualization: .signalStrength
        )
        #expect(grid.count == 10)
        #expect(grid[0].count == 10)
        for row in grid {
            for value in row {
                #expect(value == 0)
            }
        }
    }

    // MARK: - Single Point

    @Test("single point fills entire grid with that value")
    func singlePointFillsGrid() {
        let renderer = makeRenderer(gridWidth: 5, gridHeight: 5)
        let points = [makePoint(x: 0.5, y: 0.5, rssi: -60)]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )

        for row in grid {
            for value in row {
                #expect(abs(value - -60) < 0.01, "All cells should equal the single point value")
            }
        }
    }

    // MARK: - Exact Point Location

    @Test("grid value at exact point location equals point value")
    func exactPointLocationReturnsExactValue() {
        let renderer = makeRenderer(gridWidth: 11, gridHeight: 11)
        let points = [
            makePoint(x: 0.0, y: 0.0, rssi: -30),
            makePoint(x: 1.0, y: 1.0, rssi: -90),
        ]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )
        #expect(abs(grid[0][0] - -30) < 0.01, "Value at (0,0) should be -30")
        #expect(abs(grid[10][10] - -90) < 0.01, "Value at (1,1) should be -90")
    }

    // MARK: - Midpoint Interpolation

    @Test("midpoint between two equal-distance points averages their values")
    func midpointAveragesTwoPoints() {
        let renderer = makeRenderer(gridWidth: 11, gridHeight: 1)
        let points = [
            makePoint(x: 0.0, y: 0.0, rssi: -40),
            makePoint(x: 1.0, y: 0.0, rssi: -80),
        ]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )
        let midValue = grid[0][5]
        #expect(abs(midValue - -60) < 1.0, "Midpoint should be close to average (-60), got \(midValue)")
    }

    // MARK: - Closer Point Has More Influence

    @Test("value near a point is closer to that point's value")
    func closerPointDominates() {
        let renderer = makeRenderer(gridWidth: 101, gridHeight: 1)
        let points = [
            makePoint(x: 0.0, y: 0.0, rssi: -30),
            makePoint(x: 1.0, y: 0.0, rssi: -90),
        ]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )
        let nearFirst = grid[0][10]
        let nearSecond = grid[0][90]
        #expect(nearFirst > nearSecond, "Value near -30 point should be higher (less negative) than near -90 point")
        #expect(nearFirst > -60, "Value near strong point should be stronger than average")
        #expect(nearSecond < -60, "Value near weak point should be weaker than average")
    }

    // MARK: - Power Parameter

    @Test("higher power parameter produces sharper falloff")
    func higherPowerProducesSharperFalloff() {
        let lowPower = makeRenderer(gridWidth: 101, gridHeight: 1, power: 1.0)
        let highPower = makeRenderer(gridWidth: 101, gridHeight: 1, power: 4.0)

        let points = [
            makePoint(x: 0.0, y: 0.0, rssi: -30),
            makePoint(x: 1.0, y: 0.0, rssi: -90),
        ]

        let gridLow = lowPower.interpolateGrid(points: points, visualization: .signalStrength)
        let gridHigh = highPower.interpolateGrid(points: points, visualization: .signalStrength)

        let nearFirstLow = gridLow[0][10]
        let nearFirstHigh = gridHigh[0][10]
        #expect(nearFirstHigh > nearFirstLow,
                "Higher power should keep values closer to nearby point (sharper): \(nearFirstHigh) vs \(nearFirstLow)")
    }

    // MARK: - Grid Dimensions

    @Test("custom grid dimensions are respected")
    func customGridDimensions() {
        let renderer = makeRenderer(gridWidth: 50, gridHeight: 25)
        let points = [makePoint(x: 0.5, y: 0.5, rssi: -50)]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )
        #expect(grid.count == 25)
        #expect(grid[0].count == 50)
    }

    @Test("override grid dimensions via parameters")
    func overrideGridDimensions() {
        let renderer = makeRenderer(gridWidth: 10, gridHeight: 10)
        let points = [makePoint(x: 0.5, y: 0.5, rssi: -50)]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength,
            width: 30,
            height: 20
        )
        #expect(grid.count == 20)
        #expect(grid[0].count == 30)
    }

    // MARK: - Points Without Data for Visualization

    @Test("points without values for chosen visualization produce zero grid")
    func pointsWithoutValuesProduceZeroGrid() {
        let renderer = makeRenderer(gridWidth: 5, gridHeight: 5)
        let points = [makePoint(x: 0.5, y: 0.5, rssi: -50)]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .downloadSpeed
        )
        for row in grid {
            for value in row {
                #expect(value == 0, "No download data, grid should be zero")
            }
        }
    }

    // MARK: - Multiple Points

    @Test("three-point interpolation produces smooth gradient")
    func threePointInterpolation() {
        let renderer = makeRenderer(gridWidth: 11, gridHeight: 11)
        let points = [
            makePoint(x: 0.0, y: 0.0, rssi: -30),
            makePoint(x: 1.0, y: 0.0, rssi: -60),
            makePoint(x: 0.5, y: 1.0, rssi: -90),
        ]
        let grid = renderer.interpolateGrid(
            points: points,
            visualization: .signalStrength
        )

        #expect(abs(grid[0][0] - -30) < 0.01)
        #expect(abs(grid[0][10] - -60) < 0.01)
        #expect(abs(grid[10][5] - -90) < 0.01)

        let center = grid[5][5]
        #expect(center > -90 && center < -30, "Center should be between extremes, got \(center)")
    }
}

// MARK: - Color Mapping Tests

@Suite("HeatmapRenderer — Color Mapping")
struct HeatmapRendererColorTests {

    private func makeRenderer(opacity: Double = 1.0) -> HeatmapRenderer {
        HeatmapRenderer(configuration: .init(opacity: opacity))
    }

    @Test("strong signal maps to green range")
    func strongSignalIsGreen() {
        let renderer = makeRenderer()
        let color = renderer.colorForValue(-30, visualization: .signalStrength)
        #expect(color.g > color.r, "Strong signal should have more green than red")
    }

    @Test("weak signal maps to red range")
    func weakSignalIsRed() {
        let renderer = makeRenderer()
        let color = renderer.colorForValue(-95, visualization: .signalStrength)
        #expect(color.r > color.g, "Weak signal should have more red than green")
    }

    @Test("opacity affects alpha channel")
    func opacityAffectsAlpha() {
        let fullOpacity = HeatmapRenderer(configuration: .init(opacity: 1.0))
        let halfOpacity = HeatmapRenderer(configuration: .init(opacity: 0.5))

        let colorFull = fullOpacity.colorForValue(-50, visualization: .signalStrength)
        let colorHalf = halfOpacity.colorForValue(-50, visualization: .signalStrength)

        #expect(colorFull.a == 255)
        #expect(colorHalf.a == 127 || colorHalf.a == 128, "Half opacity should be ~127-128")
    }

    @Test("clamping to valid range for out-of-range values")
    func clampingOutOfRange() {
        let renderer = makeRenderer()
        let veryStrong = renderer.colorForValue(10, visualization: .signalStrength)
        let atMax = renderer.colorForValue(0, visualization: .signalStrength)
        #expect(veryStrong.r == atMax.r && veryStrong.g == atMax.g && veryStrong.b == atMax.b,
                "Values above range should clamp to max")

        let veryWeak = renderer.colorForValue(-150, visualization: .signalStrength)
        let atMin = renderer.colorForValue(-100, visualization: .signalStrength)
        #expect(veryWeak.r == atMin.r && veryWeak.g == atMin.g && veryWeak.b == atMin.b,
                "Values below range should clamp to min")
    }

    @Test("latency color inverts direction (lower is better)")
    func latencyColorInversion() {
        let renderer = makeRenderer()
        let lowLatency = renderer.colorForValue(5, visualization: .latency)
        let highLatency = renderer.colorForValue(150, visualization: .latency)
        #expect(lowLatency.g > lowLatency.r, "Low latency (good) should be more green")
        #expect(highLatency.r > highLatency.g, "High latency (bad) should be more red")
    }
}

// MARK: - CGImage Rendering Tests

@Suite("HeatmapRenderer — Image Rendering")
struct HeatmapRendererImageTests {

    @Test("render returns CGImage with correct dimensions")
    func renderReturnsCGImage() {
        let renderer = HeatmapRenderer(configuration: .init(
            gridWidth: 50,
            gridHeight: 30,
            opacity: 0.7
        ))
        let points = [
            MeasurementPoint(floorPlanX: 0.2, floorPlanY: 0.3, rssi: -45),
            MeasurementPoint(floorPlanX: 0.8, floorPlanY: 0.7, rssi: -75),
        ]
        let image = renderer.render(points: points, visualization: .signalStrength)
        #expect(image != nil)
        #expect(image?.width == 50)
        #expect(image?.height == 30)
    }

    @Test("render with empty points returns image")
    func renderWithEmptyPointsReturnsImage() {
        let renderer = HeatmapRenderer(configuration: .init(gridWidth: 10, gridHeight: 10))
        let image = renderer.render(points: [], visualization: .signalStrength)
        #expect(image != nil)
    }

    @Test("render with zero dimensions returns nil")
    func renderWithZeroDimensionsReturnsNil() {
        let renderer = HeatmapRenderer(configuration: .init(gridWidth: 0, gridHeight: 0))
        let image = renderer.render(points: [], visualization: .signalStrength)
        #expect(image == nil)
    }

    @Test("render produces 4 bytes per pixel (RGBA)")
    func renderProducesRGBA() {
        let renderer = HeatmapRenderer(configuration: .init(gridWidth: 10, gridHeight: 10))
        let points = [MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55)]
        let image = renderer.render(points: points, visualization: .signalStrength)
        #expect(image != nil)
        #expect(image?.bitsPerPixel == 32)
    }
}

// MARK: - Configuration Tests

@Suite("HeatmapRenderer — Configuration")
struct HeatmapRendererConfigTests {

    @Test("default configuration has expected values")
    func defaultConfiguration() {
        let config = HeatmapRenderer.Configuration()
        #expect(config.powerParameter == 2.0)
        #expect(config.gridWidth == 200)
        #expect(config.gridHeight == 200)
        #expect(config.opacity == 0.7)
    }

    @Test("configuration is Equatable")
    func configurationEquatable() {
        let config1 = HeatmapRenderer.Configuration(powerParameter: 2.0, gridWidth: 100, gridHeight: 100)
        let config2 = HeatmapRenderer.Configuration(powerParameter: 2.0, gridWidth: 100, gridHeight: 100)
        let config3 = HeatmapRenderer.Configuration(powerParameter: 3.0, gridWidth: 100, gridHeight: 100)
        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}

// MARK: - HeatmapVisualization extractValue Tests

@Suite("HeatmapVisualization — Value Extraction")
struct HeatmapVisualizationExtractionTests {

    @Test("signalStrength extracts RSSI")
    func signalStrengthExtractsRSSI() {
        let point = MeasurementPoint(rssi: -55)
        #expect(HeatmapVisualization.signalStrength.extractValue(from: point) == -55)
    }

    @Test("signalToNoise extracts SNR")
    func signalToNoiseExtractsSNR() {
        let point = MeasurementPoint(rssi: -45, snr: 42)
        #expect(HeatmapVisualization.signalToNoise.extractValue(from: point) == 42)
    }

    @Test("signalToNoise returns nil when SNR is nil")
    func signalToNoiseNilWhenNoSNR() {
        let point = MeasurementPoint(rssi: -45)
        #expect(HeatmapVisualization.signalToNoise.extractValue(from: point) == nil)
    }

    @Test("downloadSpeed extracts download speed")
    func downloadSpeedExtraction() {
        let point = MeasurementPoint(rssi: -50, downloadSpeed: 125.5)
        #expect(HeatmapVisualization.downloadSpeed.extractValue(from: point) == 125.5)
    }

    @Test("uploadSpeed extracts upload speed")
    func uploadSpeedExtraction() {
        let point = MeasurementPoint(rssi: -50, uploadSpeed: 45.0)
        #expect(HeatmapVisualization.uploadSpeed.extractValue(from: point) == 45.0)
    }

    @Test("latency extracts latency")
    func latencyExtraction() {
        let point = MeasurementPoint(rssi: -50, latency: 12.5)
        #expect(HeatmapVisualization.latency.extractValue(from: point) == 12.5)
    }

    @Test("channelOverlap returns nil (not point-level)")
    func channelOverlapReturnsNil() {
        let point = MeasurementPoint(rssi: -50, channel: 6)
        #expect(HeatmapVisualization.channelOverlap.extractValue(from: point) == nil)
    }
}
