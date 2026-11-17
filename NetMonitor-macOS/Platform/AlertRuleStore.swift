import Foundation
import NetMonitorCore
import os

/// The user's alert rules, saved in UserDefaults (#394).
@MainActor
@Observable
final class AlertRuleStore {
    static let storageKey = "netmonitor.alertRules"

    private(set) var rules: [AlertRule] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = Self.load(from: defaults)
    }

    func add(_ rule: AlertRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: AlertRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func delete(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    /// Re-reads the saved rules, so a change made in the Settings window reaches the app.
    func reload() {
        rules = Self.load(from: defaults)
    }

    private func save() {
        do {
            try defaults.set(JSONEncoder().encode(rules), forKey: Self.storageKey)
        } catch {
            Logger.app.error("Failed to save alert rules: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [AlertRule] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AlertRule].self, from: data)) ?? []
    }
}

/// Checks alert rules against device changes and monitoring results while the app runs, and
/// posts a notification for each match (#394). There's no background daemon.
@MainActor
final class MacRuleAlerts {
    private let store: AlertRuleStore
    private let service: NotificationService
    private let defaults: UserDefaults
    private var evaluator = AlertRuleEvaluator()

    init(store: AlertRuleStore, service: NotificationService, defaults: UserDefaults = .standard) {
        self.store = store
        self.service = service
        self.defaults = defaults
    }

    /// From a completed scan (#393). `devices` are the network's rows, used for each device's
    /// type and maker.
    func handle(deviceChanges: [DeviceChangeEvent], devices: [LocalDevice], networkID: UUID?) {
        let events = deviceChanges.compactMap { change -> AlertRuleEvent? in
            switch change {
            case let .firstSeen(observation):
                AlertRuleEvent(kind: .firstSeen, subject: subject(observation.ipAddress, observation.macAddress, observation.name, devices, networkID))
            case let .cameOnline(observation):
                AlertRuleEvent(kind: .cameOnline, subject: subject(observation.ipAddress, observation.macAddress, observation.name, devices, networkID))
            case let .wentOffline(known):
                AlertRuleEvent(kind: .wentOffline, subject: subject(known.ipAddress, known.macAddress, known.name, devices, networkID))
            case .changed:
                nil
            }
        }
        fire(events)
    }

    /// From one monitored-target check.
    func handle(targetResult result: TargetCheckOutcome) {
        let subject = AlertRuleSubject(name: result.name, ipAddress: result.host)
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
                identifier: "\(match.rule.id)-\(match.event.subject.key)"
            )
        }
    }

    private func subject(
        _ ip: String, _ mac: String?, _ name: String?, _ devices: [LocalDevice], _ networkID: UUID?
    ) -> AlertRuleSubject {
        let row = devices.first { row in
            if let mac, !mac.isEmpty, row.macAddress.caseInsensitiveCompare(mac) == .orderedSame {
                return true
            }
            return row.ipAddress == ip
        }
        return AlertRuleSubject(
            name: row?.displayName ?? name,
            ipAddress: ip,
            macAddress: mac,
            deviceType: row?.deviceType,
            maker: row?.manufacturer ?? row?.vendor,
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
