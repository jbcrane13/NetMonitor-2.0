import Foundation
import SwiftUI
import NetMonitorCore
import NetworkExtension
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
    private let locationDelegate = HeatmapLocationDelegate()
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

        #if targetEnvironment(simulator)
        // Skip location check on simulator — NEHotspotNetwork uses mock values.
        beginSurvey()
        return
        #else
        // NEHotspotNetwork.fetchCurrent requires location authorization
        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.manager.requestWhenInUseAuthorization()
            statusMessage = "Grant location access to read WiFi signal"
            // Wait for authorization then auto-start
            locationDelegate.onAuthorized = { [weak self] in
                Task { @MainActor in
                    self?.beginSurvey()
                }
            }
            locationDelegate.onDenied = { [weak self] in
                Task { @MainActor in
                    self?.locationDenied = true
                    self?.statusMessage = "Location access required for WiFi signal reading"
                }
            }
            return
        } else if status == .denied || status == .restricted {
            locationDenied = true
            statusMessage = "Location access denied — enable in Settings > Privacy > Location Services"
            return
        }

        beginSurvey()
        #endif
    }

    private func beginSurvey() {
        locationDenied = false
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
        let rssi: Double? = await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.signalStrength)
            }
        }
        if let rssi, rssi > 0 {
            // signalStrength is 0.0–1.0 normalised; convert to approximate dBm range.
            currentSignalStrength = Int(-100.0 + rssi * 70.0)
        } else {
            // NEHotspotNetwork returned nil — likely no WiFi or missing permission.
            // Show last known value if we have one, otherwise indicate no signal.
            if currentSignalStrength == 0 {
                statusMessage = isSurveying
                    ? "Unable to read WiFi signal — check location permissions"
                    : statusMessage
            }
        }
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
