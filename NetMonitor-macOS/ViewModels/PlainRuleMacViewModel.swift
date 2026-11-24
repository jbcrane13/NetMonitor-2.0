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
    /// Set by the port-scan draft's button: the Port Scanner to open, prefilled.
    var openPortScan: PortScanRequest?
    let composer: PlainRuleComposer
    let timing: RuleTiming
    /// Each host's turned-off target. Monitoring skips it, so the draft offers to turn it back on.
    private var disabledTargets: [String: NetworkTarget] = [:]
    /// How often each host's target is checked: its enabled target, or else the turned-off one.
    private var targetIntervals: [String: TimeInterval] = [:]

    struct PortScanRequest: Identifiable, Equatable {
        let host: String
        let preset: PortScanPreset
        var id: String { "\(host)|\(preset.rawValue)" }
    }

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
        draft?.device.flatMap { disabledTargets[$0.ipAddress] } != nil
    }

    func submit(devices: [LocalDevice], targets: [NetworkTarget], isScanning: Bool) async {
        draft = nil
        // Monitoring checks enabled targets only; a turned-off one doesn't make the device monitored.
        let enabled = targets.filter(\.isEnabled)
        disabledTargets = Dictionary(targets.filter { !$0.isEnabled }.map { ($0.host, $0) }) { first, _ in first }
        targetIntervals = disabledTargets.mapValues(\.checkInterval)
            .merging(Dictionary(enabled.map { ($0.host, $0.checkInterval) }, uniquingKeysWith: min)) { _, enabled in enabled }
        await composer.submit(
            text,
            devices: devices.map(RuleDevice.init),
            timing: timing,
            targetHosts: Set(enabled.map(\.host)),
            isScanning: isScanning
        )
        adoptOutcome()
    }

    func choose(_ device: RuleDevice) {
        composer.choose(device)
        adoptOutcome()
    }

    /// Saves the reviewed draft, and the monitoring target when asked, then clears the field.
    func confirm(store: AlertRuleStore, context: ModelContext, session: MonitoringSession?) {
        guard let draft else { return }
        var rule = draft.rule
        rule.name = rule.name.trimmingCharacters(in: .whitespaces)
        guard !rule.name.isEmpty else { return }
        store.add(rule)
        if addsTarget, draft.offersTarget, let device = draft.device {
            let target: NetworkTarget
            if let existing = disabledTargets[device.ipAddress], existing.modelContext != nil {
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
                session?.monitorAddedTarget(target)
            } catch {
                Logger.data.error("Failed to save the rule's monitoring target: \(error, privacy: .public)")
            }
        }
        cancel()
    }

    func cancel() {
        text = ""
        draft = nil
        addsTarget = false
        disabledTargets = [:]
        targetIntervals = [:]
        composer.clear()
    }

    private func adoptOutcome() {
        if case let .alert(alert) = composer.outcome {
            draft = alert
            addsTarget = alert.offersTarget
        } else {
            draft = nil
            addsTarget = false
        }
    }
}
