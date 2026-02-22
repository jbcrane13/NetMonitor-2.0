import Foundation
import NetMonitorCore
import NetworkScanKit

@MainActor
@Observable
final class NetworkMapViewModel {
    var selectedDeviceIP: String?
    private let networkProfileManager: NetworkProfileManager
    private let pingService: any PingServiceProtocol
    private let userDefaults: UserDefaults

    let deviceDiscoveryService: any DeviceDiscoveryServiceProtocol
    let gatewayService: any GatewayServiceProtocol
    let bonjourService: any BonjourDiscoveryServiceProtocol
    let macConnectionService: any MacConnectionServiceProtocol

    private(set) var availableNetworks: [NetworkProfile] = []
    private(set) var selectedNetworkID: UUID?

    var selectedNetwork: NetworkProfile? {
        guard let selectedNetworkID else { return nil }
        return availableNetworks.first { $0.id == selectedNetworkID }
    }

    var activeNetwork: NetworkProfile? {
        selectedNetwork
            ?? networkProfileManager.activeProfile
            ?? availableNetworks.first(where: { $0.isLocal })
            ?? availableNetworks.first
    }

    init(
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        gatewayService: any GatewayServiceProtocol = GatewayService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = BonjourDiscoveryService(),
        macConnectionService: any MacConnectionServiceProtocol = MacConnectionService.shared,
        networkProfileManager: NetworkProfileManager = NetworkProfileManager(),
        pingService: any PingServiceProtocol = PingService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.deviceDiscoveryService = deviceDiscoveryService
        self.gatewayService = gatewayService
        self.bonjourService = bonjourService
        self.macConnectionService = macConnectionService
        self.networkProfileManager = networkProfileManager
        self.pingService = pingService
        self.userDefaults = userDefaults

        refreshAvailableNetworks()
        restoreSelectedNetwork()
    }

    var discoveredDevices: [DiscoveredDevice] {
        let serviceDevices = scopedDevices(from: deviceDiscoveryService.discoveredDevices)
        if !serviceDevices.isEmpty {
            return serviceDevices
        }
        return scopedDevices(from: deviceDiscoveryService.cachedDevices(for: activeNetwork))
    }

    var isScanning: Bool {
        deviceDiscoveryService.isScanning
    }

    var scanProgress: Double {
        deviceDiscoveryService.scanProgress
    }
    
    var scanPhaseText: String {
        let phase = deviceDiscoveryService.scanPhase
        switch phase {
        case .tcpProbe:
            return "Scanning… \(Int(deviceDiscoveryService.scanProgress * 100))%"
        case .idle, .done:
            return ""
        default:
            return phase.rawValue
        }
    }

    var deviceCount: Int {
        discoveredDevices.count
    }

    var gateway: GatewayInfo? {
        gatewayService.gateway
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

    var bonjourServices: [BonjourService] {
        bonjourService.discoveredServices
    }

    func startScan(forceRefresh: Bool = false) async {
        // Always detect gateway so the summary card shows it
        if gatewayService.gateway == nil {
            await gatewayService.detectGateway()
        }
        
        // Skip device scan if we already have cached results and not forcing refresh
        if !forceRefresh, !discoveredDevices.isEmpty {
            return
        }
        let profile = activeNetwork
        await deviceDiscoveryService.scanNetwork(profile: profile)
        updateScanMetadata(for: profile)
    }

    func stopScan() {
        deviceDiscoveryService.stopScan()
    }

    func selectDevice(_ ip: String?) {
        selectedDeviceIP = selectedDeviceIP == ip ? nil : ip
    }

    func startBonjourDiscovery() {
        bonjourService.startDiscovery(serviceType: nil)
    }

    func stopBonjourDiscovery() {
        bonjourService.stopDiscovery()
    }

    func refresh() async {
        refreshAvailableNetworks()
        await gatewayService.detectGateway()
        await startScan(forceRefresh: true)
    }

    func refreshAvailableNetworks() {
        networkProfileManager.detectLocalNetwork()
        availableNetworks = networkProfileManager.profiles.sorted(by: sortProfiles)
        if let selectedNetworkID, !availableNetworks.contains(where: { $0.id == selectedNetworkID }) {
            clearSelectedNetwork()
        }
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
        await startScan(forceRefresh: true)
        return true
    }

    /// Adds a network profile after validating the gateway is reachable.
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

        await startScan(forceRefresh: true)
        return nil
    }

    // MARK: - Private

    private func restoreSelectedNetwork() {
        guard let rawValue = userDefaults.string(forKey: AppSettings.Keys.selectedNetworkProfileID),
              let persistedID = UUID(uuidString: rawValue),
              availableNetworks.contains(where: { $0.id == persistedID }),
              networkProfileManager.switchProfile(id: persistedID) else {
            userDefaults.removeObject(forKey: AppSettings.Keys.selectedNetworkProfileID)
            return
        }

        selectedNetworkID = persistedID
    }

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
