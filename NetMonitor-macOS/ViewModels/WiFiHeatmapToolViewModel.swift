import Foundation
import SwiftUI
import NetMonitorCore

// MARK: - WiFiHeatmapToolViewModel (macOS)

@MainActor
@Observable
final class WiFiHeatmapToolViewModel {

    // MARK: - Survey state
    private(set) var isSurveying = false
    private(set) var currentRSSI: Int = 0
    private(set) var dataPoints: [HeatmapDataPoint] = []
    private(set) var surveys: [HeatmapSurvey] = []
    private(set) var selectedSurveyID: UUID? = nil
    private(set) var statusMessage = "Click 'Start Survey' to begin"

    var persistenceError: String?
    var colorScheme: HeatmapColorScheme = .thermal
    var displayOverlays: HeatmapDisplayOverlay = .gradient
    var preferredUnit: DistanceUnit = .feet
    var calibration: CalibrationScale? = nil
    var floorplanImage: NSImage? = nil
    var hoverPoint: CGPoint? = nil
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero

    // MARK: - Private
    private let service: any WiFiHeatmapServiceProtocol
    private var signalRefreshTask: Task<Void, Never>?
    private static let surveysKey = "wifiHeatmap_surveys_mac"

    private var macService: WiFiHeatmapService? { service as? WiFiHeatmapService }

    init(service: any WiFiHeatmapServiceProtocol = WiFiHeatmapService()) {
        self.service = service
        loadSurveys()
    }

    // MARK: - Survey control

    func startSurvey() {
        guard !isSurveying else { return }
        isSurveying = true
        dataPoints = []
        service.startSurvey()
        statusMessage = "Click the canvas to record signal at each location"

        signalRefreshTask = Task {
            while !Task.isCancelled {
                currentRSSI = macService?.currentRSSI() ?? macService?.simulatedRSSI() ?? Int.random(in: -80...(-45))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSurvey() {
        guard isSurveying else { return }
        isSurveying = false
        signalRefreshTask?.cancel()
        signalRefreshTask = nil
        service.stopSurvey()
        dataPoints = service.getSurveyData()

        if !dataPoints.isEmpty {
            let survey = HeatmapSurvey(
                name: "Survey \(surveys.count + 1)",
                mode: floorplanImage != nil ? .floorplan : .freeform,
                dataPoints: dataPoints,
                calibration: calibration
            )
            surveys.insert(survey, at: 0)
            selectedSurveyID = survey.id
            saveSurveys()
        }
        statusMessage = dataPoints.isEmpty
            ? "No data recorded. Start another survey."
            : "Survey complete — \(dataPoints.count) measurements"
    }

    func recordDataPoint(at point: CGPoint, in size: CGSize) {
        guard isSurveying, size.width > 0, size.height > 0 else { return }
        let nx = point.x / size.width
        let ny = point.y / size.height
        let rssi = currentRSSI != 0 ? currentRSSI : macService?.simulatedRSSI() ?? Int.random(in: -80...(-45))
        service.recordDataPoint(signalStrength: rssi, x: nx, y: ny)
        dataPoints = service.getSurveyData()
        statusMessage = "\(rssi) dBm recorded at (\(String(format: "%.2f", nx)), \(String(format: "%.2f", ny)))"
    }

    func selectSurvey(_ survey: HeatmapSurvey) {
        selectedSurveyID = survey.id
        dataPoints = survey.dataPoints
        calibration = survey.calibration
    }

    func deleteSurvey(_ survey: HeatmapSurvey) {
        surveys.removeAll { $0.id == survey.id }
        if selectedSurveyID == survey.id { selectedSurveyID = surveys.first?.id }
        saveSurveys()
    }

    func setCalibration(pixelDist: Double, realDist: Double, unit: DistanceUnit) {
        calibration = CalibrationScale(pixelDistance: pixelDist, realDistance: realDist, unit: unit)
    }

    func clearCalibration() { calibration = nil }

    // MARK: - Computed

    var stats: HeatmapRenderer.SurveyStats {
        HeatmapRenderer.computeStats(points: dataPoints, calibration: calibration, unit: preferredUnit)
    }

    var signalColor: Color {
        switch SignalLevel.from(rssi: currentRSSI) {
        case .strong: return .green
        case .fair:   return .yellow
        case .weak:   return .red
        }
    }

    // MARK: - Persistence

    private func loadSurveys() {
        guard let data = UserDefaults.standard.data(forKey: Self.surveysKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([HeatmapSurvey].self, from: data)
            surveys = loaded
            selectedSurveyID = surveys.first?.id
            if let first = surveys.first { dataPoints = first.dataPoints
            calibration = first.calibration
            }
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func saveSurveys() {
        do {
            let data = try JSONEncoder().encode(surveys)
            UserDefaults.standard.set(data, forKey: Self.surveysKey)
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}
