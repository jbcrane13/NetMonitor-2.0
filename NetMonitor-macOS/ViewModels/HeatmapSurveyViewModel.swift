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

    // MARK: - Services
    private var wifiEngine: WiFiMeasurementEngine?
    private var renderer: HeatmapRenderer
    private let wifiService = MacWiFiInfoService()

    // MARK: - Measurement Mode
    enum MeasurementMode: String, CaseIterable {
        case passive  // RSSI, SNR only
        case active   // + speed test, latency
    }

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    private func setupEngine() {
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(from url: URL) throws {
        let imageData = try Data(contentsOf: url)
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,  // Default, user can calibrate
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: url.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
        measurementPoints = []
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
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

        measurementPoints.append(point)
    }

    // MARK: - Heatmap Rendering

    func renderHeatmap() -> CGImage? {
        renderer.render(points: measurementPoints, visualization: selectedVisualization)
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

    // MARK: - Clear

    func clearMeasurements() {
        measurementPoints = []
    }
}

// MARK: - Errors

enum HeatmapError: Error, LocalizedError {
    case invalidImage
    case noFloorPlan
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image format"
        case .noFloorPlan: return "No floor plan loaded"
        case .saveFailed: return "Failed to save project"
        }
    }
}
