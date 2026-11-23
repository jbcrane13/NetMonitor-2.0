import Foundation
import NetMonitorCore
import NetworkScanKit

// MARK: - AppEnvironment

/// Composition root for the iOS target. Holds references to the foundational
/// services that root ViewModels depend on so they can be wired explicitly
/// from `@main` instead of via scattered `Service.shared` defaults inside VM
/// init signatures.
///
/// **Migration pattern.** Root views read this from `@Environment`:
/// ```swift
/// @Environment(AppEnvironment.self) private var env
/// @State private var viewModel: DashboardViewModel
/// init(env: AppEnvironment) {
///     _viewModel = State(initialValue: DashboardViewModel(
///         networkMonitor: env.networkMonitor,
///         deviceDiscoveryService: env.deviceDiscovery,
///         ...
///     ))
/// }
/// ```
///
/// VM init signatures keep their existing `Service.shared` defaults during the
/// migration so tests and child views aren't broken. Once every root view is
/// migrated, those defaults can be removed in a follow-up.
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - Services

    let networkMonitor: any NetworkMonitorServiceProtocol
    let deviceDiscovery: any DeviceDiscoveryServiceProtocol
    let macConnection: any MacConnectionServiceProtocol
    let publicIP: any PublicIPServiceProtocol
    let wifiInfo: any WiFiInfoServiceProtocol
    let targetManager: TargetManager
    let activityLog: ToolActivityLog
    let eventService: NetworkEventService
    let scanScheduler: any ScanSchedulerServiceProtocol
    /// The network the device is on, for events and samples (#491 D9): the local profile, else
    /// the active one. Under `UITEST_FAKE_DEVICES`, the UI-test network.
    let currentNetworkProfileID: @MainActor () -> UUID?

    // MARK: - Init

    init(
        networkMonitor: any NetworkMonitorServiceProtocol,
        deviceDiscovery: any DeviceDiscoveryServiceProtocol,
        macConnection: any MacConnectionServiceProtocol,
        publicIP: any PublicIPServiceProtocol,
        wifiInfo: any WiFiInfoServiceProtocol,
        targetManager: TargetManager,
        activityLog: ToolActivityLog,
        eventService: NetworkEventService,
        scanScheduler: any ScanSchedulerServiceProtocol,
        currentNetworkProfileID: @escaping @MainActor () -> UUID? = { nil }
    ) {
        self.networkMonitor = networkMonitor
        self.deviceDiscovery = deviceDiscovery
        self.macConnection = macConnection
        self.publicIP = publicIP
        self.wifiInfo = wifiInfo
        self.targetManager = targetManager
        self.activityLog = activityLog
        self.eventService = eventService
        self.scanScheduler = scanScheduler
        self.currentNetworkProfileID = currentNetworkProfileID
    }

    // MARK: - Factories

    /// Production wiring. Uses the existing `*.shared` instances so services
    /// shared with `@main` lifecycle hooks (`EventListenerService`,
    /// `BackgroundTaskService`, etc.) keep observing the same state.
    ///
    /// Under `UITEST_FAKE_DEVICES`, the dashboard and the event listener share one fake discovery
    /// service, so UI tests never scan the real network (#491 D9).
    static func live() -> AppEnvironment {
        let fake = UITestFakeDeviceFeed.isEnabled
        let networkID: @MainActor () -> UUID?
        if fake {
            networkID = { UITestBootstrap.networkProfileID }
        } else {
            networkID = localNetworkID()
        }
        return AppEnvironment(
            networkMonitor: NetworkMonitorService.shared,
            deviceDiscovery: fake ? UITestFakeDiscoveryService() : DeviceDiscoveryService.shared,
            macConnection: MacConnectionService.shared,
            publicIP: PublicIPService(),
            wifiInfo: WiFiInfoService(),
            targetManager: TargetManager.shared,
            activityLog: ToolActivityLog.shared,
            eventService: NetworkEventService.shared,
            scanScheduler: ScanSchedulerService.shared,
            currentNetworkProfileID: networkID
        )
    }

    /// Re-detects the local network on each call, so the ID follows network changes.
    private static func localNetworkID() -> @MainActor () -> UUID? {
        let profiles = NetworkProfileManager()
        return {
            profiles.detectLocalNetwork()
            return profiles.localProfile?.id ?? profiles.activeProfile?.id
        }
    }
}

// MARK: - UI-test discovery

/// The discovery service UI tests get with `UITEST_FAKE_DEVICES=1` (#491 D9). A scan sets
/// `isScanning`, holds it for `hold` so observers see both states, then publishes the fixture
/// devices stamped with `UITestBootstrap.networkProfileID` and clears `isScanning`.
@MainActor
@Observable
final class UITestFakeDiscoveryService: DeviceDiscoveryServiceProtocol {
    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    private(set) var scanProgress: Double = 0
    private(set) var scanPhase: ScanDisplayPhase = .idle
    private(set) var lastScanDate: Date?
    private let devices: @MainActor () -> [DiscoveredDevice]
    private let hold: Duration

    init(devices: @escaping @MainActor () -> [DiscoveredDevice] = UITestFakeDiscoveryService.fixtureDevices, hold: Duration = .milliseconds(300)) {
        self.devices = devices
        self.hold = hold
    }

    /// The UI-test feed's devices on the UI-test network.
    static func fixtureDevices() -> [DiscoveredDevice] {
        UITestFakeDeviceFeed().devices.map { device in
            DiscoveredDevice(
                id: device.id,
                ipAddress: device.ipAddress,
                hostname: device.hostname,
                vendor: device.vendor,
                macAddress: device.macAddress,
                latency: device.latency,
                discoveredAt: device.discoveredAt,
                source: device.source,
                networkProfileID: UITestBootstrap.networkProfileID
            )
        }
    }

    func cachedDevices(for profile: NetworkProfile?) -> [DiscoveredDevice] {
        discoveredDevices
    }

    func scanNetwork(subnet: String? = nil) async {
        await scan()
    }

    func scanNetwork(profile: NetworkProfile?) async {
        await scan()
    }

    func stopScan() {
        isScanning = false
        scanPhase = .idle
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanPhase = .arpScan
        scanProgress = 0
        try? await Task.sleep(for: hold)
        discoveredDevices = devices()
        lastScanDate = Date()
        scanProgress = 1
        scanPhase = .idle
        isScanning = false
    }
}
