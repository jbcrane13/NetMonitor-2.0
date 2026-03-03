import Foundation
import SwiftUI
import NetMonitorCore
import CoreLocation

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
    private(set) var locationDenied = false

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
    private let signalSampler: any WiFiSignalSampling
    private let locationDelegate = HeatmapLocationDelegate()
    private var signalRefreshTask: Task<Void, Never>?
    private var usingEstimatedSignal = false
    private static let surveysKey = "wifiHeatmap_surveys"

    // MARK: - Init

    init(
        service: any WiFiHeatmapServiceProtocol = WiFiHeatmapService(),
        signalSampler: any WiFiSignalSampling = WiFiSignalSampler()
    ) {
        self.service = service
        self.signalSampler = signalSampler
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

        #if targetEnvironment(simulator)
        // Skip location check on simulator — NEHotspotNetwork uses mock values.
        beginSurvey()
        return
        #else
        // NEHotspotNetwork.fetchCurrent requires location authorization
        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.manager.requestWhenInUseAuthorization()
            beginSurvey(usingEstimatedSignal: true)
            statusMessage = "Grant location access for live WiFi RSSI (using estimated signal now)"
            // Update mode once authorization resolves.
            locationDelegate.onAuthorized = { [weak self] in
                Task { @MainActor in
                    self?.locationDenied = false
                    self?.usingEstimatedSignal = false
                    self?.statusMessage = "Walk around and tap to record signal at each spot"
                }
            }
            locationDelegate.onDenied = { [weak self] in
                Task { @MainActor in
                    self?.locationDenied = true
                    self?.usingEstimatedSignal = true
                    self?.statusMessage = "Location denied — continuing with estimated WiFi signal"
                }
            }
            return
        } else if status == .denied || status == .restricted {
            locationDenied = true
            beginSurvey(usingEstimatedSignal: true)
            statusMessage = "Location denied — continuing with estimated WiFi signal"
            return
        }

        beginSurvey()
        #endif
    }

    private func beginSurvey(usingEstimatedSignal: Bool = false) {
        locationDenied = false
        self.usingEstimatedSignal = usingEstimatedSignal
        isSurveying = true
        currentSignalStrength = currentSignalStrength == 0 ? -65 : currentSignalStrength
        dataPoints = []
        service.startSurvey()
        statusMessage = usingEstimatedSignal
            ? "Walk around and tap to record points (estimated WiFi signal)"
            : "Walk around and tap to record signal at each spot"

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
        // Use real signal; if we havent read one yet, use -65 dBm as reasonable default
        let signal = currentSignalStrength != 0 ? currentSignalStrength : -65
        service.recordDataPoint(signalStrength: signal, x: nx, y: ny)
        dataPoints = service.getSurveyData()
        let level = SignalLevel.from(rssi: signal)
        statusMessage = "\(signal) dBm (\(level.label)) recorded"
    }

    func addSurvey(_ survey: HeatmapSurvey) {
        surveys.insert(survey, at: 0)
        saveSurveys()
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
        let sample = await signalSampler.currentSample()
        if let dbm = sample.dbm {
            currentSignalStrength = dbm
            if usingEstimatedSignal {
                usingEstimatedSignal = false
                if isSurveying {
                    statusMessage = "Walk around and tap to record signal at each spot"
                }
            }
        } else {
            // Keep last known if we have one, otherwise indicate unavailable.
            if currentSignalStrength == 0 {
                currentSignalStrength = -65
            }
            if isSurveying && !usingEstimatedSignal {
                usingEstimatedSignal = true
                statusMessage = "Live WiFi RSSI unavailable — using estimated signal"
            }
        }
    }

    // MARK: - Computed helpers

    var signalLevel: SignalLevel {
        SignalLevel.from(rssi: currentSignalStrength)
    // periphery:ignore
    }

    var signalText: String {
        isSurveying ? "\(currentSignalStrength) dBm" : "--"
    }

    // periphery:ignore
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

// MARK: - Location Authorization Helper

/// Lightweight CLLocationManager delegate for heatmap WiFi permission requests.
/// Separate from WiFiInfoService to avoid coupling the heatmap to dashboard services.
private final class HeatmapLocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var onAuthorized: (() -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            onAuthorized?()
            onAuthorized = nil
            onDenied = nil
        case .denied, .restricted:
            onDenied?()
            onAuthorized = nil
            onDenied = nil
        default:
            break
        }
    }
}
