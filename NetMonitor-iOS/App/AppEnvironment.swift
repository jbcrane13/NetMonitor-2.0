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
    /// The network the device is on, for events (#491 D9): the saved local profile, read without
    /// writing. Under `UITEST_FAKE_DEVICES`, the UI-test network.
    let currentNetworkProfileID: @MainActor () -> UUID?
    /// The network health samples belong to (#491 S5): the local network only while it is
    /// connected, never the active profile. Under `UITEST_FAKE_DEVICES`, the UI-test network.
    let connectedNetworkProfileID: @MainActor () -> UUID?

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
        currentNetworkProfileID: @escaping @MainActor () -> UUID? = { nil },
        connectedNetworkProfileID: @escaping @MainActor () -> UUID? = { nil }
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
        self.connectedNetworkProfileID = connectedNetworkProfileID
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
        let networkID: @MainActor () -> UUID?
        let connectedNetworkID: @MainActor () -> UUID?
        if fake {
            networkID = { UITestBootstrap.networkProfileID }
            connectedNetworkID = { UITestBootstrap.networkProfileID }
        } else {
            // Read only, from the saved profiles: a manager of its own would save its startup
            // copy of the list over networks added since (#491).
            networkID = { NetworkProfileManager.savedLocalProfile()?.id }
            connectedNetworkID = {
                NetworkProfileManager.detectActiveProfiles().isEmpty ? nil : NetworkProfileManager.savedLocalProfile()?.id
            }
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
            currentNetworkProfileID: networkID,
            connectedNetworkProfileID: connectedNetworkID
        )
    }
}
