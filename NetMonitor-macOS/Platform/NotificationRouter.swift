import Foundation
import NetMonitorCore
import Observation

/// Where an alert's View Details (or a click on the alert) takes the user (#478).
enum NotificationRoute: Equatable {
    /// The local network's dashboard, which lists the monitored targets.
    case localNetwork
    /// The Devices list with this device selected.
    case device(ipAddress: String)

    /// The route for a delivered alert, from its category and payload. Nil for an alert with
    /// nowhere to go.
    @MainActor
    static func route(category: String, userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        switch category {
        case NotificationService.targetDownCategory, NotificationService.targetRecoveredCategory,
             NotificationService.highLatencyCategory:
            return .localNetwork
        case NotificationService.newDeviceCategory, NotificationService.ruleMatchCategory:
            guard let ip = userInfo["ipAddress"] as? String, !ip.isEmpty else { return .localNetwork }
            return .device(ipAddress: ip)
        default:
            return nil
        }
    }
}

/// Hands a route from the notification delegate to the window (#478). The window clears
/// `pending` once it has navigated.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var pending: NotificationRoute?
    /// The saved device Devices should select, set when the window opens Devices for a route.
    var deviceToSelect: UUID?

    /// Where `route` lands, given the saved devices: a device route whose device isn't saved
    /// falls back to the local network's dashboard (a rule can match a monitored target).
    static func selection(for route: NotificationRoute, devices: [LocalDevice], localNetworkID: UUID?)
        -> (section: SidebarSelection?, device: UUID?) {
        switch route {
        case .localNetwork:
            return (localNetworkID.map { .network($0) }, nil)
        case let .device(ip):
            guard let device = devices.first(where: { $0.ipAddress == ip }) else {
                return (localNetworkID.map { .network($0) }, nil)
            }
            return (.section(.devices), device.id)
        }
    }
}
