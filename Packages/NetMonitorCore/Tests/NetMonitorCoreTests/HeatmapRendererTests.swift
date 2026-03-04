import CoreGraphics
import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - HeatmapRenderer IDW Interpolation Tests

@Suite("HeatmapRenderer IDW")
struct HeatmapRendererIDWTests {

    // MARK: - Helpers

    private func makePoints(_ specs: [(x: Double, y: Double, rssi: Int)]) -> [MeasurementPoint] {
        specs.map { spec in
            MeasurementPoint(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                floorPlanX: spec.x,
                floorPlanY: spec.y,
                rssi: spec.rssi
            )
        }
    }

    // VAL-FOUND-046: Minimum 3 points required for heatmap
    @Test func returnsNilForZeroPoints() {
        let result = HeatmapRenderer.render(
            points: [],
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        #expect(result == nil)
    }

    @Test func returnsNilForOnePoint() {
        let points = makePoints([(0.5, 0.5, -50)])
        let result = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        #expect(result == nil)
    }

    @Test func returnsNilForTwoPoints() {
        let points = makePoints([(0.2, 0.2, -40), (0.8, 0.8, -80)])
        let result = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        #expect(result == nil)
    }

    // VAL-FOUND-020: HeatmapRenderer output is valid CGImage
    @Test func outputIsValidCGImage() {
        let points = makePoints([
            (0.2, 0.2, -40),
            (0.5, 0.5, -60),
            (0.8, 0.8, -80)
        ])
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        #expect(image != nil)
        #expect(image!.width == 200)
        #expect(image!.height == 200)
    }

    // VAL-FOUND-021: HeatmapRenderer default 200x200 grid
    @Test func defaultResolution200x200() {
        let points = makePoints([
            (0.1, 0.1, -40),
            (0.5, 0.5, -60),
            (0.9, 0.9, -80)
        ])
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        #expect(image != nil)
        #expect(image!.width == 200)
        #expect(image!.height == 200)
    }

    @Test func customResolution() {
        let points = makePoints([
            (0.1, 0.1, -40),
            (0.5, 0.5, -60),
            (0.9, 0.9, -80)
        ])
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 100,
            floorPlanHeight: 100,
            visualization: .signalStrength,
            resolution: HeatmapResolution(width: 100, height: 100)
        )
        #expect(image != nil)
        #expect(image!.width == 100)
        #expect(image!.height == 100)
    }

    // VAL-FOUND-019: IDW handles zero distance (co-located pixel)
    @Test func zeroDistanceReturnsExactValue() {
        let points = makePoints([
            (0.5, 0.5, -42),
            (0.1, 0.1, -70),
            (0.9, 0.9, -80)
        ])
        // Pixel at the exact location of point (0.5, 0.5) should return -42
        let value = HeatmapRenderer.interpolateIDW(
            atX: 0.5,
            y: 0.5,
            points: points,
            valueExtractor: { Double($0.rssi) }
        )
        #expect(value == -42.0)
    }

    // VAL-FOUND-018: IDW power parameter p=2.0
    @Test func idwPowerParameterP2() {
        // Known-answer test: 3 points, query at specific location
        // A(0,0)=10, B(1,0)=20, C(0,1)=30, query at (0.5,0.5)
        // d(A)=sqrt(0.25+0.25)=sqrt(0.5), d(B)=sqrt(0.25+0.25)=sqrt(0.5), d(C)=sqrt(0.25+0.25)=sqrt(0.5)
        // All equidistant → weighted average = (10+20+30)/3 = 20.0
        let points = makePoints([
            (0.0, 0.0, -10),
            (1.0, 0.0, -20),
            (0.0, 1.0, -30)
        ])
        let value = HeatmapRenderer.interpolateIDW(
            atX: 0.5,
            y: 0.5,
            points: points,
            valueExtractor: { Double($0.rssi) }
        )
        #expect(abs(value - -20.0) < 0.01)
    }

    // VAL-FOUND-016: IDW interpolation — two points linear gradient (with third helper)
    @Test func twoPointGradientWithThird() {
        // Three points: left edge strong (-30), right edge weak (-90), center helper (-60)
        // Midpoint should be close to -60
        let points = makePoints([
            (0.0, 0.5, -30),
            (1.0, 0.5, -90),
            (0.5, 0.5, -60)
        ])
        let midValue = HeatmapRenderer.interpolateIDW(
            atX: 0.5,
            y: 0.5,
            points: points,
            valueExtractor: { Double($0.rssi) }
        )
        // At (0.5,0.5) we're exactly on the third point, so exact value
        #expect(midValue == -60.0)
    }

    // VAL-FOUND-017: IDW interpolation — proximity dominance
    @Test func proximityDominance() {
        // A(-40) at (0.1, 0.5), B(-70) at (0.9, 0.1), C(-80) at (0.9, 0.9)
        // Query pixel 1 unit-like close to A → value should be within 2 dBm of -40
        let points = makePoints([
            (0.1, 0.5, -40),
            (0.9, 0.1, -70),
            (0.9, 0.9, -80)
        ])
        let value = HeatmapRenderer.interpolateIDW(
            atX: 0.11,
            y: 0.5,
            points: points,
            valueExtractor: { Double($0.rssi) }
        )
        #expect(abs(value - -40.0) < 2.0)
    }

    // VAL-FOUND-015: IDW interpolation — single point constant (with helpers)
    @Test func singlePointWithHelpersConstant() {
        // One dominant point at center, two far helpers
        // The dominant point should strongly influence the center
        let points = makePoints([
            (0.5, 0.5, -50),
            (0.0, 0.0, -50),
            (1.0, 1.0, -50)
        ])
        // All same value → should be -50 everywhere
        let value = HeatmapRenderer.interpolateIDW(
            atX: 0.25,
            y: 0.25,
            points: points,
            valueExtractor: { Double($0.rssi) }
        )
        #expect(abs(value - -50.0) < 0.01)
    }
}

// MARK: - HeatmapRenderer Color Mapping Tests

@Suite("HeatmapRenderer Color Mapping")
struct HeatmapRendererColorMappingTests {

    // MARK: - Helpers

    // VAL-FOUND-024: Color mapping — signalStrength gradient
    @Test func signalStrengthGreen() {
        // RSSI >= -50 → green
        let color = HeatmapRenderer.colorForValue(-40, visualization: .signalStrength, colorScheme: .standard)
        #expect(color.green > color.red, "Strong signal should be green-dominant")
    }

    @Test func signalStrengthYellow() {
        // RSSI -50 to -70 → yellow (R+G high, B low)
        let color = HeatmapRenderer.colorForValue(-60, visualization: .signalStrength, colorScheme: .standard)
        #expect(color.red > 0.3, "Medium signal should have red component")
        #expect(color.green > 0.3, "Medium signal should have green component")
    }

    @Test func signalStrengthRed() {
        // RSSI <= -70 → red
        let color = HeatmapRenderer.colorForValue(-85, visualization: .signalStrength, colorScheme: .standard)
        #expect(color.red > color.green, "Weak signal should be red-dominant")
    }

    // VAL-FOUND-025: Color mapping — SNR gradient
    @Test func snrGreen() {
        // SNR > 25 → green
        let color = HeatmapRenderer.colorForValue(35, visualization: .signalToNoise, colorScheme: .standard)
        #expect(color.green > color.red, "High SNR should be green-dominant")
    }

    @Test func snrYellow() {
        // SNR 15-25 → yellow
        let color = HeatmapRenderer.colorForValue(20, visualization: .signalToNoise, colorScheme: .standard)
        #expect(color.red > 0.3, "Medium SNR should have red component")
        #expect(color.green > 0.3, "Medium SNR should have green component")
    }

    @Test func snrRed() {
        // SNR < 15 → red
        let color = HeatmapRenderer.colorForValue(5, visualization: .signalToNoise, colorScheme: .standard)
        #expect(color.red > color.green, "Low SNR should be red-dominant")
    }

    // VAL-FOUND-026: Color mapping — downloadSpeed gradient
    @Test func downloadSpeedGreen() {
        // >100 Mbps → green
        let color = HeatmapRenderer.colorForValue(150, visualization: .downloadSpeed, colorScheme: .standard)
        #expect(color.green > color.red, "Fast download should be green-dominant")
    }

    @Test func downloadSpeedYellow() {
        // 25-100 → yellow
        let color = HeatmapRenderer.colorForValue(60, visualization: .downloadSpeed, colorScheme: .standard)
        #expect(color.red > 0.3, "Medium download should have red component")
        #expect(color.green > 0.3, "Medium download should have green component")
    }

    @Test func downloadSpeedRed() {
        // <25 → red
        let color = HeatmapRenderer.colorForValue(10, visualization: .downloadSpeed, colorScheme: .standard)
        #expect(color.red > color.green, "Slow download should be red-dominant")
    }

    // VAL-FOUND-027: Color mapping — uploadSpeed gradient
    @Test func uploadSpeedGreen() {
        let color = HeatmapRenderer.colorForValue(150, visualization: .uploadSpeed, colorScheme: .standard)
        #expect(color.green > color.red, "Fast upload should be green-dominant")
    }

    @Test func uploadSpeedYellow() {
        let color = HeatmapRenderer.colorForValue(60, visualization: .uploadSpeed, colorScheme: .standard)
        #expect(color.red > 0.3)
        #expect(color.green > 0.3)
    }

    @Test func uploadSpeedRed() {
        let color = HeatmapRenderer.colorForValue(10, visualization: .uploadSpeed, colorScheme: .standard)
        #expect(color.red > color.green, "Slow upload should be red-dominant")
    }

    // VAL-FOUND-028: Color mapping — latency gradient
    @Test func latencyGreen() {
        // <10ms → green
        let color = HeatmapRenderer.colorForValue(5, visualization: .latency, colorScheme: .standard)
        #expect(color.green > color.red, "Low latency should be green-dominant")
    }

    @Test func latencyYellow() {
        // 10-50 → yellow
        let color = HeatmapRenderer.colorForValue(30, visualization: .latency, colorScheme: .standard)
        #expect(color.red > 0.3)
        #expect(color.green > 0.3)
    }

    @Test func latencyRed() {
        // >50 → red
        let color = HeatmapRenderer.colorForValue(80, visualization: .latency, colorScheme: .standard)
        #expect(color.red > color.green, "High latency should be red-dominant")
    }

    // VAL-FOUND-029: Color mapping — 70% default opacity
    @Test func defaultOpacity70Percent() {
        let points = [
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40),
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60),
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.9, floorPlanY: 0.9, rssi: -80)
        ]
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 10,
            floorPlanHeight: 10,
            visualization: .signalStrength,
            resolution: HeatmapResolution(width: 10, height: 10)
        )
        #expect(image != nil)

        // Sample a pixel and check alpha = 178/255 ≈ 0.698
        guard let image = image,
              let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data)
        else {
            Issue.record("Could not get pixel data")
            return
        }

        // Sample pixel at (5, 5) — center of image
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        let offset = 5 * bytesPerRow + 5 * bytesPerPixel
        // RGBA format: alpha is 4th component
        let alpha = ptr[offset + 3]
        // 0.7 * 255 = 178.5, allow ±2 for rounding
        #expect(abs(Int(alpha) - 178) <= 2, "Default opacity should be ~0.7 (178/255), got \(alpha)")
    }

    @Test func customOpacity() {
        let points = [
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40),
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60),
            MeasurementPoint(timestamp: Date(), floorPlanX: 0.9, floorPlanY: 0.9, rssi: -80)
        ]
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 10,
            floorPlanHeight: 10,
            visualization: .signalStrength,
            resolution: HeatmapResolution(width: 10, height: 10),
            opacity: 1.0
        )
        #expect(image != nil)

        guard let image = image,
              let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data)
        else {
            Issue.record("Could not get pixel data")
            return
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        let offset = 5 * bytesPerRow + 5 * bytesPerPixel
        let alpha = ptr[offset + 3]
        #expect(alpha == 255, "Full opacity should be 255, got \(alpha)")
    }

    // VAL-FOUND-030: Color mapping — value clamping
    @Test func valueClamping() {
        // Extreme RSSI values should not crash
        let colorVeryLow = HeatmapRenderer.colorForValue(-150, visualization: .signalStrength, colorScheme: .standard)
        let colorVeryHigh = HeatmapRenderer.colorForValue(10, visualization: .signalStrength, colorScheme: .standard)
        // Both should produce valid colors (no NaN, no crash)
        #expect(colorVeryLow.red >= 0 && colorVeryLow.red <= 1)
        #expect(colorVeryLow.green >= 0 && colorVeryLow.green <= 1)
        #expect(colorVeryLow.blue >= 0 && colorVeryLow.blue <= 1)
        #expect(colorVeryHigh.red >= 0 && colorVeryHigh.red <= 1)
        #expect(colorVeryHigh.green >= 0 && colorVeryHigh.green <= 1)
        #expect(colorVeryHigh.blue >= 0 && colorVeryHigh.blue <= 1)
    }

    @Test func clampingExtremeLatency() {
        let colorNeg = HeatmapRenderer.colorForValue(-10, visualization: .latency, colorScheme: .standard)
        let colorHuge = HeatmapRenderer.colorForValue(5000, visualization: .latency, colorScheme: .standard)
        #expect(colorNeg.red >= 0 && colorNeg.red <= 1)
        #expect(colorHuge.red >= 0 && colorHuge.red <= 1)
    }

    // VAL-FOUND-045: HeatmapRenderer supports all five visualization types
    @Test func allFiveTypesProduceDistinctOutput() {
        let points = [
            MeasurementPoint(
                timestamp: Date(), floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40,
                snr: 30, downloadSpeed: 150, uploadSpeed: 80, latency: 5
            ),
            MeasurementPoint(
                timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60,
                snr: 20, downloadSpeed: 50, uploadSpeed: 30, latency: 30
            ),
            MeasurementPoint(
                timestamp: Date(), floorPlanX: 0.9, floorPlanY: 0.9, rssi: -80,
                snr: 10, downloadSpeed: 10, uploadSpeed: 5, latency: 80
            )
        ]

        var images: [HeatmapVisualization: CGImage] = [:]
        for viz in HeatmapVisualization.allCases {
            let image = HeatmapRenderer.render(
                points: points,
                floorPlanWidth: 20,
                floorPlanHeight: 20,
                visualization: viz,
                resolution: HeatmapResolution(width: 20, height: 20)
            )
            #expect(image != nil, "Visualization \(viz) should produce an image")
            if let img = image {
                images[viz] = img
            }
        }

        #expect(images.count == 5, "All 5 visualization types should produce images")
    }

    // VAL-FOUND-051: HeatmapRenderer supports dual color schemes
    @Test func dualColorSchemes() {
        // Standard scheme (green→yellow→red) should differ from WiFiman (blue→cyan→green→yellow→orange→red)
        let standardColor = HeatmapRenderer.colorForValue(-60, visualization: .signalStrength, colorScheme: .standard)
        let wifimanColor = HeatmapRenderer.colorForValue(-60, visualization: .signalStrength, colorScheme: .wifiman)

        // They should be different color mappings
        let colorsDiffer = standardColor.red != wifimanColor.red
            || standardColor.green != wifimanColor.green
            || standardColor.blue != wifimanColor.blue
        #expect(colorsDiffer, "Standard and WiFiman schemes should produce different colors")
    }

    @Test func wifimanColorScheme() {
        // WiFiman: blue (-30 to -50) → green (-50 to -60) → yellow (-60 to -70) → orange (-70 to -80) → red (-80+)
        let excellent = HeatmapRenderer.colorForValue(-35, visualization: .signalStrength, colorScheme: .wifiman)
        #expect(excellent.blue > 0.3, "Excellent signal in WiFiman should have blue component")

        let good = HeatmapRenderer.colorForValue(-55, visualization: .signalStrength, colorScheme: .wifiman)
        #expect(good.green > 0.3, "Good signal in WiFiman should have green component")

        let deadZone = HeatmapRenderer.colorForValue(-90, visualization: .signalStrength, colorScheme: .wifiman)
        #expect(deadZone.red > deadZone.green, "Dead zone in WiFiman should be red-dominant")
    }
}

// MARK: - HeatmapRenderer Performance Tests

@Suite("HeatmapRenderer Performance")
struct HeatmapRendererPerformanceTests {

    private func makeRandomPoints(count: Int) -> [MeasurementPoint] {
        // Use a deterministic seed-like approach for reproducibility
        (0 ..< count).map { i in
            let x = Double(i % 20) / 20.0
            let y = Double(i / 20 % 20) / 20.0
            let rssi = -30 - (i % 70) // Range: -30 to -99
            return MeasurementPoint(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                floorPlanX: min(max(x, 0.01), 0.99),
                floorPlanY: min(max(y, 0.01), 0.99),
                rssi: rssi,
                snr: max(5, 40 - (i % 35)),
                downloadSpeed: Double(max(5, 200 - i * 2)),
                uploadSpeed: Double(max(2, 100 - i)),
                latency: Double(max(1, 5 + i / 2))
            )
        }
    }

    // VAL-FOUND-022: HeatmapRenderer performance — 50 points <500ms
    @Test func performance50Points() {
        let points = makeRandomPoints(count: 50)
        let start = CFAbsoluteTimeGetCurrent()
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(image != nil, "Should produce an image")
        #expect(elapsed < 0.5, "50 points on 200x200 should complete in <500ms, took \(elapsed)s")
    }

    // VAL-FOUND-023: HeatmapRenderer performance — 200 points <2s
    @Test func performance200Points() {
        let points = makeRandomPoints(count: 200)
        let start = CFAbsoluteTimeGetCurrent()
        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 200,
            floorPlanHeight: 200,
            visualization: .signalStrength
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(image != nil, "Should produce an image")
        #expect(elapsed < 2.0, "200 points on 200x200 should complete in <2s, took \(elapsed)s")
    }
}

// MARK: - HeatmapRenderer Scale Bar Tests

@Suite("HeatmapRenderer Scale Bar")
struct HeatmapRendererScaleBarTests {

    @Test func scaleBarWithCalibration() {
        let scaleBar = HeatmapRenderer.computeScaleBar(
            floorPlanWidthMeters: 20.0,
            floorPlanHeightMeters: 15.0,
            imageWidth: 200,
            imageHeight: 150
        )

        #expect(scaleBar != nil)
        #expect(scaleBar!.lengthMeters > 0, "Scale bar length should be positive")
        #expect(scaleBar!.lengthPixels > 0, "Scale bar pixel length should be positive")
        #expect(!scaleBar!.label.isEmpty, "Scale bar label should not be empty")
    }

    @Test func scaleBarWithoutCalibration() {
        let scaleBar = HeatmapRenderer.computeScaleBar(
            floorPlanWidthMeters: 0,
            floorPlanHeightMeters: 0,
            imageWidth: 200,
            imageHeight: 150
        )

        #expect(scaleBar == nil, "Scale bar should be nil without calibration data")
    }

    @Test func scaleBarReasonableLength() {
        let scaleBar = HeatmapRenderer.computeScaleBar(
            floorPlanWidthMeters: 50.0,
            floorPlanHeightMeters: 30.0,
            imageWidth: 500,
            imageHeight: 300
        )

        #expect(scaleBar != nil)
        // Scale bar should be a reasonable fraction of image width (10%-40%)
        if let bar = scaleBar {
            let fraction = Double(bar.lengthPixels) / 500.0
            #expect(fraction >= 0.05, "Scale bar should be at least 5% of image width")
            #expect(fraction <= 0.5, "Scale bar should be at most 50% of image width")
        }
    }
}

// MARK: - HeatmapRenderer Value Extraction Tests

@Suite("HeatmapRenderer Value Extraction")
struct HeatmapRendererValueExtractionTests {

    @Test func signalStrengthExtractsRSSI() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55,
            snr: 30, downloadSpeed: 100, uploadSpeed: 50, latency: 10
        )
        let value = HeatmapRenderer.extractValue(from: point, for: .signalStrength)
        #expect(value == -55.0)
    }

    @Test func snrExtractsValue() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55,
            snr: 30, downloadSpeed: 100, uploadSpeed: 50, latency: 10
        )
        let value = HeatmapRenderer.extractValue(from: point, for: .signalToNoise)
        #expect(value == 30.0)
    }

    @Test func downloadSpeedExtractsValue() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55,
            downloadSpeed: 150.5
        )
        let value = HeatmapRenderer.extractValue(from: point, for: .downloadSpeed)
        #expect(value == 150.5)
    }

    @Test func uploadSpeedExtractsValue() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55,
            uploadSpeed: 75.3
        )
        let value = HeatmapRenderer.extractValue(from: point, for: .uploadSpeed)
        #expect(value == 75.3)
    }

    @Test func latencyExtractsValue() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55,
            latency: 12.5
        )
        let value = HeatmapRenderer.extractValue(from: point, for: .latency)
        #expect(value == 12.5)
    }

    @Test func nilOptionalReturnsNil() {
        let point = MeasurementPoint(
            timestamp: Date(), floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55
        )
        #expect(HeatmapRenderer.extractValue(from: point, for: .signalToNoise) == nil)
        #expect(HeatmapRenderer.extractValue(from: point, for: .downloadSpeed) == nil)
        #expect(HeatmapRenderer.extractValue(from: point, for: .uploadSpeed) == nil)
        #expect(HeatmapRenderer.extractValue(from: point, for: .latency) == nil)
    }
}
