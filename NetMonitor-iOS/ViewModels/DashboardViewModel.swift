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
    private let networkProfileManager: NetworkProfileManager
    private let pingService: any PingServiceProtocol
    private let userDefaults: UserDefaults

    // MARK: - Network Selection

    /// Available network interfaces for scanning.
    private(set) var availableNetworks: [NetworkProfile] = []

    /// Currently selected network profile. `nil` means auto-detect (default behavior).
    private(set) var selectedNetworkID: UUID?

    var selectedNetwork: NetworkProfile? {
        guard let id = selectedNetworkID else { return nil }
        return availableNetworks.first { $0.id == id }
    }

    var activeNetwork: NetworkProfile? {
        selectedNetwork
            ?? networkProfileManager.activeProfile
            ?? availableNetworks.first(where: { $0.isLocal })
            ?? availableNetworks.first
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
        macConnectionService: any MacConnectionServiceProtocol = MacConnectionService.shared,
        networkProfileManager: NetworkProfileManager = NetworkProfileManager(),
        pingService: any PingServiceProtocol = PingService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.networkMonitor = networkMonitor
        self.wifiService = wifiService
        self.gatewayService = gatewayService
        self.publicIPService = publicIPService
        self.deviceDiscoveryService = deviceDiscoveryService
        self.macConnectionService = macConnectionService
        self.networkProfileManager = networkProfileManager
        self.pingService = pingService
        self.userDefaults = userDefaults
        self.sessionStartTime = Date()

        refreshAvailableNetworks()
        restoreSelectedNetwork(
            userDefaults: userDefaults,
            availableNetworks: availableNetworks,
            networkProfileManager: networkProfileManager,
            selectedNetworkID: &selectedNetworkID
        )
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
        let currentDevices = scopedDevices(from: deviceDiscoveryService.discoveredDevices)
        if !currentDevices.isEmpty {
            return currentDevices
        }
        return scopedDevices(from: deviceDiscoveryService.cachedDevices(for: activeNetwork))
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

    var activeNetworkLastScanned: Date? {
        activeNetwork?.lastScanned
    }

    var activeNetworkDeviceCount: Int? {
        activeNetwork?.deviceCount
    }

    var activeNetworkGatewayReachable: Bool? {
        activeNetwork?.gatewayReachable
    }

    var isShowingStaleActiveNetworkData: Bool {
        (activeNetwork?.gatewayReachable == false) && (activeNetwork?.lastScanned != nil)
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
        networkProfileManager.detectLocalNetwork()
        availableNetworks = networkProfileManager.profiles.sorted(by: sortProfiles)
        if let selectedNetworkID, !availableNetworks.contains(where: { $0.id == selectedNetworkID }) {
            clearSelectedNetwork()
        }
    }

    func startDeviceScan() async {
        let profile = activeNetwork
        await deviceDiscoveryService.scanNetwork(profile: profile)
        updateScanMetadata(for: profile)
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

    @discardableResult
    func selectNetwork(id: UUID?) async -> Bool {
        if selectedNetworkID == id {
            return true
        }

        if let id {
            if !availableNetworks.contains(where: { $0.id == id }) {
                refreshAvailableNetworks()
            }

            guard networkProfileManager.switchProfile(id: id) else {
                return false
            }

            selectedNetworkID = id
            persistSelectedNetwork()
        } else {
            networkProfileManager.detectLocalNetwork()
            if let localID = networkProfileManager.profiles.first(where: { $0.isLocal })?.id {
                _ = networkProfileManager.switchProfile(id: localID)
            }
            clearSelectedNetwork()
        }

        await startDeviceScan()
        return true
    }

    /// Adds a network profile after validating that the target gateway is reachable over ICMP/TCP ping.
    /// - Returns: `nil` on success, or a user-facing error message.
    func addNetworkProfile(gateway: String, subnet: String, name: String) async -> String? {
        let trimmedGateway = gateway.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubnet = subnet.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedGateway.isEmpty, !trimmedSubnet.isEmpty else {
            return "Gateway and CIDR are required."
        }

        let isReachable = await isHostReachable(trimmedGateway)
        guard isReachable else {
            return "Gateway did not respond to ICMP validation."
        }

        guard let profile = networkProfileManager.addProfile(
            gateway: trimmedGateway,
            subnet: trimmedSubnet,
            name: trimmedName
        ) else {
            return "Invalid network details. Check gateway IP and CIDR."
        }

        refreshAvailableNetworks()
        _ = networkProfileManager.switchProfile(id: profile.id)
        selectedNetworkID = profile.id
        persistSelectedNetwork()

        await deviceDiscoveryService.scanNetwork(profile: profile)
        return nil
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

    // MARK: - Private

    private func clearSelectedNetwork() {
        selectedNetworkID = nil
        persistSelectedNetwork()
    }

    private func persistSelectedNetwork() {
        if let selectedNetworkID {
            userDefaults.set(selectedNetworkID.uuidString, forKey: AppSettings.Keys.selectedNetworkProfileID)
        } else {
            userDefaults.removeObject(forKey: AppSettings.Keys.selectedNetworkProfileID)
        }
    }

    private func isHostReachable(_ host: String) async -> Bool {
        let pingStream = await pingService.ping(host: host, count: 2, timeout: 1.5)

        for await result in pingStream {
            if !result.isTimeout {
                return true
            }
        }

        return false
    }

    private func sortProfiles(_ lhs: NetworkProfile, _ rhs: NetworkProfile) -> Bool {
        if lhs.isLocal != rhs.isLocal {
            return lhs.isLocal
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func scopedDevices(from devices: [DiscoveredDevice]) -> [DiscoveredDevice] {
        let activeProfileID = activeNetwork?.id
        return devices.filter { $0.networkProfileID == activeProfileID }
    }

    private func updateScanMetadata(for profile: NetworkProfile?) {
        guard let profile else { return }
        let scoped = scopedDevices(from: deviceDiscoveryService.discoveredDevices)
        networkProfileManager.updateProfileScanInfo(
            id: profile.id,
            lastScanned: Date(),
            deviceCount: scoped.count,
            gatewayReachable: scoped.contains(where: { $0.ipAddress == profile.gatewayIP })
        )
        refreshAvailableNetworks()
    }
}
