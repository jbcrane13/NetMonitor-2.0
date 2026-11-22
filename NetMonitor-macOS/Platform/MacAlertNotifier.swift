import Foundation
import NetMonitorCore

/// Sends the Mac's target-down, target-recovered, high-latency and new-device alerts
/// (#403, #445).
///
/// `NotificationService` applies each alert's own toggle; this adds the Mac's
/// "Enable notifications" master switch, which turns every alert off.
@MainActor
final class MacAlertNotifier {
    static let notificationsEnabledKey = "netmonitor.notifications.enabled"
    /// Settings › Notifications › Latency threshold, in ms (#445).
    static let latencyThresholdKey = "netmonitor.notifications.latencyThreshold"
    static let defaultLatencyThreshold = 500.0
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
    /// Targets whose last reachable check was above the threshold, so a target alerts once
    /// when it crosses, not on every check.
    private var aboveThreshold: Set<UUID> = []

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

    /// Recovery and high-latency alerts from each recorded check (#445).
    func targetChecked(_ outcome: TargetCheckOutcome) {
        let threshold = defaults.object(forKey: Self.latencyThresholdKey) as? Double ?? Self.defaultLatencyThreshold
        let isAbove = outcome.isReachable && (outcome.latency ?? 0) > threshold
        let crossed = isAbove && !aboveThreshold.contains(outcome.targetID)
        if isAbove {
            aboveThreshold.insert(outcome.targetID)
        } else {
            aboveThreshold.remove(outcome.targetID)
        }
        guard isEnabled else { return }
        if outcome.cameUp {
            service.notifyTargetRecovered(name: outcome.name, host: outcome.host)
        }
        if crossed, let latency = outcome.latency {
            service.notifyTargetLatency(name: outcome.name, host: outcome.host, latency: latency, thresholdMs: Int(threshold))
        }
    }

    /// Sends a new-device alert for each device answering for the first time (#393). The
    /// first scan of a network and devices only ever cached never count.
    func devicesChanged(_ events: [DeviceChangeEvent], networkID: UUID? = nil) {
        guard isEnabled else { return }
        for case let .firstSeen(device) in events {
            service.notifyNewDevice(ipAddress: device.ipAddress, hostname: device.name, networkID: networkID)
        }
    }
}
