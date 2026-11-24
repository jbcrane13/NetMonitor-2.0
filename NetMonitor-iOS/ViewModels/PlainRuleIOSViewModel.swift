import Foundation
import NetMonitorCore
import os
import SwiftData

/// Settings › Monitoring's "Describe a rule…" field (#450). iOS has no alert-rule engine:
/// offline and latency requests become a monitoring-target draft, a port scan opens the Port
/// Scanner prefilled, and other alerts point to the Mac app. Nothing is saved until `confirm`.
@MainActor
@Observable
final class PlainRuleIOSViewModel {
    var text = ""
    let composer: PlainRuleComposer

    struct PortScanRequest: Identifiable, Equatable {
        let host: String
        let preset: PortScanPreset
        var id: String { "\(host)|\(preset.rawValue)" }
    }

    init(parser: any RuleIntentParsing = UITestBootstrap.ruleParser ?? RuleIntentParser.shared) {
        composer = PlainRuleComposer(parser: parser, platform: .iOS)
    }

    var isAvailable: Bool { composer.isAvailable }

    /// - Parameter networkID: the network the phone is on. Only its saved devices can be named: a
    ///   device saved on another network has an address that means something else here. Nil when
    ///   the network isn't known, which leaves every saved device in.
    func submit(devices: [LocalDevice], targets: [MonitoringTarget], networkID: UUID?, isScanning: Bool) async {
        let devices = networkID.map { id in devices.filter { $0.networkProfileID == id } } ?? devices
        await composer.submit(
            text,
            devices: devices.map(RuleDevice.init),
            // iOS targets are checked in background refresh; the notes don't quote an interval.
            timing: RuleTiming(targetCheckInterval: 60),
            targetHosts: Set(targets.map(\.host)),
            isScanning: isScanning
        )
    }

    func choose(_ device: RuleDevice) {
        composer.choose(device)
    }

    /// Saves the reviewed monitoring-target draft, then clears the field.
    func confirm(context: ModelContext) {
        guard case let .target(draft) = composer.outcome else { return }
        context.insert(MonitoringTarget(name: draft.name, host: draft.host))
        do {
            try context.save()
        } catch {
            Logger.data.error("Failed to save the described monitoring target: \(error.localizedDescription, privacy: .public)")
        }
        cancel()
    }

    /// The Port Scanner to open for the port-scan draft, and clears the field. Nothing is saved.
    func takePortScan() -> PortScanRequest? {
        guard case let .portScan(device, preset) = composer.outcome else { return nil }
        cancel()
        return PortScanRequest(host: device.ipAddress, preset: preset)
    }

    func cancel() {
        text = ""
        composer.clear()
    }
}
