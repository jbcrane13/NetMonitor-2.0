import Foundation
import NetMonitorCore
import NetworkScanKit

@MainActor
@Observable
final class NetworkMapViewModel {
    var selectedDeviceIP: String?

    /// Cached devices that persist across tab switches
    private(set) var cachedDevices: [DiscoveredDevice] = []
    private var lastCacheDate: Date?

    let deviceDiscoveryService: any DeviceDiscoveryServiceProtocol
    let gatewayService: any GatewayServiceProtocol
    let bonjourService: any BonjourDiscoveryServiceProtocol
    let macConnectionService: any MacConnectionServiceProtocol

    init(
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        gatewayService: any GatewayServiceProtocol = GatewayService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = BonjourDiscoveryService(),
        macConnectionService: any MacConnectionServiceProtocol = MacConnectionService.shared
    ) {
        self.deviceDiscoveryService = deviceDiscoveryService
        self.gatewayService = gatewayService
        self.bonjourService = bonjourService
        self.macConnectionService = macConnectionService
    }

    var discoveredDevices: [DiscoveredDevice] {
        // Return service devices if a scan is active or just finished, otherwise cached
        let serviceDevices = deviceDiscoveryService.discoveredDevices
        if !serviceDevices.isEmpty {
            return serviceDevices
        }
        return cachedDevices
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

    var bonjourServices: [BonjourService] {
        bonjourService.discoveredServices
    }

    func startScan(forceRefresh: Bool = false) async {
        // Always detect gateway so the summary card shows it
        if gatewayService.gateway == nil {
            await gatewayService.detectGateway()
        }
        
        // Skip device scan if we already have cached results and not forcing refresh
        if !forceRefresh, !cachedDevices.isEmpty {
            return
        }
        await deviceDiscoveryService.scanNetwork(subnet: nil)
        // Cache the results after scan completes
        let results = deviceDiscoveryService.discoveredDevices
        if !results.isEmpty {
            cachedDevices = results
            lastCacheDate = Date()
        }
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
        await gatewayService.detectGateway()
        await startScan(forceRefresh: true)
    }
}
