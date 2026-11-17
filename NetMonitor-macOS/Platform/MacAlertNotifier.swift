import Foundation
import NetMonitorCore

/// Sends the Mac's target-down and new-device alerts (#403).
///
/// `NotificationService` applies each alert's own toggle; this adds the Mac's
/// "Enable notifications" master switch, which turns every alert off.
@MainActor
final class MacAlertNotifier {
    static let notificationsEnabledKey = "netmonitor.notifications.enabled"
    /// The key the target-down toggle wrote before #403. Nothing read it, but a user who
    /// turned it off meant it.
    static let legacyTargetDownKey = "netmonitor.notifications.targetDown"

    /// Copies the old target-down toggle onto the service's key once, if the new key has no
    /// stored value yet. Safe to call on every launch.
    static func migrateLegacyToggles(in defaults: UserDefaults = .standard) {
        let newKey = NotificationService.targetDownAlertKey
        guard defaults.object(forKey: newKey) == nil,
              let legacy = defaults.object(forKey: legacyTargetDownKey) as? Bool
        else { return }
        defaults.set(legacy, forKey: newKey)
    }

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
