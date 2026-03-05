import Foundation
import SwiftUI
import NetMonitorCore

@MainActor
@Observable
final class HeatmapSurveyViewModel {
    // MARK: - Published State
    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var selectedVisualization: HeatmapVisualization = .signalStrength
    var measurementMode: MeasurementMode = .passive
    var isMeasuring: Bool = false
    var showImportSheet: Bool = false
    var currentRSSI: Int = -100

    // MARK: - Services
    private var wifiEngine: WiFiMeasurementEngine?
    private var renderer: HeatmapRenderer
    private var wifiService: WiFiInfoService?

    // MARK: - Measurement Mode
    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    init() {
        renderer = HeatmapRenderer()
    }

    private func setupEngineIfNeeded() {
        if wifiEngine == nil {
            let service = WiFiInfoService()
            self.wifiService = service
            let speedService = SpeedTestService()
            let pingService = PingService()
            wifiEngine = WiFiMeasurementEngine(
                wifiService: service,
                speedTestService: speedService,
                pingService: pingService
            )
        }
    }

    func onAppear() {
        setupEngineIfNeeded()
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(imageData: Data, width: Int, height: Int) {
        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: width,
            pixelHeight: height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: "Survey",
            floorPlan: floorPlan
        )
        measurementPoints = []
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        setupEngineIfNeeded()
        guard let project = surveyProject, !isMeasuring else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        let point: MeasurementPoint
        if measurementMode == .active {
            point = await wifiEngine?.takeActiveMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        } else {
            point = await wifiEngine?.takeMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        }

        currentRSSI = point.rssi
        measurementPoints.append(point)
    }

    // MARK: - Heatmap Rendering

    func renderHeatmap() -> CGImage? {
        renderer.render(points: measurementPoints, visualization: selectedVisualization)
    }

    // MARK: - Clear

    func clearMeasurements() {
        measurementPoints = []
    }

    // MARK: - Save/Load

    func saveProject(to url: URL) throws {
        guard var project = surveyProject else { return }
        project.measurementPoints = measurementPoints
        let manager = ProjectSaveLoadManager()
        try manager.save(project: project, to: url)
    }

    func loadProject(from url: URL) throws {
        let manager = ProjectSaveLoadManager()
        surveyProject = try manager.load(from: url)
        measurementPoints = surveyProject?.measurementPoints ?? []
    }
}
