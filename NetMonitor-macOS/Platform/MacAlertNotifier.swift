import Foundation
import NetMonitorCore

/// Sends the Mac's target-down, target-recovered, high-latency and new-device alerts
/// (#403, #445).
///
/// `NotificationService` applies each alert's own toggle; this adds the Mac's
/// "Enable notifications" master switch, which turns every alert off. With a `writer`, alert
/// bodies are worded by the on-device model, or keep their fixed text (#453).
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
    /// Words alert bodies with the on-device model; nil sends every alert with fixed text at once.
    var writer: NotificationTextWriter?

    init(service: NotificationService, defaults: UserDefaults = .standard, writer: NotificationTextWriter? = nil) {
        self.service = service
        self.defaults = defaults
        self.writer = writer
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
    }

    func targetWentDown(name: String, host: String) {
        guard isEnabled, service.isTargetDownAlertEnabled else { return }
        send([.targetDown(name: name, host: host)]) { [service] bodies in
            service.notifyTargetDown(name: name, host: host, generatedBody: bodies[0])
        }
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
        if outcome.cameUp, service.isTargetRecoveryAlertEnabled {
            send([.targetRecovered(name: outcome.name, host: outcome.host)]) { [service] bodies in
                service.notifyTargetRecovered(name: outcome.name, host: outcome.host, generatedBody: bodies[0])
            }
        }
        if crossed, let latency = outcome.latency {
            let event = NotificationEvent.highLatency(name: outcome.name, host: outcome.host, latencyMs: latency, thresholdMs: Int(threshold))
            send([event]) { [service] bodies in
                service.notifyTargetLatency(
                    name: outcome.name, host: outcome.host, latency: latency, thresholdMs: Int(threshold), generatedBody: bodies[0]
                )
            }
        }
    }

    /// Sends a new-device alert for each device answering for the first time (#393). The
    /// first scan of a network and devices only ever cached never count. `devices` are the
    /// network's rows, read only for the name, maker and type the model text states.
    func devicesChanged(_ events: [DeviceChangeEvent], devices: [LocalDevice] = [], networkID: UUID? = nil) {
        guard isEnabled, service.isNewDeviceAlertEnabled else { return }
        let seen = events.compactMap { event -> DeviceObservation? in
            if case let .firstSeen(device) = event {
                return device
            }
            return nil
        }
        let alerts = seen.map { device in
            let row = MacRuleAlerts.row(ip: device.ipAddress, mac: device.macAddress, in: devices)
            return NotificationEvent.newDevice(NotificationDevice(
                name: row?.displayName ?? device.name ?? device.ipAddress,
                ipAddress: device.ipAddress,
                maker: row?.maker,
                deviceType: row?.deviceType
            ))
        }
        send(alerts) { [service] bodies in
            for (device, body) in zip(seen, bodies) {
                service.notifyNewDevice(ipAddress: device.ipAddress, hostname: device.name, networkID: networkID, generatedBody: body)
            }
        }
    }

    /// Posts at once with fixed text, or after the writer has worded the bodies (at most
    /// `NotificationTextWriter.timeout` later).
    private func send(_ events: [NotificationEvent], post: @escaping @MainActor ([String?]) -> Void) {
        guard !events.isEmpty else { return }
        guard let writer else {
            post(Array(repeating: nil, count: events.count))
            return
        }
        Task { await post(writer.bodies(for: events)) }
    }
}
