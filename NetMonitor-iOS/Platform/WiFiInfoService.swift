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
        
        #if targetEnvironment(simulator)
        currentWiFi = mockWiFiInfo()
        #else
        guard isLocationAuthorized else {
            currentWiFi = nil
            return
        }
        // NEHotspotNetwork.fetchCurrent() can return nil on first call —
        // retry once with a short delay, then fall back to legacy API.
        // Avoid excessive retries as each call logs "nehelper sent invalid
        // result code [1]" when the entitlement or WiFi info is unavailable.
        retryTask = Task {
            // Try modern API first (1 attempt + 1 retry)
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                }

                if let info = await fetchWiFiInfoModern() {
                    currentWiFi = info
                    return
                }
            }

            // Fall back to legacy API (no log spam)
            if let info = fetchWiFiInfoLegacy() {
                currentWiFi = info
                return
            }

            // All attempts exhausted — clear any stale data
            currentWiFi = nil
        }
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
        
        return WiFiInfo(
            ssid: network.ssid,
            bssid: network.bssid,
            signalStrength: Int(network.signalStrength * 100),
            signalDBm: nil,
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
