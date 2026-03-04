import Foundation
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ContinuousCapturePipeline Tests

@Suite("ContinuousCapturePipeline")
struct ContinuousCapturePipelineTests {

    // MARK: - Adaptive Rate Logic

    @Suite("Adaptive Rate")
    struct AdaptiveRateTests {

        @Test("moving state returns default 500ms interval")
        func movingReturnsDefaultInterval() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .moving)
            #expect(interval == 0.5)
        }

        @Test("stationary <3s returns default 500ms interval")
        func stationaryUnderThresholdReturnsDefault() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .stationary(duration: 2.0))
            #expect(interval == 0.5)
        }

        @Test("stationary at exactly 3s returns slow 2000ms interval")
        func stationaryAtThresholdReturnsSlow() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .stationary(duration: 3.0))
            #expect(interval == 2.0)
        }

        @Test("stationary >3s returns slow 2000ms interval")
        func stationaryOverThresholdReturnsSlow() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .stationary(duration: 10.0))
            #expect(interval == 2.0)
        }

        @Test("stationary at 2.9s returns default interval")
        func stationaryJustBelowThresholdReturnsDefault() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .stationary(duration: 2.9))
            #expect(interval == 0.5)
        }

        @Test("stationary at 0s returns default interval")
        func stationaryZeroDurationReturnsDefault() {
            let interval = ContinuousCapturePipeline.adaptiveInterval(for: .stationary(duration: 0.0))
            #expect(interval == 0.5)
        }

        @Test("default interval constant is 0.5 (2Hz)")
        func defaultIntervalIs2Hz() {
            #expect(ContinuousCapturePipeline.defaultInterval == 0.5)
        }

        @Test("stationary interval constant is 2.0 (0.5Hz)")
        func stationaryIntervalIs0_5Hz() {
            #expect(ContinuousCapturePipeline.stationaryInterval == 2.0)
        }

        @Test("stationary threshold is 3 seconds")
        func stationaryThresholdIs3Seconds() {
            #expect(ContinuousCapturePipeline.stationaryThreshold == 3.0)
        }
    }

    // MARK: - Grid Cell Computation

    @Suite("Grid Cell")
    struct GridCellTests {

        @Test("origin maps to cell (0, 0)")
        func originMapsToZeroCell() {
            let cell = ContinuousCapturePipeline.gridCell(arX: 0.1, arZ: 0.1)
            #expect(cell.cellX == 0)
            #expect(cell.cellY == 0)
        }

        @Test("negative coordinates map to negative cells")
        func negativeCoordsMapToNegativeCells() {
            let cell = ContinuousCapturePipeline.gridCell(arX: -1.0, arZ: -2.0)
            #expect(cell.cellX < 0)
            #expect(cell.cellY < 0)
        }

        @Test("points in same 0.5m² area share a cell")
        func pointsInSameCellShareCell() {
            let cellSize = ContinuousCapturePipeline.gridCellSize
            let cell1 = ContinuousCapturePipeline.gridCell(arX: 0.1, arZ: 0.1)
            let cell2 = ContinuousCapturePipeline.gridCell(arX: 0.2, arZ: 0.2)
            // Both within one cell (cellSize ~0.707m)
            #expect(cell1.cellX == cell2.cellX)
            #expect(cell1.cellY == cell2.cellY)

            // Point in next cell
            let cell3 = ContinuousCapturePipeline.gridCell(arX: cellSize + 0.1, arZ: 0.1)
            #expect(cell3.cellX == cell1.cellX + 1)
        }

        @Test("grid cell size produces ~0.5m² area")
        func gridCellSizeProducesHalfSquareMeter() {
            let cellSize = ContinuousCapturePipeline.gridCellSize
            let area = cellSize * cellSize
            // 0.707 * 0.707 ≈ 0.5
            #expect(abs(area - 0.5) < 0.01)
        }
    }

    // MARK: - Downsampling

    @Suite("Downsampling")
    struct DownsamplingTests {

        @Test("empty measurements produce empty result")
        func emptyInputProducesEmptyOutput() {
            let result = ContinuousCapturePipeline.downsample([])
            #expect(result.isEmpty)
        }

        @Test("single measurement passes through")
        func singleMeasurementPassesThrough() {
            let point = makeMeasurement(rssi: -50, floorPlanX: 0.5, floorPlanY: 0.5)
            let positioned = PositionedMeasurement(measurement: point, arX: 1.0, arZ: 1.0)

            let result = ContinuousCapturePipeline.downsample([positioned])
            #expect(result.count == 1)
            #expect(result[0].rssi == -50)
        }

        @Test("multiple measurements in same cell produce one point")
        func sameCellProducesOnePoint() {
            // Place three measurements close together (within one grid cell)
            let m1 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -40, floorPlanX: 0.1, floorPlanY: 0.1),
                arX: 0.1, arZ: 0.1
            )
            let m2 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -60, floorPlanX: 0.15, floorPlanY: 0.15),
                arX: 0.15, arZ: 0.15
            )
            let m3 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -50, floorPlanX: 0.2, floorPlanY: 0.2),
                arX: 0.2, arZ: 0.2
            )

            let result = ContinuousCapturePipeline.downsample([m1, m2, m3])
            #expect(result.count == 1)
        }

        @Test("measurements in different cells produce multiple points")
        func differentCellsProduceMultiplePoints() {
            let cellSize = ContinuousCapturePipeline.gridCellSize
            let m1 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -40, floorPlanX: 0.1, floorPlanY: 0.1),
                arX: 0.1, arZ: 0.1
            )
            let m2 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -60, floorPlanX: 0.5, floorPlanY: 0.5),
                arX: cellSize + 0.5, arZ: cellSize + 0.5
            )
            let m3 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -70, floorPlanX: 0.9, floorPlanY: 0.9),
                arX: 2 * cellSize + 0.5, arZ: 2 * cellSize + 0.5
            )

            let result = ContinuousCapturePipeline.downsample([m1, m2, m3])
            #expect(result.count == 3)
        }

        @Test("median RSSI selection — odd count selects middle")
        func medianSelectionOddCount() {
            let m1 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -30, floorPlanX: 0.1, floorPlanY: 0.1),
                arX: 0.1, arZ: 0.1
            )
            let m2 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -50, floorPlanX: 0.15, floorPlanY: 0.15),
                arX: 0.15, arZ: 0.15
            )
            let m3 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -80, floorPlanX: 0.2, floorPlanY: 0.2),
                arX: 0.2, arZ: 0.2
            )

            let result = ContinuousCapturePipeline.medianRSSIMeasurement(from: [m1, m2, m3])
            #expect(result != nil)
            // Sorted: -80, -50, -30. Median index = 1 → RSSI = -50
            #expect(result?.measurement.rssi == -50)
        }

        @Test("median RSSI selection — even count selects upper middle")
        func medianSelectionEvenCount() {
            let m1 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -40, floorPlanX: 0.1, floorPlanY: 0.1),
                arX: 0.1, arZ: 0.1
            )
            let m2 = PositionedMeasurement(
                measurement: makeMeasurement(rssi: -60, floorPlanX: 0.15, floorPlanY: 0.15),
                arX: 0.15, arZ: 0.15
            )

            let result = ContinuousCapturePipeline.medianRSSIMeasurement(from: [m1, m2])
            #expect(result != nil)
            // Sorted: -60, -40. Index = 1 → RSSI = -40
            #expect(result?.measurement.rssi == -40)
        }

        @Test("median returns nil for empty array")
        func medianReturnsNilForEmpty() {
            let result = ContinuousCapturePipeline.medianRSSIMeasurement(from: [])
            #expect(result == nil)
        }

        @Test("downsampling preserves measurement fields")
        func downsamplingPreservesMeasurementFields() {
            let point = MeasurementPoint(
                floorPlanX: 0.5,
                floorPlanY: 0.6,
                rssi: -55,
                ssid: "TestNetwork",
                bssid: "AA:BB:CC:DD:EE:FF",
                channel: 6,
                band: .band2_4GHz
            )
            let positioned = PositionedMeasurement(measurement: point, arX: 1.0, arZ: 1.0)

            let result = ContinuousCapturePipeline.downsample([positioned])
            #expect(result.count == 1)
            #expect(result[0].ssid == "TestNetwork")
            #expect(result[0].bssid == "AA:BB:CC:DD:EE:FF")
            #expect(result[0].channel == 6)
            #expect(result[0].band == .band2_4GHz)
            #expect(result[0].floorPlanX == 0.5)
            #expect(result[0].floorPlanY == 0.6)
        }

        @Test("downsampling max 1 per grid cell with many points")
        func downsamplingMaxOnePerCell() {
            // Place 10 measurements in the same cell
            var measurements: [PositionedMeasurement] = []
            for i in 0..<10 {
                let rssi = -40 - i
                let offset = Float(i) * 0.01 // tiny offset, same cell
                let point = makeMeasurement(rssi: rssi, floorPlanX: 0.5, floorPlanY: 0.5)
                measurements.append(PositionedMeasurement(measurement: point, arX: 0.1 + offset, arZ: 0.1))
            }

            let result = ContinuousCapturePipeline.downsample(measurements)
            #expect(result.count == 1)
        }
    }

    // MARK: - Position Tagging

    @Suite("Position Tagging")
    struct PositionTaggingTests {

        @Test("PositionedMeasurement stores AR coordinates")
        func positionedMeasurementStoresCoords() {
            let point = makeMeasurement(rssi: -50, floorPlanX: 0.3, floorPlanY: 0.7)
            let positioned = PositionedMeasurement(measurement: point, arX: 2.5, arZ: -1.3)

            #expect(positioned.arX == 2.5)
            #expect(positioned.arZ == -1.3)
            #expect(positioned.measurement.rssi == -50)
            #expect(positioned.measurement.floorPlanX == 0.3)
            #expect(positioned.measurement.floorPlanY == 0.7)
        }

        @Test("PositionedMeasurement is Sendable")
        func positionedMeasurementIsSendable() {
            // Compile-time check — if this compiles, the type is Sendable
            let point = makeMeasurement(rssi: -50, floorPlanX: 0.5, floorPlanY: 0.5)
            let positioned: any Sendable = PositionedMeasurement(measurement: point, arX: 1.0, arZ: 1.0)
            #expect(positioned is PositionedMeasurement)
        }

        @Test("PositionedMeasurement is Equatable")
        func positionedMeasurementIsEquatable() {
            let point = makeMeasurement(rssi: -50, floorPlanX: 0.5, floorPlanY: 0.5)
            let p1 = PositionedMeasurement(measurement: point, arX: 1.0, arZ: 2.0)
            let p2 = PositionedMeasurement(measurement: point, arX: 1.0, arZ: 2.0)
            #expect(p1 == p2)
        }
    }

    // MARK: - Pipeline State

    @Suite("Pipeline State")
    @MainActor
    struct PipelineStateTests {

        @Test("pipeline starts not capturing")
        func pipelineStartsNotCapturing() async {
            let engine = MockCaptureHeatmapService()
            let pipeline = ContinuousCapturePipeline(measurementEngine: engine)

            let isCapturing = await pipeline.isCapturing
            #expect(isCapturing == false)
        }

        @Test("pipeline raw measurements start empty")
        func pipelineRawMeasurementsStartEmpty() async {
            let engine = MockCaptureHeatmapService()
            let pipeline = ContinuousCapturePipeline(measurementEngine: engine)

            let count = await pipeline.rawMeasurementCount
            #expect(count == 0)
        }

        @Test("pipeline downsampled points start empty")
        func pipelineDownsampledPointsStartEmpty() async {
            let engine = MockCaptureHeatmapService()
            let pipeline = ContinuousCapturePipeline(measurementEngine: engine)

            let count = await pipeline.downsampledPointCount
            #expect(count == 0)
        }

        @Test("pipeline initial motion state is moving")
        func pipelineInitialMotionStateIsMoving() async {
            let engine = MockCaptureHeatmapService()
            let pipeline = ContinuousCapturePipeline(measurementEngine: engine)

            let state = await pipeline.motionState
            #expect(state == .moving)
        }

        @Test("reset clears all data")
        func resetClearsAllData() async {
            let engine = MockCaptureHeatmapService()
            let pipeline = ContinuousCapturePipeline(measurementEngine: engine)

            await pipeline.reset()

            let rawCount = await pipeline.rawMeasurementCount
            let dsCount = await pipeline.downsampledPointCount
            let isCapturing = await pipeline.isCapturing
            #expect(rawCount == 0)
            #expect(dsCount == 0)
            #expect(isCapturing == false)
        }
    }

    // MARK: - MotionState Enum

    @Suite("MotionState")
    struct MotionStateTests {

        @Test("moving equals moving")
        func movingEqualsMoving() {
            #expect(MotionState.moving == MotionState.moving)
        }

        @Test("stationary with same duration are equal")
        func stationaryWithSameDurationEqual() {
            #expect(MotionState.stationary(duration: 5.0) == MotionState.stationary(duration: 5.0))
        }

        @Test("stationary with different durations are not equal")
        func stationaryWithDifferentDurationsNotEqual() {
            #expect(MotionState.stationary(duration: 3.0) != MotionState.stationary(duration: 4.0))
        }

        @Test("moving and stationary are not equal")
        func movingAndStationaryNotEqual() {
            #expect(MotionState.moving != MotionState.stationary(duration: 0.0))
        }
    }

    // MARK: - Helpers

    static func makeMeasurement(rssi: Int, floorPlanX: Double, floorPlanY: Double) -> MeasurementPoint {
        MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: rssi
        )
    }
}

/// File-level helper for creating test measurements.
private func makeMeasurement(rssi: Int, floorPlanX: Double, floorPlanY: Double) -> MeasurementPoint {
    MeasurementPoint(
        floorPlanX: floorPlanX,
        floorPlanY: floorPlanY,
        rssi: rssi
    )
}

// MARK: - Mock Capture Heatmap Service

/// Mock implementation of HeatmapServiceProtocol for testing the capture pipeline.
final class MockCaptureHeatmapService: HeatmapServiceProtocol, @unchecked Sendable {
    var mockRSSI: Int = -50
    var mockSSID: String? = "TestNetwork"
    var takeMeasurementCallCount = 0
    var stopContinuousCallCount = 0

    func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        takeMeasurementCallCount += 1
        return MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: mockRSSI,
            ssid: mockSSID
        )
    }

    func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        await takeMeasurement(at: floorPlanX, floorPlanY: floorPlanY)
    }

    func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stopContinuousMeasurement() async {
        stopContinuousCallCount += 1
    }
}
