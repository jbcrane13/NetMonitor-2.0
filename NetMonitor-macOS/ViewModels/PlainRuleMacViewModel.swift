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
        draft?.notes(addingTarget: addsTarget, timing: timing) ?? []
    }

    func submit(devices: [LocalDevice], targets: [NetworkTarget], isScanning: Bool) async {
        draft = nil
        await composer.submit(
            text,
            devices: devices.map(Self.ruleDevice),
            timing: timing,
            targetHosts: Set(targets.map(\.host)),
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
            let target = NetworkTarget(
                name: device.displayName,
                host: device.ipAddress,
                targetProtocol: .icmp,
                checkInterval: timing.targetCheckInterval,
                timeout: TargetDefaults.timeout()
            )
            context.insert(target)
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

    /// A device as rules see it: its stable identity and the identity seam's name, type and maker.
    static func ruleDevice(_ device: LocalDevice) -> RuleDevice {
        RuleDevice(
            id: device.id,
            displayName: device.displayName,
            deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions,
            ipAddress: device.ipAddress
        )
    }
}
