import CoreGraphics
import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Test Helpers

@MainActor
private func makeProject() -> SurveyProject {
    let floorPlan = FloorPlan(
        imageData: Data([1, 2, 3]),
        widthMeters: 10,
        heightMeters: 10,
        pixelWidth: 1000,
        pixelHeight: 500
    )
    return SurveyProject(name: "Test", floorPlan: floorPlan)
}

@MainActor
private func makePoint(rssi: Int = -55, ssid: String? = "A", bssid: String? = "11:22:33:44:55:66") -> MeasurementPoint {
    MeasurementPoint(
        floorPlanX: 0.5,
        floorPlanY: 0.5,
        rssi: rssi,
        ssid: ssid,
        bssid: bssid
    )
}

// MARK: - Initial State

@MainActor
struct HeatmapSurveyStateInitialTests {

    @Test func initialStateIsEmpty() {
        let s = HeatmapSurveyState()
        #expect(s.surveyProject == nil)
        #expect(s.measurementPoints.isEmpty)
        #expect(s.isSurveying == false)
        #expect(s.isMeasuring == false)
        #expect(s.isCalibrating == false)
        #expect(s.isCalibrated == false)
        #expect(s.calibrationPoints.isEmpty)
        #expect(s.canUndo == false)
        #expect(s.hasFloorPlan == false)
        #expect(s.selectedAPFilter == nil)
        #expect(s.errorMessage == nil)
    }

    @Test func defaultVisualizationIsSignalStrength() {
        let s = HeatmapSurveyState()
        #expect(s.selectedVisualization == .signalStrength)
        #expect(s.selectedColorScheme == .thermal)
        #expect(s.heatmapOpacity == 0.7)
    }
}

// MARK: - Calibration

@MainActor
struct HeatmapSurveyStateCalibrationTests {

    @Test func startCalibrationFlipsFlags() {
        let s = HeatmapSurveyState()
        s.isCalibrated = true
        s.startCalibration()
        #expect(s.isCalibrating)
        #expect(s.isCalibrated == false)
        #expect(s.calibrationPoints.isEmpty)
    }

    @Test func addCalibrationPointCapsAtTwo() {
        let s = HeatmapSurveyState()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        s.addCalibrationPoint(at: CGPoint(x: 200, y: 0))
        #expect(s.calibrationPoints.count == 2)
    }

    @Test func secondCalibrationPointShowsSheet() {
        let s = HeatmapSurveyState()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        #expect(s.showCalibrationSheet == false)
        s.addCalibrationPoint(at: CGPoint(x: 50, y: 0))
        #expect(s.showCalibrationSheet)
    }

    @Test func skipCalibrationCompletes() {
        let s = HeatmapSurveyState()
        s.startCalibration()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.skipCalibration()
        #expect(s.isCalibrating == false)
        #expect(s.isCalibrated)
        #expect(s.calibrationPoints.isEmpty)
    }

    @Test func cancelCalibrationDropsPoints() {
        let s = HeatmapSurveyState()
        s.startCalibration()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.cancelCalibration()
        #expect(s.isCalibrating == false)
        #expect(s.isCalibrated == false)
        #expect(s.calibrationPoints.isEmpty)
    }

    @Test func completeCalibrationUpdatesFloorPlan() {
        let s = HeatmapSurveyState()
        s.setProject(makeProject())
        s.startCalibration()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        s.completeCalibration(withDistance: 10) // 10 m across 100 px → 0.1 m/px

        #expect(s.isCalibrated)
        #expect(s.isCalibrating == false)
        #expect(s.calibrationPoints.isEmpty)
        let plan = s.surveyProject?.floorPlan
        #expect(plan?.widthMeters == 100)  // 1000 px * 0.1 m/px
        #expect(plan?.heightMeters == 50)  // 500 px * 0.1 m/px
        #expect(plan?.calibrationPoints?.count == 2)
    }

    @Test func completeCalibrationNoOpsWithoutProject() {
        let s = HeatmapSurveyState()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        s.completeCalibration(withDistance: 10)
        #expect(s.isCalibrated == false)
        #expect(s.calibrationPoints.isEmpty)
    }

    @Test func feetToMetersConversion() {
        let s = HeatmapSurveyState()
        s.setProject(makeProject())
        s.startCalibration()
        s.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        s.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        // 10 ft = 3.048 m; over 100 px → 0.03048 m/px
        s.completeCalibration(distance: 10, isFeet: true)
        let plan = s.surveyProject?.floorPlan
        // widthMeters = 1000 * 0.03048 = 30.48
        #expect(abs((plan?.widthMeters ?? 0) - 30.48) < 0.001)
    }
}

// MARK: - Measurements + Undo

@MainActor
struct HeatmapSurveyStateMeasurementTests {

    @Test func recordMeasurementAppendsAndEnablesUndo() {
        let s = HeatmapSurveyState()
        let p = makePoint()
        s.recordMeasurement(p)
        #expect(s.measurementPoints.count == 1)
        #expect(s.canUndo)
    }

    @Test func undoRestoresPriorState() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint(rssi: -50))
        s.recordMeasurement(makePoint(rssi: -60))
        #expect(s.measurementPoints.count == 2)
        s.undo()
        #expect(s.measurementPoints.count == 1)
        s.undo()
        #expect(s.measurementPoints.isEmpty)
        // Past empty: no-op
        s.undo()
        #expect(s.measurementPoints.isEmpty)
    }

    @Test func deleteMeasurementRemovesById() {
        let s = HeatmapSurveyState()
        let p1 = makePoint(rssi: -50)
        let p2 = makePoint(rssi: -60)
        s.recordMeasurement(p1)
        s.recordMeasurement(p2)
        s.deleteMeasurement(id: p1.id)
        #expect(s.measurementPoints.count == 1)
        #expect(s.measurementPoints.first?.id == p2.id)
    }

    @Test func clearMeasurementsEmptiesList() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint())
        s.recordMeasurement(makePoint())
        s.clearMeasurements()
        #expect(s.measurementPoints.isEmpty)
        // But undo should restore
        s.undo()
        #expect(s.measurementPoints.count == 2)
    }

    @Test func undoStackCapsAtMaxSnapshots() {
        let s = HeatmapSurveyState()
        for _ in 0..<(HeatmapSurveyState.maxUndoSnapshots + 5) {
            s.recordMeasurement(makePoint())
        }
        // Each record adds an undo snapshot — capped.
        // Undo `maxUndoSnapshots` times then no more.
        for _ in 0..<HeatmapSurveyState.maxUndoSnapshots {
            s.undo()
        }
        #expect(s.canUndo == false)
    }

    @Test func setMeasurementsDoesNotSnapshotUndo() {
        let s = HeatmapSurveyState()
        s.setMeasurements([makePoint(), makePoint()])
        #expect(s.measurementPoints.count == 2)
        #expect(s.canUndo == false)
    }
}

// MARK: - AP Filter + Derived

@MainActor
struct HeatmapSurveyStateFilteringTests {

    @Test func filteredPointsRespectsFilter() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint(ssid: "A", bssid: "AA"))
        s.recordMeasurement(makePoint(ssid: "B", bssid: "BB"))
        #expect(s.filteredPoints.count == 2)
        s.selectedAPFilter = "AA"
        #expect(s.filteredPoints.count == 1)
        #expect(s.filteredPoints.first?.bssid == "AA")
    }

    @Test func uniqueBSSIDsExcludesUnknown() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint(ssid: "Net1", bssid: "11"))
        s.recordMeasurement(makePoint(ssid: "Net2", bssid: "22"))
        s.recordMeasurement(makePoint(ssid: nil, bssid: nil))  // unknown → excluded
        let bssids = s.uniqueBSSIDs
        #expect(bssids.count == 2)
        #expect(Set(bssids.map(\.bssid)) == ["11", "22"])
    }

    @Test func averageRSSIRespectsFilter() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint(rssi: -40, bssid: "A"))
        s.recordMeasurement(makePoint(rssi: -60, bssid: "A"))
        s.recordMeasurement(makePoint(rssi: -80, bssid: "B"))
        #expect(s.averageRSSI == -60)  // (-40 + -60 + -80) / 3
        s.selectedAPFilter = "A"
        #expect(s.averageRSSI == -50)  // (-40 + -60) / 2
    }
}

// MARK: - Project Lifecycle

@MainActor
struct HeatmapSurveyStateProjectTests {

    @Test func setProjectFreshNeedsCalibration() {
        let s = HeatmapSurveyState()
        s.setProject(makeProject())
        #expect(s.hasFloorPlan)
        #expect(s.isCalibrating)
        #expect(s.isCalibrated == false)
    }

    @Test func setProjectPreCalibratedSkipsCalibration() {
        let s = HeatmapSurveyState()
        let plan = FloorPlan(
            imageData: Data([1]),
            widthMeters: 10,
            heightMeters: 10,
            pixelWidth: 100,
            pixelHeight: 100,
            calibrationPoints: [
                CalibrationPoint(pixelX: 0, pixelY: 0),
                CalibrationPoint(pixelX: 100, pixelY: 0)
            ]
        )
        let project = SurveyProject(name: "Pre-Cal", floorPlan: plan)
        s.setProject(project)
        #expect(s.isCalibrated)
        #expect(s.isCalibrating == false)
    }

    @Test func setProjectClearsUndo() {
        let s = HeatmapSurveyState()
        s.recordMeasurement(makePoint())
        #expect(s.canUndo)
        s.setProject(makeProject())
        #expect(s.canUndo == false)
    }
}

// MARK: - Survey Lifecycle

@MainActor
struct HeatmapSurveyStateSurveyTests {

    @Test func startSurveyRequiresProjectAndCalibration() {
        let s = HeatmapSurveyState()
        s.startSurvey()
        #expect(s.isSurveying == false)  // no project

        s.setProject(makeProject())
        s.startSurvey()
        #expect(s.isSurveying == false)  // not yet calibrated

        s.skipCalibration()
        s.startSurvey()
        #expect(s.isSurveying)
    }

    @Test func stopSurveyClearsFlag() {
        let s = HeatmapSurveyState()
        s.setProject(makeProject())
        s.skipCalibration()
        s.startSurvey()
        s.stopSurvey()
        #expect(s.isSurveying == false)
    }
}
