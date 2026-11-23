import Foundation
import NetMonitorCore

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
    /// The app's network profiles. `LocalNetworkChangeMonitor` keeps its local network current.
    let networkProfiles: NetworkProfileManager
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
        networkProfiles: NetworkProfileManager,
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
        self.networkProfiles = networkProfiles
        self.currentNetworkProfileID = currentNetworkProfileID
    }

    // MARK: - Factories

    /// Production wiring. Uses the existing `*.shared` instances so services shared with `@main`
    /// lifecycle hooks (`BackgroundTaskService`, etc.) keep observing the same state; the app builds
    /// its event listener from this environment's discovery service and network provider.
    ///
    /// Under `UITEST_FAKE_DEVICES`, the dashboard and the event listener share one fake discovery
    /// service, so UI tests never scan the real network (#491 D9).
    static func live() -> AppEnvironment {
        let fake = UITestFakeDeviceFeed.isEnabled
        let profiles = NetworkProfileManager()
        let networkID: @MainActor () -> UUID?
        if fake {
            networkID = { UITestBootstrap.networkProfileID }
        } else {
            // Read only: the network-change monitor re-detects into this same manager.
            networkID = { [weak profiles] in profiles?.localProfile?.id ?? profiles?.activeProfile?.id }
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
            networkProfiles: profiles,
            currentNetworkProfileID: networkID
        )
    }
}
