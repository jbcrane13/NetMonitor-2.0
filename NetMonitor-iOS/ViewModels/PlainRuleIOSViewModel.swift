import Foundation
import NetMonitorCore
import NetworkScanKit
import os
import SwiftData

/// Settings › Monitoring's "Describe a rule…" field (#450). iOS has no alert-rule engine:
/// offline and latency requests become a monitoring-target draft, a port scan opens the Port
/// Scanner prefilled, and other alerts point to the Mac app. Nothing is saved until `confirm`.
@MainActor
@Observable
final class PlainRuleIOSViewModel {
    var text = ""
    /// The monitoring-target draft under review, as the user edits its name and address.
    var targetDraft: TargetDraft?
    let composer: PlainRuleComposer
    /// Devices the latest scan saw that no saved row describes, by the stand-in ID their
    /// candidate carries until a draft saves their row (#571).
    private var scannedOnly: [UUID: DiscoveredDevice] = [:]
    /// The latest scan of the network, for matching a new row the way device detail does.
    private var scan: [DiscoveredDevice] = []
    private var networkID: UUID?
    private var context: ModelContext?
    /// Open ports the rows and the scan know, by address and hostname, for an edited address.
    private var knownPorts: [String: [Int]] = [:]
    /// The address the draft was built for; its port was picked for that address.
    private var draftHost: String?
    /// Why Confirm didn't save, such as an edited address with no known open port.
    private(set) var confirmProblem: String?

    init(parser: any RuleIntentParsing = UITestBootstrap.ruleParser ?? RuleIntentParser.shared) {
        composer = PlainRuleComposer(parser: parser, platform: .iOS)
    }

    var isAvailable: Bool { composer.isAvailable }

    /// - Parameters:
    ///   - devices: the saved rows.
    ///   - scan: the latest scan's devices. One with no saved row can be named too (#571); a
    ///     target draft for it saves its row, through device detail's matching, so the rule keeps
    ///     a stable `LocalDevice.id`.
    ///   - networkID: the network the phone is on. Only its devices can be named: a device saved
    ///     on another network has an address that means something else here. Nil when the network
    ///     isn't known, which leaves every device in.
    ///   - context: where a draft saves a scanned device's row.
    func submit(
        devices: [LocalDevice],
        scan: [DiscoveredDevice] = [],
        targets: [MonitoringTarget],
        networkID: UUID?,
        isScanning: Bool,
        context: ModelContext
    ) async {
        let devices = networkID.map { id in devices.filter { $0.networkProfileID == id } } ?? devices
        let scan = networkID.map { id in scan.filter { $0.networkProfileID == id } } ?? scan
        self.scan = scan
        self.networkID = networkID
        self.context = context
        scannedOnly = [:]
        let matched = Self.match(scan, to: devices)
        var candidates = devices.map { row in
            var device = RuleDevice(row)
            // The last scan's open ports win over ports a row saved earlier (#572).
            if let ports = matched.byRow[row.id]?.openPorts, !ports.isEmpty {
                device.openPorts = ports
            }
            return device
        }
        knownPorts = [:]
        for row in devices {
            remember(row.openPorts ?? [], for: [row.ipAddress, row.hostname, row.resolvedHostname])
        }
        for scanned in scan {
            remember(scanned.openPorts ?? [], for: [scanned.ipAddress, scanned.hostname])
        }
        for device in candidates {
            remember(device.openPorts, for: [device.ipAddress])
        }
        for scanned in matched.unmatched {
            let candidate = RuleDevice(scanned: scanned)
            scannedOnly[candidate.id] = scanned
            candidates.append(candidate)
        }
        await composer.submit(
            text,
            devices: candidates,
            // iOS targets are checked in background refresh; the notes don't quote an interval.
            timing: RuleTiming(targetCheckInterval: 60),
            targetHosts: Set(targets.map(\.host)),
            isScanning: isScanning
        )
        adoptOutcome()
    }

    func choose(_ device: RuleDevice) {
        composer.choose(device)
        adoptOutcome()
    }

    /// Whether the edited draft can be saved: it has a name and an address.
    var canConfirmTarget: Bool {
        guard let targetDraft else { return false }
        return !trimmed(targetDraft.name).isEmpty && !trimmed(targetDraft.host).isEmpty
    }

    /// Saves the reviewed monitoring-target draft, then clears the field. The draft's port was
    /// found open on the draft's address; an edited address gets a port a scan found open on it,
    /// or isn't saved and `confirmProblem` says why (#578 review).
    func confirm(context: ModelContext) {
        guard canConfirmTarget, let draft = targetDraft else { return }
        let host = trimmed(draft.host)
        var port = draft.port
        if host.caseInsensitiveCompare(draftHost ?? "") != .orderedSame {
            guard let edited = PlainRuleBuilder.probePort(knownPorts[host.lowercased()] ?? []) else {
                confirmProblem = "No scan has found an open port on \(host), so it can't be checked in the background. "
                    + "Use \(draftHost ?? "the suggested address"), or scan \(host)'s ports first."
                return
            }
            port = edited
        }
        confirmProblem = nil
        // A TCP check of a port a scan found open: one that can succeed in the background (#572).
        context.insert(MonitoringTarget(name: trimmed(draft.name), host: host, port: port, targetProtocol: .tcp))
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
        targetDraft = nil
        draftHost = nil
        confirmProblem = nil
        scannedOnly = [:]
        composer.clear()
    }

    /// Deletes targets from the Monitoring Targets list (a swipe on one row).
    func delete(_ targets: [MonitoringTarget], context: ModelContext) {
        targets.forEach(context.delete)
        do {
            try context.save()
        } catch {
            Logger.data.error("Failed to delete monitoring targets: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func adoptOutcome() {
        if case var .target(draft) = composer.outcome {
            if let scanned = scannedOnly[draft.deviceID], let row = saveRow(for: scanned) {
                draft.deviceID = row.id
            }
            targetDraft = draft
            draftHost = draft.host
        } else {
            targetDraft = nil
            draftHost = nil
        }
        confirmProblem = nil
    }

    /// Saves the row for a device only the scan knew, as device detail does when it opens, so a
    /// draft names it by a stable ID (#571).
    private func saveRow(for scanned: DiscoveredDevice) -> LocalDevice? {
        guard let context else { return nil }
        let row = DeviceDetailViewModel.savedRow(
            ipAddress: scanned.ipAddress, scanned: scanned, networkID: networkID ?? scanned.networkProfileID, scan: scan, in: context
        )
        DeviceDetailViewModel.adopt(scanned, into: row)
        if let ports = scanned.openPorts, !ports.isEmpty {
            row.openPorts = ports
        }
        do {
            try context.save()
        } catch {
            Logger.data.error("Failed to save a described device's row: \(error.localizedDescription, privacy: .public)")
        }
        scannedOnly = scannedOnly.filter { $0.value.id != scanned.id }
        return row
    }

    /// Which saved row each scanned device is, by the device match that `saveRow` saves rows
    /// with: a new device at a saved device's old address has no row, and a device whose private
    /// MAC rotated keeps its row. `byRow` is keyed by the row's ID.
    private static func match(
        _ scan: [DiscoveredDevice], to rows: [LocalDevice]
    ) -> (byRow: [UUID: DiscoveredDevice], unmatched: [DiscoveredDevice]) {
        let observed = scan.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) }
        var matcher = DeviceMatcher(
            known: rows.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) },
            observed: observed
        )
        var byRow: [UUID: DiscoveredDevice] = [:]
        var unmatched: [DiscoveredDevice] = []
        for (scanned, observation) in zip(scan, observed) {
            guard let match = matcher.match(observation) else {
                unmatched.append(scanned)
                continue
            }
            let row = rows[match.index].id
            byRow[row] = byRow[row] ?? scanned
        }
        return (byRow, unmatched)
    }

    private func remember(_ ports: [Int], for names: [String?]) {
        guard !ports.isEmpty else { return }
        for name in names.compactMap({ $0?.lowercased() }) where !name.isEmpty {
            knownPorts[name] = ports
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
