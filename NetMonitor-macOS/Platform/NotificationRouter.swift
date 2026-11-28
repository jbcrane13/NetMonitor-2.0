import Foundation
import NetMonitorCore
import Observation

/// Where an alert's View Details (or a click on the alert) takes the user (#478).
enum NotificationRoute: Equatable, Sendable {
    /// The monitored targets, which the menu bar popover lists.
    case targets
    /// The Devices list with this device selected, on its own network when known.
    case device(ipAddress: String, networkID: UUID?)
    /// The Devices list, where "Which network is this?" is answered (#645).
    case devices

    /// The route for a delivered alert, from its category and payload. Nil for an alert with
    /// nowhere to go.
    static func route(category: String, userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        switch category {
        case NotificationService.targetDownCategory, NotificationService.targetRecoveredCategory,
             NotificationService.highLatencyCategory:
            return .targets
        case NotificationService.newDeviceCategory, NotificationService.ruleMatchCategory:
            guard let ip = userInfo["ipAddress"] as? String, !ip.isEmpty else { return .targets }
            return .device(ipAddress: ip, networkID: (userInfo["networkID"] as? String).flatMap(UUID.init(uuidString:)))
        default:
            return nil
        }
    }
}

/// Hands a route from the notification delegate to the app (#478).
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    /// A device route for the main window, which clears it once it has navigated.
    var pending: NotificationRoute?
    /// The saved device Devices should select, set when the window opens Devices for a route.
    var deviceToSelect: UUID?
    /// Opens the menu bar popover; set by the app once the status item exists.
    @ObservationIgnored var showTargets: (@MainActor () -> Void)?

    /// Shows what `route` points at: the targets in the popover, or a device in the main
    /// window (opened if the user closed it).
    func open(_ route: NotificationRoute) {
        if route == .targets, let showTargets {
            showTargets()
            return
        }
        pending = route
        WindowOpener.shared.openMainWindow()
    }

    /// Where a route lands in the main window, given the saved devices at its address: the
    /// one on the alert's network, else the only one; with none (a rule can match a monitored
    /// target, or the popover isn't available), the local network's dashboard.
    ///
    /// `devices` are saved rows with their groups complete: a device is found by any interface's
    /// address and counts once (#594), and the ID handed on is its primary row's.
    static func selection(for route: NotificationRoute, devices: [LocalDevice], localNetworkID: UUID?)
        -> (section: SidebarSelection?, device: UUID?) {
        let dashboard: SidebarSelection? = localNetworkID.map { .network($0) }
        if route == .devices {
            return (.section(.devices), nil)
        }
        guard case let .device(ip, networkID) = route else { return (dashboard, nil) }
        let atAddress = DeviceGroups.project(devices).filter { device in device.members.contains { $0.ipAddress == ip } }
        let device = networkID.flatMap { id in atAddress.first { $0.primary.networkProfileID == id } }
            ?? (atAddress.count == 1 ? atAddress.first : nil)
        guard let device else { return (dashboard, nil) }
        return (.section(.devices), device.primary.id)
    }
}
