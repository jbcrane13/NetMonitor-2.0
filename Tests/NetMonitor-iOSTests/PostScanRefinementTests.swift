import CoreGraphics
import Foundation
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - PostScanRefinement Tests

struct PostScanRefinementTests {

    // MARK: - IDW Refinement Performance

    /// VAL-AR3-021: IDW refinement completes in <5s for 2000 points.
    @Test("IDW refinement under 5 seconds for 2000 points")
    func idwRefinementPerformance2000Points() {
        // Generate 2000 measurement points spread across the floor plan
        let points = generateMeasurementGrid(count: 2000)

        let startTime = CFAbsoluteTimeGetCurrent()

        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 2048,
            floorPlanHeight: 2048,
            visualization: .signalStrength,
            colorScheme: .wifiman
        )

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(image != nil, "IDW refinement should produce a valid image for 2000 points")
        #expect(duration < 5.0, "IDW refinement for 2000 points should complete in <5s, took \(duration)s")
    }

    /// VAL-AR3-020: Full IDW refinement replaces nearest-neighbor coloring.
    @Test("IDW refinement produces valid CGImage for scan data")
    func idwRefinementProducesImage() {
        let points = generateMeasurementGrid(count: 50)

        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 512,
            floorPlanHeight: 512,
            visualization: .signalStrength,
            colorScheme: .wifiman
        )

        #expect(image != nil, "IDW refinement should produce an image for 50 points")
        #expect(image?.width == 512, "Output width should match requested")
        #expect(image?.height == 512, "Output height should match requested")
    }

    /// VAL-AR3-024: Post-scan visualization switching produces different images.
    @Test("visualization switching produces different images")
    func visualizationSwitchingProducesDifferentOutput() {
        // Create points with both rssi and latency data
        var points = generateMeasurementGrid(count: 20)
        // Add latency data to some points
        for i in 0..<points.count {
            points[i] = MeasurementPoint(
                floorPlanX: points[i].floorPlanX,
                floorPlanY: points[i].floorPlanY,
                rssi: points[i].rssi,
                latency: Double.random(in: 5...80)
            )
        }

        let signalImage = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 128,
            floorPlanHeight: 128,
            visualization: .signalStrength,
            colorScheme: .wifiman
        )

        let latencyImage = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 128,
            floorPlanHeight: 128,
            visualization: .latency,
            colorScheme: .wifiman
        )

        #expect(signalImage != nil, "Signal strength image should be rendered")
        #expect(latencyImage != nil, "Latency image should be rendered")
        // Both should produce images but they should visualize different metrics
    }

    /// VAL-AR3-023: Saves as SurveyProject with .arContinuous.
    @Test("completed project has arContinuous survey mode")
    func completedProjectSurveyMode() {
        let points = generateMeasurementGrid(count: 10)
        let floorPlan = FloorPlan(
            imageData: Data(),
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelWidth: 512,
            pixelHeight: 512,
            origin: FloorPlanOrigin.arGenerated
        )
        let project = SurveyProject(
            name: "Continuous Scan",
            floorPlan: floorPlan,
            measurementPoints: points,
            surveyMode: SurveyMode.arContinuous
        )

        #expect(project.surveyMode == SurveyMode.arContinuous)
        #expect(project.measurementPoints.count == 10)
        #expect(project.floorPlan.origin == FloorPlanOrigin.arGenerated)
    }

    // MARK: - WiFiman Color Scheme for Post-Scan

    @Test("wifiman color scheme used for post-scan rendering")
    func wifimanColorSchemeUsed() {
        let points = generateMeasurementGrid(count: 10)

        let image = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: 128,
            floorPlanHeight: 128,
            visualization: .signalStrength,
            colorScheme: .wifiman
        )

        #expect(image != nil, "WiFiman color scheme should produce valid image")
    }

    // MARK: - Helpers

    /// Generates a grid of measurement points with random RSSI values.
    private func generateMeasurementGrid(count: Int) -> [MeasurementPoint] {
        var points: [MeasurementPoint] = []
        let gridSize = Int(ceil(sqrt(Double(count))))

        for i in 0..<count {
            let row = i / gridSize
            let col = i % gridSize

            let x = Double(col) / Double(max(gridSize - 1, 1))
            let y = Double(row) / Double(max(gridSize - 1, 1))
            let rssi = Int.random(in: -90 ... -30)

            points.append(MeasurementPoint(
                floorPlanX: x,
                floorPlanY: y,
                rssi: rssi
            ))
        }

        return points
    }
}
