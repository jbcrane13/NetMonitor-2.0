import Foundation
import NetMonitorCore
import SystemConfiguration.CaptiveNetwork
import CoreLocation
import Network
import NetworkExtension

@MainActor
@Observable
final class WiFiInfoService: NSObject, WiFiInfoServiceProtocol {
    private(set) var currentWiFi: WiFiInfo?
    private(set) var isLocationAuthorized: Bool = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    private var retryTask: Task<Void, Never>?

    // MARK: - TTL Cache (VAL-IOS-039)

    /// Minimum interval between NEHotspotNetwork polls to avoid Apple rate limiting.
    private static let cacheTTL: TimeInterval = 1.0
    private var lastFetchTime: Date?
    private var cachedResult: WiFiInfo?
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkAuthorizationStatus()
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func refreshWiFiInfo() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            self.currentWiFi = await self.fetchCurrentWiFi()
        }
    }

    func fetchCurrentWiFi() async -> WiFiInfo? {
        // Return cached result if within TTL window (VAL-IOS-039)
        if let lastFetchTime, let cachedResult,
           Date().timeIntervalSince(lastFetchTime) < Self.cacheTTL {
            return cachedResult
        }

        #if targetEnvironment(simulator)
        let result = mockWiFiInfo()
        lastFetchTime = Date()
        cachedResult = result
        return result
        #else
        // Re-check live status every call. Other flows may request permission
        // via separate CLLocationManager instances, so cached flags can be stale.
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        isLocationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways

        // Try modern API first. Some devices return nil transiently; a short
        // retry improves reliability without introducing noticeable UI delay.
        for attempt in 0..<2 {
            if let info = await fetchWiFiInfoModern() {
                lastFetchTime = Date()
                cachedResult = info
                return info
            }
            if attempt == 0 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return nil }
            }
        }

        // Fall back to legacy API (no log spam)
        let legacyResult = fetchWiFiInfoLegacy()
        if let legacyResult {
            lastFetchTime = Date()
            cachedResult = legacyResult
        }
        return legacyResult
        #endif
    }

    private func checkAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
        isLocationAuthorized = authorizationStatus == .authorizedWhenInUse ||
                               authorizationStatus == .authorizedAlways

        #if targetEnvironment(simulator)
        refreshWiFiInfo()
        #else
        if isLocationAuthorized {
            refreshWiFiInfo()
        }
        #endif
    }
    
    // MARK: - Modern API (iOS 14+)
    
    private func fetchWiFiInfoModern() async -> WiFiInfo? {
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            return nil
        }

        // signalStrength is 0.0 when the system can't read the actual value
        // (e.g. transient failure). Treat as nil so the HUD doesn't show "0%".
        let strength = network.signalStrength
        let clamped = max(0, min(1, strength))
        let signalStrength = strength > 0 ? Int(clamped * 100) : nil
        return WiFiInfo(
            ssid: network.ssid,
            bssid: network.bssid,
            signalStrength: signalStrength,
            signalDBm: signalStrength.map { Self.percentToApproxDBm($0) },
            channel: nil,
            frequency: nil,
            band: nil,
            securityType: Self.securityLabel(for: network)
        )
    }
    
    // MARK: - Security Type Mapping
    
    private static func securityLabel(for network: NEHotspotNetwork) -> String {
        // NEHotspotNetworkSecurityType raw values: 0=Open, 1=WEP, 2=Personal, 3=Enterprise, 4=Unknown
        switch network.securityType.rawValue {
        case 0:  return "Open"
        case 1:  return "WEP"
        case 2:  return "WPA/WPA2/WPA3"
        case 3:  return "WPA Enterprise"
        default: return "Secured"
        }
    }

    private static func percentToApproxDBm(_ percent: Int) -> Int {
        let clamped = max(0, min(100, percent))
        return Int(-100.0 + (Double(clamped) / 100.0 * 70.0))
    }
    
    // MARK: - Legacy API (fallback)
    
    private func fetchWiFiInfoLegacy() -> WiFiInfo? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String],
              let interface = interfaces.first,
              let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
              let ssid = info[kCNNetworkInfoKeySSID as String] as? String else {
            return nil
        }

        let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String

        return WiFiInfo(
            ssid: ssid,
            bssid: bssid,
            signalStrength: nil,
            signalDBm: nil,
            channel: nil,
            frequency: nil,
            band: nil,
            securityType: nil
        )
    }
    
    // MARK: - Simulator Mock
    
    // periphery:ignore
    private func mockWiFiInfo() -> WiFiInfo {
        WiFiInfo(
            ssid: "Simulator WiFi",
            bssid: "00:00:00:00:00:00",
            signalStrength: nil,
            signalDBm: -45,
            channel: 6,
            frequency: nil,
            band: .band2_4GHz,
            securityType: "WPA3"
        )
    }
}

extension WiFiInfoService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkAuthorizationStatus()
        }
    }
}

// WiFiInfoServiceProtocol conformance declared in ServiceProtocols.swift
