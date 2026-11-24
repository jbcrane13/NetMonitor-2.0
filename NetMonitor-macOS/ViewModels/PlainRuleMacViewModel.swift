import Foundation
import NetMonitorCore
import os
import SwiftData

/// The Rules tab's "Describe a rule…" field (#450). The composer reads the text and drafts a
/// rule; nothing is saved until `confirm`.
@MainActor
@Observable
final class PlainRuleMacViewModel {
    var text = ""
    /// The alert draft under review, as the user edits it.
    var draft: AlertRuleDraft?
    /// Also add a monitoring target for the draft's device.
    var addsTarget = false
    /// Start monitoring (every enabled target) on Confirm, offered while it is stopped.
    var startsMonitoring = true
    /// Set by the port-scan draft's button: the Port Scanner to open, prefilled.
    var openPortScan: PortScanRequest?
    let composer: PlainRuleComposer
    let timing: RuleTiming
    /// The targets as submitted. Monitoring skips a turned-off one, so the draft offers to turn
    /// it back on.
    private var targets: [NetworkTarget] = []
    /// The device each linked target checks, by target ID.
    private var targetLinks: [UUID: UUID] = [:]
    /// How often each host's target is checked: its enabled target, or else the turned-off one.
    private var targetIntervals: [String: TimeInterval] = [:]

    init(parser: any RuleIntentParsing = UITestPlainRules.parser, timing: RuleTiming = RuleTiming(targetCheckInterval: TargetDefaults.interval())) {
        composer = PlainRuleComposer(parser: parser, platform: .mac)
        self.timing = timing
    }

    var isAvailable: Bool { composer.isAvailable }

    /// The notes for the draft as edited.
    var notes: [String] {
        guard let draft else { return [] }
        var timing = timing
        if let host = draft.device?.ipAddress, let interval = targetIntervals[host] {
            timing.targetCheckInterval = interval
        }
        return draft.notes(addingTarget: addsTarget, timing: timing)
    }

    /// The draft's device has a turned-off target, which `confirm` turns back on instead of adding another.
    var reusesDisabledTarget: Bool {
        draft?.device.flatMap(disabledTarget) != nil
    }

    /// Whether `target` checks `device`: a linked target checks the device it is linked to,
    /// whatever its address; an unlinked one checks whichever device has its address.
    private func checks(_ target: NetworkTarget, _ device: RuleDevice) -> Bool {
        Self.checks(target, deviceID: device.id, address: device.ipAddress, linkedDevice: targetLinks[target.id])
    }

    static func checks(_ target: NetworkTarget, deviceID: UUID, address: String?, linkedDevice: UUID?) -> Bool {
        linkedDevice.map { $0 == deviceID } ?? (target.host == address)
    }

    /// Whether an enabled target checks the device, by the same rule as the draft: the rule
    /// editor's warning uses it too.
    static func isMonitored(
        deviceID: UUID, address: String?, targets: [NetworkTarget], linkedDevice: (UUID) -> UUID?
    ) -> Bool {
        targets.contains { $0.isEnabled && checks($0, deviceID: deviceID, address: address, linkedDevice: linkedDevice($0.id)) }
    }

    private func disabledTarget(for device: RuleDevice) -> NetworkTarget? {
        targets.first { !$0.isEnabled && checks($0, device) }
    }

    /// - Parameter linkedDevice: the device a rule linked a target to (`AlertRuleStore.device(forTarget:)`).
    func submit(
        devices: [LocalDevice], targets: [NetworkTarget], isScanning: Bool, linkedDevice: (UUID) -> UUID? = { _ in nil }
    ) async {
        draft = nil
        self.targets = targets
        targetLinks = Dictionary(uniqueKeysWithValues: targets.compactMap { target in linkedDevice(target.id).map { (target.id, $0) } })
        // Monitoring checks enabled targets only; a turned-off one doesn't make the device monitored.
        let enabled = targets.filter(\.isEnabled)
        targetIntervals = Dictionary(targets.filter { !$0.isEnabled }.map { ($0.host, $0.checkInterval) }) { first, _ in first }
            .merging(Dictionary(enabled.map { ($0.host, $0.checkInterval) }, uniquingKeysWith: min)) { _, enabled in enabled }
        let candidates = devices.map(RuleDevice.init)
        // The addresses of devices an enabled target checks: a linked target counts only for its
        // own device, an unlinked one for the device at its address.
        let monitored = candidates.filter { device in enabled.contains { checks($0, device) } }
        await composer.submit(
            text,
            devices: candidates,
            timing: timing,
            targetHosts: Set(monitored.map(\.ipAddress)),
            isScanning: isScanning
        )
        adoptOutcome()
    }

    func choose(_ device: RuleDevice) {
        composer.choose(device)
        adoptOutcome()
    }

    /// Whether the draft relies on a monitoring target: it adds one, or its device has one.
    var usesTarget: Bool {
        guard let draft else { return false }
        return (addsTarget && draft.offersTarget) || draft.hasTarget
    }

    /// Saves the reviewed draft, and the monitoring target when asked, then clears the field.
    /// With `startMonitoring`, monitoring starts after everything is saved, so it checks the new
    /// target with the others.
    func confirm(store: AlertRuleStore, context: ModelContext, session: MonitoringSession?, startMonitoring: Bool = false) {
        guard let draft else { return }
        var rule = draft.rule
        rule.name = rule.name.trimmingCharacters(in: .whitespaces)
        guard !rule.name.isEmpty else { return }
        store.add(rule)
        if addsTarget, draft.offersTarget, let device = draft.device {
            let target: NetworkTarget
            if let existing = disabledTarget(for: device), existing.modelContext != nil {
                existing.isEnabled = true
                target = existing
            } else {
                target = NetworkTarget(
                    name: device.displayName,
                    host: device.ipAddress,
                    targetProtocol: .icmp,
                    checkInterval: timing.targetCheckInterval,
                    timeout: TargetDefaults.timeout()
                )
                context.insert(target)
            }
            do {
                try context.save()
                // The target checks this device even if its address changes (#450 review).
                store.link(target: target.id, to: device.id)
                session?.monitorAddedTarget(target)
            } catch {
                Logger.data.error("Failed to save the rule's monitoring target: \(error, privacy: .public)")
            }
        }
        if startMonitoring, let session, !session.isMonitoring {
            session.startMonitoring()
        }
        cancel()
    }

    func cancel() {
        text = ""
        draft = nil
        addsTarget = false
        startsMonitoring = true
        targets = []
        targetLinks = [:]
        targetIntervals = [:]
        composer.clear()
    }

    private func adoptOutcome() {
        if case var .alert(alert) = composer.outcome {
            // The composer matched targets by address; a linked target counts only for its own device.
            if let device = alert.device {
                alert.hasTarget = targets.contains { $0.isEnabled && checks($0, device) }
            }
            draft = alert
            addsTarget = alert.offersTarget
        } else {
            draft = nil
            addsTarget = false
        }
    }
}
