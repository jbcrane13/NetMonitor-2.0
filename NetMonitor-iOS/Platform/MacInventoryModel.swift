import Foundation
import NetMonitorCore
import Observation
import SwiftData
import WidgetKit

/// The connected Mac's inventory for the network the phone is on (#585), computed once per change
/// and read by every view: when a list arrives, the link changes, the store saves, a scan finishes
/// or presence ticks. Views read `overlay` and never match or fetch themselves.
///
/// While the inventory is live it also publishes one online count (the list's) to the dashboard and
/// the widget; when it ends, the phone's own count is published again. The widget can't see a link
/// drop while the app is suspended: its count stays the last one published until the app runs.
@MainActor
@Observable
final class MacInventoryModel {
    private(set) var overlay: MacInventoryOverlay = .none

    @ObservationIgnored private let connection: any MacConnectionServiceProtocol
    @ObservationIgnored private let discovery: any DeviceDiscoveryServiceProtocol
    @ObservationIgnored private let presence: DevicePresenceModel
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let summaries: SavedDeviceSummaryModel
    @ObservationIgnored private let currentNetwork: @MainActor () -> NetworkProfile?
    @ObservationIgnored private let routedGateway: @MainActor () -> String?
    @ObservationIgnored private let widgetDefaults: UserDefaults
    @ObservationIgnored private let reloadsWidget: Bool
    /// The network whose count was last published from the inventory, to put back when it ends.
    @ObservationIgnored private var publishedNetwork: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var saves: NSObjectProtocol?

    init(
        connection: any MacConnectionServiceProtocol,
        discovery: any DeviceDiscoveryServiceProtocol,
        presence: DevicePresenceModel,
        context: ModelContext,
        summaries: SavedDeviceSummaryModel = .shared,
        currentNetwork: @escaping @MainActor () -> NetworkProfile? = { CurrentNetwork.detected() },
        routedGateway: @escaping @MainActor () -> String? = NetworkUtilities.detectRoutedGateway,
        widgetDefaults: UserDefaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard,
        reloadsWidget: Bool = true
    ) {
        self.connection = connection
        self.discovery = discovery
        self.presence = presence
        self.context = context
        self.summaries = summaries
        self.currentNetwork = currentNetwork
        self.routedGateway = routedGateway
        self.widgetDefaults = widgetDefaults
        self.reloadsWidget = reloadsWidget
    }

    /// Refreshes now and after every change it depends on, until the app ends.
    func start() {
        guard task == nil else { return }
        saves = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                let waiter = ObservationChangeWaiter()
                await waiter.wait { onChange in
                    withObservationTracking {
                        _ = self.connection.lastDeviceListReceivedAt
                        _ = self.connection.connectionState
                        _ = self.connection.linkPath
                        _ = self.discovery.lastScanDate
                        _ = self.presence.snapshot
                    } onChange: {
                        onChange()
                    }
                }
            }
        }
    }

    /// Computes the overlay for the network the phone is on now.
    func refresh() {
        let snapshot = presence.snapshot
        var phone = currentNetwork().map { PhoneNetwork(profile: $0, gatewayIP: routedGateway()) }
        var link = connection.linkPath
        #if DEBUG
        (phone, link) = UITestFakeMacPairing.standIns(phone: phone, link: link)
        #endif
        let networkID = phone?.profile.id
        let availability = MacInventory.availability(
            list: connection.lastDeviceList, receivedAt: connection.lastDeviceListReceivedAt,
            connected: connection.connectionState.isConnected, link: link, phone: phone, viewing: networkID, now: snapshot.now,
            policy: snapshot.policy
        )
        let ownScan = discovery.lastScanDate.map { OwnScan(date: $0, devices: discovery.completedScanDevices) }
        overlay = MacInventoryOverlay.make(
            availability: availability, networkID: networkID,
            rows: DeviceGroups.listedRows(network: networkID, limit: DeviceGroups.listedRowLimit, in: context),
            presence: snapshot, ownScan: ownScan
        )
        publishCount(snapshot)
    }

    /// The list's online count to the dashboard and the widget while the inventory is live; the
    /// phone's own once it ends.
    private func publishCount(_ snapshot: PresenceSnapshot) {
        if overlay.inventory != nil, let network = overlay.networkID {
            summaries.publish(
                SavedDeviceSummary(overlay: overlay, presence: snapshot), for: network, to: widgetDefaults, reloadWidget: reloadsWidget
            )
            publishedNetwork = network
        } else if let network = publishedNetwork {
            publishedNetwork = nil
            summaries.refresh(network: network, in: context, presence: snapshot, defaults: widgetDefaults, reloadWidget: reloadsWidget)
        }
    }
}
