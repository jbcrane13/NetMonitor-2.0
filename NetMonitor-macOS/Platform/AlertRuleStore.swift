import Foundation
import NetMonitorCore
import os
import SwiftData

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
    /// Which device each monitoring target added by a described rule checks (#450). A target
    /// stores only an address, which the device can leave or another device can take.
    static let targetDevicesKey = "netmonitor.alertRules.targetDevices"

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
        // A link exists for a rule's device; with no rule left on it, the target stops following it.
        let named = Set(rules.compactMap(\.conditions.deviceID))
        setLinks(targetDevices().filter { UUID(uuidString: $0.value).map(named.contains) ?? false })
    }

    /// The device (`LocalDevice.id`) monitoring target `target` checks, when a rule linked them.
    func device(forTarget target: UUID) -> UUID? {
        targetDevices()[target.uuidString].flatMap(UUID.init(uuidString:))
    }

    func link(target: UUID, to device: UUID) {
        var links = targetDevices()
        links[target.uuidString] = device.uuidString
        setLinks(links)
    }

    /// Forgets the links of deleted targets.
    func unlink(targets: some Sequence<UUID>) {
        var links = targetDevices()
        for target in targets {
            links[target.uuidString] = nil
        }
        setLinks(links)
    }

    func unlinkAllTargets() {
        defaults.removeObject(forKey: Self.targetDevicesKey)
    }

    /// Keeps only links whose target and device still exist and whose device a rule still names,
    /// so the links can't go stale against SwiftData. Run at launch.
    func pruneLinks(targets: Set<UUID>, devices: Set<UUID>) {
        let named = Set(rules.compactMap(\.conditions.deviceID))
        setLinks(targetDevices().filter { target, device in
            guard let target = UUID(uuidString: target), let device = UUID(uuidString: device) else { return false }
            return targets.contains(target) && devices.contains(device) && named.contains(device)
        })
    }

    /// `pruneLinks` against the saved targets and devices in `context`.
    func pruneLinks(in context: ModelContext) {
        guard !targetDevices().isEmpty,
              let targets = try? context.fetch(FetchDescriptor<NetworkTarget>()),
              let devices = try? context.fetch(FetchDescriptor<LocalDevice>())
        else { return }
        pruneLinks(targets: Set(targets.map(\.id)), devices: Set(devices.map(\.id)))
    }

    private func targetDevices() -> [String: String] {
        defaults.dictionary(forKey: Self.targetDevicesKey) as? [String: String] ?? [:]
    }

    private func setLinks(_ links: [String: String]) {
        if links.isEmpty {
            defaults.removeObject(forKey: Self.targetDevicesKey)
        } else {
            defaults.set(links, forKey: Self.targetDevicesKey)
        }
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
    /// What the rows' saved statuses mean now (#583): an old status is no evidence of who holds an
    /// address. Without a coordinator there is no scan, so no saved status counts.
    private let presence: @MainActor () -> PresenceSnapshot
    private var evaluator = AlertRuleEvaluator()
    /// The monitoring targets being checked now. Results of others are ignored, and the rules
    /// forget them, so a deleted, turned-off or stopped target doesn't silence scans (#574 review).
    var activeTargets: (@MainActor () -> Set<UUID>)?

    init(
        store: AlertRuleStore,
        service: NotificationService,
        defaults: UserDefaults = .standard,
        currentDevices: @escaping @MainActor () -> (devices: [LocalDevice], networkID: UUID?) = { ([], nil) },
        presence: @escaping @MainActor () -> PresenceSnapshot = { PresenceSnapshot(lastScans: [:], now: Date()) }
    ) {
        self.store = store
        self.service = service
        self.defaults = defaults
        self.presence = presence
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
                // Reported after the grace period: the device has been down since it last answered.
                event(.wentOffline, known.ipAddress, known.macAddress, known.name, devices, networkID, offlineSince: known.lastSeen)
            case .changed:
                nil
            }
        }
        fire(events)
    }

    /// The address a linked target's device answers at now, when that isn't `host`. A check of
    /// `host` was then of an address that may be another device's: the session drops it and
    /// moves the target there.
    func movedHost(forTarget targetID: UUID, checkedAt host: String) -> String? {
        guard let linked = store.device(forTarget: targetID),
              let row = currentDevices().devices.first(where: { $0.id == linked }), row.ipAddress != host
        else { return nil }
        return row.ipAddress
    }

    /// From one monitored-target check. A target a rule linked to a device is that device while
    /// the current network shows it at the checked address; any other target's host is looked
    /// up in the current network's devices so device conditions can match it.
    func handle(targetResult result: TargetCheckOutcome) {
        if let activeTargets, !activeTargets().contains(result.targetID) {
            return
        }
        guard movedHost(forTarget: result.targetID, checkedAt: result.host) == nil else { return }
        let (devices, networkID) = currentDevices()
        var linked = store.device(forTarget: result.targetID)
        let row: LocalDevice?
        if let device = linked {
            // While the device is offline, another device that took its address answers this
            // target. The device is still down, so its outage carries on; the answers aren't its.
            // Only a recent scan says so (#583): on a network not checked recently the saved
            // statuses are old, so the answers count as the device's, as with any target.
            let presence = presence()
            let taken = devices.contains { $0.id != device && $0.ipAddress == result.host && presence.freshness(of: $0) == .online }
            if taken, let offline = devices.first(where: { $0.id == device && presence.freshness(of: $0) == .offline }) {
                fire([AlertRuleEvent(kind: .stillOffline, subject: subject(for: offline, result: result, networkID: networkID))])
                return
            }
            // On another network the device has no row here, so the check isn't known to be its.
            row = devices.first { $0.id == device }
            if row == nil {
                linked = nil
            }
        } else {
            row = devices.first {
                $0.ipAddress == result.host
                    || ($0.hostname?.caseInsensitiveCompare(result.host) == .orderedSame)
            }
        }
        let subject = AlertRuleSubject(
            name: result.name,
            ipAddress: result.host,
            macAddress: row.flatMap { $0.macAddress.isEmpty ? nil : $0.macAddress },
            deviceType: row?.deviceType,
            maker: row?.makerExcludingSuggestions,
            networkID: row == nil ? nil : networkID,
            deviceID: linked ?? row?.id,
            monitoredTargetID: result.targetID
        )
        var events: [AlertRuleEvent] = []
        if result.wentDown {
            events.append(AlertRuleEvent(kind: .wentOffline, subject: subject))
        } else if !result.isReachable {
            // Times rules that wait for an outage to last (#450).
            events.append(AlertRuleEvent(kind: .stillOffline, subject: subject))
        }
        if result.cameUp {
            events.append(AlertRuleEvent(kind: .cameOnline, subject: subject))
        }
        if let latency = result.latency {
            events.append(AlertRuleEvent(kind: .latency(milliseconds: latency), subject: subject))
        }
        fire(events)
    }

    private func subject(for device: LocalDevice, result: TargetCheckOutcome, networkID: UUID?) -> AlertRuleSubject {
        AlertRuleSubject(
            name: device.displayName,
            ipAddress: result.host,
            macAddress: device.macAddress.isEmpty ? nil : device.macAddress,
            deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions,
            networkID: networkID,
            deviceID: device.id,
            monitoredTargetID: result.targetID
        )
    }

    /// Monitoring stopped: targets go unchecked from here, so their duration timers start over
    /// when it resumes. Scan-timed outages keep theirs.
    func monitoringStopped() {
        evaluator.endMonitoredTargetEpisodes()
    }

    private func fire(_ events: [AlertRuleEvent]) {
        guard !events.isEmpty else { return }
        if let activeTargets {
            evaluator.retainTargets(activeTargets())
        }
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
        _ kind: AlertRuleEvent.Kind, _ ip: String, _ mac: String?, _ name: String?, _ devices: [LocalDevice], _ networkID: UUID?,
        offlineSince: Date? = nil
    ) -> AlertRuleEvent {
        AlertRuleEvent(kind: kind, subject: subject(ip, mac, name, devices, networkID), offlineSince: offlineSince)
    }

    private func subject(
        _ ip: String, _ mac: String?, _ name: String?, _ devices: [LocalDevice], _ networkID: UUID?
    ) -> AlertRuleSubject {
        let row = Self.row(ip: ip, mac: mac, in: devices)
        return AlertRuleSubject(
            name: row?.displayName ?? name,
            ipAddress: ip,
            macAddress: mac,
            deviceType: row?.deviceType,
            maker: row?.makerExcludingSuggestions,
            networkID: networkID,
            deviceID: row?.id
        )
    }

    /// The network's row for an event's device, for display. A MAC identifies the row
    /// exactly; the IP is only a fallback for an event without one.
    static func row(ip: String, mac: String?, in devices: [LocalDevice]) -> LocalDevice? {
        if let mac, !mac.isEmpty {
            devices.first { $0.macAddress.caseInsensitiveCompare(mac) == .orderedSame }
        } else {
            devices.first { $0.ipAddress == ip }
        }
    }

    static func detail(for event: AlertRuleEvent) -> String {
        let name = event.subject.displayName
        switch event.kind {
        case .cameOnline: return "\(name) came online"
        case .wentOffline, .stillOffline: return "\(name) went offline"
        case .firstSeen: return "\(name) joined the network for the first time"
        case let .latency(milliseconds): return String(format: "%@ latency is %.0f ms", name, milliseconds)
        }
    }
}
