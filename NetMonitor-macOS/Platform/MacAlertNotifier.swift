import Foundation
import NetMonitorCore

/// Sends the Mac's target-down and new-device alerts (#403).
///
/// `NotificationService` applies each alert's own toggle; this adds the Mac's
/// "Enable notifications" master switch, which turns every alert off.
@MainActor
final class MacAlertNotifier {
    static let notificationsEnabledKey = "netmonitor.notifications.enabled"

    private let service: NotificationService
    private let defaults: UserDefaults

    init(service: NotificationService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
    }

    func targetWentDown(name: String, host: String) {
        guard isEnabled else { return }
        service.notifyTargetDown(name: name, host: host)
    }

    func devicesJoined(_ devices: [LocalDevice]) {
        guard isEnabled else { return }
        for device in devices {
            service.notifyNewDevice(ipAddress: device.ipAddress, hostname: device.hostname)
        }
    }
}
