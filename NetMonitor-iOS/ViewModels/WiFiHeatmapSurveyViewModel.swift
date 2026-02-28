import Foundation
import SwiftUI
import NetMonitorCore
import NetworkExtension

// MARK: - WiFiHeatmapSurveyViewModel

@MainActor
@Observable
final class WiFiHeatmapSurveyViewModel {

    // MARK: - Survey state

    private(set) var isSurveying = false
    private(set) var currentSignalStrength: Int = 0  // dBm
    private(set) var dataPoints: [HeatmapDataPoint] = []
    private(set) var surveys: [HeatmapSurvey] = []
    private(set) var statusMessage = "Tap 'Start Survey' to begin"

    var selectedMode: HeatmapMode = .freeform
    var floorplanImageData: Data?

    // MARK: - Heatmap display settings

    private(set) var calibration: CalibrationScale?
    var colorScheme: HeatmapColorScheme = .thermal {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: AppSettings.Keys.heatmapColorScheme) }
    }

    var displayOverlays: HeatmapDisplayOverlay = .gradient {
        didSet { UserDefaults.standard.set(displayOverlays.rawValue, forKey: AppSettings.Keys.heatmapDisplayOverlays) }
    }

    var preferredUnit: DistanceUnit = .feet {
        didSet { UserDefaults.standard.set(preferredUnit.rawValue, forKey: AppSettings.Keys.heatmapPreferredUnit) }
    }

    var isCalibrating = false

    // MARK: - Private

    private let service: any WiFiHeatmapServiceProtocol
    private var signalRefreshTask: Task<Void, Never>?
    private static let surveysKey = "wifiHeatmap_surveys"

    // MARK: - Init

    init(service: any WiFiHeatmapServiceProtocol = WiFiHeatmapService()) {
        self.service = service
        loadSurveys()
        if let raw = UserDefaults.standard.string(forKey: AppSettings.Keys.heatmapColorScheme),
           let scheme = HeatmapColorScheme(rawValue: raw) {
            colorScheme = scheme
        }
        if let rawUnit = UserDefaults.standard.string(forKey: AppSettings.Keys.heatmapPreferredUnit),
           let unit = DistanceUnit(rawValue: rawUnit) {
            preferredUnit = unit
        }
        let overlayRaw = UserDefaults.standard.integer(forKey: AppSettings.Keys.heatmapDisplayOverlays)
        if overlayRaw != 0 {
            displayOverlays = HeatmapDisplayOverlay(rawValue: overlayRaw)
        }
    }

    // MARK: - Survey control

    func startSurvey() {
        guard !isSurveying else { return }
        isSurveying = true
        dataPoints = []
        service.startSurvey()
        statusMessage = "Walk around and tap to record signal at each spot"

        signalRefreshTask = Task {
            while !Task.isCancelled {
                await refreshSignalStrength()
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

        if dataPoints.isEmpty {
            statusMessage = "No data recorded. Tap 'Start Survey' to try again."
        } else {
            statusMessage = "Survey complete — \(dataPoints.count) measurements recorded"
            let survey = HeatmapSurvey(
                name: "Survey \(surveys.count + 1)",
                mode: selectedMode,
                dataPoints: dataPoints,
                calibration: calibration
            )
            surveys.insert(survey, at: 0)
            saveSurveys()
        }
    }

    func recordDataPoint(at point: CGPoint, in size: CGSize) {
        guard isSurveying, size.width > 0, size.height > 0 else { return }
        let nx = point.x / size.width
        let ny = point.y / size.height
        let signal = currentSignalStrength != 0 ? currentSignalStrength : simulatedRSSI()
        service.recordDataPoint(signalStrength: signal, x: nx, y: ny)
        dataPoints = service.getSurveyData()
        let level = SignalLevel.from(rssi: signal)
        statusMessage = "\(signal) dBm (\(level.label)) recorded"
    }

    func deleteSurvey(_ survey: HeatmapSurvey) {
        surveys.removeAll { $0.id == survey.id }
        saveSurveys()
    }

    // MARK: - Calibration

    func setCalibration(pixelDist: Double, realDist: Double, unit: DistanceUnit) {
        calibration = CalibrationScale(pixelDistance: pixelDist, realDistance: realDist, unit: unit)
        isCalibrating = false
    }

    func clearCalibration() {
        calibration = nil
    }

    // MARK: - Signal reading

    private func refreshSignalStrength() async {
        if #available(iOS 14.0, *) {
            let rssi: Double? = await withCheckedContinuation { continuation in
                NEHotspotNetwork.fetchCurrent { network in
                    continuation.resume(returning: network?.signalStrength)
                }
            }
            if let rssi {
                // signalStrength is 0.0–1.0 normalised; convert to approximate dBm range.
                currentSignalStrength = Int(-100.0 + Double(rssi) * 70.0)
                return
            }
        }
        currentSignalStrength = simulatedRSSI()
    }

    private func simulatedRSSI() -> Int {
        Int.random(in: -80...(-45))
    }

    // MARK: - Computed helpers

    var signalLevel: SignalLevel {
        SignalLevel.from(rssi: currentSignalStrength)
    }

    var signalText: String {
        isSurveying ? "\(currentSignalStrength) dBm" : "--"
    }

    func colorFor(point: HeatmapDataPoint) -> Color {
        switch SignalLevel.from(rssi: point.signalStrength) {
        case .strong: return .green
        case .fair:   return .yellow
        case .weak:   return .red
        }
    }

    var signalColor: Color {
        switch signalLevel {
        case .strong: return .green
        case .fair:   return .yellow
        case .weak:   return .red
        }
    }

    // MARK: - Persistence

    private func loadSurveys() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.surveysKey),
            let loaded = try? JSONDecoder().decode([HeatmapSurvey].self, from: data)
        else { return }
        surveys = loaded
    }

    private func saveSurveys() {
        guard let data = try? JSONEncoder().encode(surveys) else { return }
        UserDefaults.standard.set(data, forKey: Self.surveysKey)
    }
}
