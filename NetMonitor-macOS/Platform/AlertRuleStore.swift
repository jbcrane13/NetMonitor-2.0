import Foundation
import NetMonitorCore
import os

/// The user's alert rules, saved in UserDefaults (#394).
///
/// One instance is shared app-wide through the environment. Each change is also applied to
/// freshly loaded state, so a second window or instance can't save a stale list over it.
/// Stored data that can't be decoded is copied aside once before anything is saved over it,
/// the last good rules are kept in memory, and `loadError` explains the problem.
@MainActor
@Observable
final class AlertRuleStore {
    static let storageKey = "netmonitor.alertRules"
    /// Where unreadable stored rules are kept, so a save can't destroy them.
    static let unreadableKey = "netmonitor.alertRules.unreadable"

    private(set) var rules: [AlertRule] = []
    /// Set when the stored rules couldn't be read. Shown in the Rules tab.
    private(set) var loadError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func add(_ rule: AlertRule) {
        mutate { $0.append(rule) }
    }

    func update(_ rule: AlertRule) {
        mutate { rules in
            guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
            rules[index] = rule
        }
    }

    func delete(id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    /// Re-reads the saved rules. On unreadable data, keeps the last good rules.
    func reload() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            rules = []
            return
        }
        do {
            rules = try JSONDecoder().decode([AlertRule].self, from: data)
            loadError = nil
        } catch {
            setAside(data, error: error)
        }
    }

    private func mutate(_ change: (inout [AlertRule]) -> Void) {
        reload()
        var updated = rules
        change(&updated)
        rules = updated
        save()
    }

    private func save() {
        do {
            try defaults.set(JSONEncoder().encode(rules), forKey: Self.storageKey)
        } catch {
            Logger.app.error("Failed to save alert rules: \(error, privacy: .public)")
        }
    }

    private func setAside(_ data: Data, error: Error) {
        if defaults.data(forKey: Self.unreadableKey) == nil {
            defaults.set(data, forKey: Self.unreadableKey)
        }
        loadError = "Saved rules couldn't be read. They were kept aside; rules shown here are the last ones that loaded."
        Logger.app.error("Alert rules unreadable, set aside: \(error, privacy: .public)")
    }
}

/// Checks alert rules against device changes and monitoring results while the app runs, and
/// posts a notification for each match (#394). There's no background daemon.
@MainActor
final class MacRuleAlerts {
    private let store: AlertRuleStore
    private let service: NotificationService
    private let defaults: UserDefaults
    /// The current network's device rows and ID, used to fill in a monitored target's
    /// MAC, type, maker and network from its host.
    private let currentDevices: @MainActor () -> (devices: [LocalDevice], networkID: UUID?)
    private var evaluator = AlertRuleEvaluator()

    init(
        store: AlertRuleStore,
        service: NotificationService,
        defaults: UserDefaults = .standard,
        currentDevices: @escaping @MainActor () -> (devices: [LocalDevice], networkID: UUID?) = { ([], nil) }
    ) {
        self.store = store
        self.service = service
        self.defaults = defaults
        self.currentDevices = currentDevices
    }

    /// From a completed scan (#393). `devices` are the network's rows, used for each device's
    /// type and maker.
    func handle(deviceChanges: [DeviceChangeEvent], devices: [LocalDevice], networkID: UUID?) {
        let events = deviceChanges.compactMap { change -> AlertRuleEvent? in
            switch change {
            case let .firstSeen(seen):
                event(.firstSeen, seen.ipAddress, seen.macAddress, seen.name, devices, networkID)
            case let .cameOnline(seen):
                event(.cameOnline, seen.ipAddress, seen.macAddress, seen.name, devices, networkID)
            case let .wentOffline(known):
                event(.wentOffline, known.ipAddress, known.macAddress, known.name, devices, networkID)
            case .changed:
                nil
            }
        }
        fire(events)
    }

    /// From one monitored-target check. The target's host is looked up in the current
    /// network's devices so device conditions can match it.
    func handle(targetResult result: TargetCheckOutcome) {
        let (devices, networkID) = currentDevices()
        let row = devices.first {
            $0.ipAddress == result.host
                || ($0.hostname?.caseInsensitiveCompare(result.host) == .orderedSame)
        }
        let subject = AlertRuleSubject(
            name: result.name,
            ipAddress: result.host,
            macAddress: row.flatMap { $0.macAddress.isEmpty ? nil : $0.macAddress },
            deviceType: row?.deviceType,
            maker: row?.makerExcludingSuggestions,
            networkID: row == nil ? nil : networkID,
            stateKey: "target:\(result.targetID.uuidString)"
        )
        var events: [AlertRuleEvent] = []
        if result.wentDown {
            events.append(AlertRuleEvent(kind: .wentOffline, subject: subject))
        }
        if result.cameUp {
            events.append(AlertRuleEvent(kind: .cameOnline, subject: subject))
        }
        if let latency = result.latency {
            events.append(AlertRuleEvent(kind: .latency(milliseconds: latency), subject: subject))
        }
        fire(events)
    }

    private func fire(_ events: [AlertRuleEvent]) {
        guard !events.isEmpty else { return }
        store.reload()
        let matches = evaluator.evaluate(events, rules: store.rules)
        // The Mac's "Enable notifications" master switch silences rules too.
        guard defaults.object(forKey: MacAlertNotifier.notificationsEnabledKey) as? Bool ?? true else { return }
        for match in matches {
            service.notifyRuleMatched(
                ruleName: match.rule.name,
                detail: Self.detail(for: match.event),
                identifier: "\(match.rule.id)-\(match.event.subject.key)",
                ipAddress: match.event.subject.ipAddress,
                networkID: match.event.subject.networkID
            )
        }
    }

    private func event(
        _ kind: AlertRuleEvent.Kind, _ ip: String, _ mac: String?, _ name: String?, _ devices: [LocalDevice], _ networkID: UUID?
    ) -> AlertRuleEvent {
        AlertRuleEvent(kind: kind, subject: subject(ip, mac, name, devices, networkID))
    }

    private func subject(
        _ ip: String, _ mac: String?, _ name: String?, _ devices: [LocalDevice], _ networkID: UUID?
    ) -> AlertRuleSubject {
        // A MAC identifies the row exactly; the IP is only a fallback for an event without one.
        let row: LocalDevice? = if let mac, !mac.isEmpty {
            devices.first { $0.macAddress.caseInsensitiveCompare(mac) == .orderedSame }
        } else {
            devices.first { $0.ipAddress == ip }
        }
        return AlertRuleSubject(
            name: row?.displayName ?? name,
            ipAddress: ip,
            macAddress: mac,
            deviceType: row?.deviceType,
            maker: row?.makerExcludingSuggestions,
            networkID: networkID
        )
    }

    static func detail(for event: AlertRuleEvent) -> String {
        let name = event.subject.displayName
        switch event.kind {
        case .cameOnline: return "\(name) came online"
        case .wentOffline: return "\(name) went offline"
        case .firstSeen: return "\(name) joined the network for the first time"
        case let .latency(milliseconds): return String(format: "%@ latency is %.0f ms", name, milliseconds)
        }
    }
}
