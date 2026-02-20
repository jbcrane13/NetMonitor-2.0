import Foundation
import NetMonitorCore
import SwiftUI
import NetworkScanKit

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var isRefreshing = false
    private(set) var sessionStartTime: Date
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Network Selection

    /// Available network interfaces for scanning.
    private(set) var availableNetworks: [NetworkProfile] = []

    /// Currently selected network profile. `nil` means auto-detect (default behavior).
    var selectedNetworkID: String?

    var selectedNetwork: NetworkProfile? {
        guard let id = selectedNetworkID else { return nil }
        return availableNetworks.first { $0.id == id }
    }

    let networkMonitor: any NetworkMonitorServiceProtocol
    let wifiService: any WiFiInfoServiceProtocol
    let gatewayService: any GatewayServiceProtocol
    let publicIPService: any PublicIPServiceProtocol
    let deviceDiscoveryService: any DeviceDiscoveryServiceProtocol
    let macConnectionService: any MacConnectionServiceProtocol

    init(
        networkMonitor: any NetworkMonitorServiceProtocol = NetworkMonitorService.shared,
        wifiService: any WiFiInfoServiceProtocol = WiFiInfoService(),
        gatewayService: any GatewayServiceProtocol = GatewayService(),
        publicIPService: any PublicIPServiceProtocol = PublicIPService(),
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        macConnectionService: any MacConnectionServiceProtocol = MacConnectionService.shared
    ) {
        self.networkMonitor = networkMonitor
        self.wifiService = wifiService
        self.gatewayService = gatewayService
        self.publicIPService = publicIPService
        self.deviceDiscoveryService = deviceDiscoveryService
        self.macConnectionService = macConnectionService
        self.sessionStartTime = Date()
    }
    
    var isConnected: Bool {
        networkMonitor.isConnected
    }
    
    var connectionType: ConnectionType {
        networkMonitor.connectionType
    }
    
    var connectionStatusText: String {
        networkMonitor.statusText
    }
    
    var currentWiFi: WiFiInfo? {
        wifiService.currentWiFi
    }
    
    var gateway: GatewayInfo? {
        gatewayService.gateway
    }
    
    var ispInfo: ISPInfo? {
        publicIPService.ispInfo
    }
    
    var discoveredDevices: [DiscoveredDevice] {
        deviceDiscoveryService.discoveredDevices
    }
    
    var deviceCount: Int {
        discoveredDevices.count
    }
    
    var lastScanDate: Date? {
        deviceDiscoveryService.lastScanDate
    }
    
    var isScanning: Bool {
        deviceDiscoveryService.isScanning
    }
    
    var sessionDuration: String {
        let interval = Date().timeIntervalSince(sessionStartTime)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    var sessionStartTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Today, \(formatter.string(from: sessionStartTime))"
    }
    
    func refresh(forceIP: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        wifiService.refreshWiFiInfo()
        
        await gatewayService.detectGateway()
        // Auto-refresh uses cache (5-min TTL); manual pull-to-refresh forces a fresh fetch
        await publicIPService.fetchPublicIP(forceRefresh: forceIP)
    }
    
    func refreshAvailableNetworks() {
        availableNetworks = NetworkProfileManager.detectActiveProfiles()
    }

    func startDeviceScan() async {
        await deviceDiscoveryService.scanNetwork(profile: selectedNetwork)
    }

    func stopDeviceScan() {
        deviceDiscoveryService.stopScan()
    }
    
    func refreshPublicIP() async {
        await publicIPService.fetchPublicIP(forceRefresh: true)
    }
    
    func requestLocationPermission() {
        wifiService.requestLocationPermission()
    }
    
    var needsLocationPermission: Bool {
        !wifiService.isLocationAuthorized
    }

    // MARK: - Auto-Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                let interval = UserDefaults.standard.object(forKey: AppSettings.Keys.autoRefreshInterval) as? Int ?? 60
                guard interval > 0 else {
                    // Manual mode — wait a bit then re-check in case user changes setting
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
