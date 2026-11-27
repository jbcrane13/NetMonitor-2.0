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
    /// Why Confirm didn't save, such as an edited address with no open port.
    private(set) var confirmProblem: String?
    /// True while the app checks a device for an open port to probe (#578 review).
    private(set) var isCheckingPorts = false
    /// Set when a target draft was refused: no port answered the check.
    private(set) var refusal: String?
    /// Checks a device for an open port when no scan found one.
    private let probe: MonitoringTargetProbe
    /// The ports that check tries, in order.
    private let checkedPorts: [Int]
    /// Goes up with every request, so a port check that finishes after a newer one is dropped.
    private var generation = 0
    private let parser: any RuleIntentParsing

    init(
        parser: any RuleIntentParsing = UITestBootstrap.ruleParser ?? PhoneModel.ruleParser,
        probe: MonitoringTargetProbe = UITestBootstrap.ruleProbe ?? BackgroundTaskService.liveProbe,
        checkedPorts: [Int] = DeviceTypeInferenceService.fingerprintPorts
    ) {
        composer = PlainRuleComposer(parser: parser, platform: .iOS)
        self.parser = parser
        self.probe = probe
        self.checkedPorts = checkedPorts
    }

    /// What to show under the field: a refusal, else the composer's outcome.
    var displayedOutcome: PlainRuleOutcome? {
        refusal.map(PlainRuleOutcome.message) ?? composer.outcome
    }

    var isAvailable: Bool { composer.isAvailable }

    /// Whether the user must first agree to let the Mac read what they type (#586). Read live:
    /// the local model or a Mac can come and go.
    var needsMacConsent: Bool { parser.availability == .needsConsent }

    /// The answer the prompt records.
    var macConsent: MacInsightConsent? { parser.macConsent }

    /// - Parameters:
    ///   - devices: the saved rows, complete groups (`DeviceGroups.recentDevices`): a group of
    ///     interfaces is one candidate, named by its primary's ID (#594).
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
        var candidates = DeviceGroups.project(devices).map { projection in
            var device = RuleDevice(projection)
            // The last scan's open ports win over ports a row saved earlier (#572). Only ports
            // measured at the candidate's address (the current member's) count: another
            // interface's ports say nothing about this one, so with none the port probe runs (#594).
            if let ports = matched.byRow[projection.current.id]?.openPorts, !ports.isEmpty {
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
        await adoptOutcome()
    }

    func choose(_ device: RuleDevice) async {
        composer.choose(device)
        await adoptOutcome()
    }

    /// Whether the edited draft can be saved: it has a name and an address.
    var canConfirmTarget: Bool {
        guard let targetDraft else { return false }
        return !trimmed(targetDraft.name).isEmpty && !trimmed(targetDraft.host).isEmpty
    }

    /// Saves the reviewed monitoring-target draft, then clears the field. The draft's port is
    /// open on the draft's address. An edited address gets a port a scan found open on it, else
    /// one a quick check finds open now; with neither, nothing is saved and `confirmProblem`
    /// says why (#578 review). No check runs during a scan.
    func confirm(context: ModelContext, isScanning: Bool = false) async {
        guard canConfirmTarget, !isCheckingPorts, let draft = targetDraft else { return }
        let host = trimmed(draft.host)
        var port = draft.port
        if host.caseInsensitiveCompare(draftHost ?? "") != .orderedSame {
            port = PlainRuleBuilder.probePort(knownPorts[host.lowercased()] ?? [])
            if port == nil {
                guard !isScanning else {
                    confirmProblem = "Wait for the scan to finish, then try again."
                    return
                }
                let request = generation
                port = await checkForOpenPort(on: host)
                guard request == generation else { return }
            }
        }
        guard let port else {
            confirmProblem = PlainRuleBuilder.cantCheckMessage(host)
            return
        }
        confirmProblem = nil
        // A TCP check of a port found open: one that can succeed in the background (#572).
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
        generation += 1
        isCheckingPorts = false
        refusal = nil
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

    private func adoptOutcome() async {
        generation += 1
        let request = generation
        refusal = nil
        confirmProblem = nil
        guard case var .target(draft) = composer.outcome else {
            targetDraft = nil
            draftHost = nil
            return
        }
        targetDraft = nil
        if draft.port == nil {
            // Discovery on iOS never records open ports, so a device a scan found has none: check
            // a few common ports now. This deliberately extends "a port the last scan found open"
            // (#572) to "a port found open now" (#578 review).
            let found = await checkForOpenPort(on: draft.host)
            guard request == generation else { return }
            guard let found else {
                refusal = PlainRuleBuilder.cantCheckMessage(draft.name)
                scannedOnly = [:]
                return
            }
            draft.port = found
            draft.notes.insert(PlainRuleBuilder.foundNowNote(port: found, name: draft.name), at: min(1, draft.notes.count))
            remember([found], for: [draft.host])
        }
        if let scanned = scannedOnly[draft.deviceID], let row = saveRow(for: scanned, openPort: draft.port) {
            draft.deviceID = row.id
        }
        targetDraft = draft
        draftHost = draft.host
    }

    /// The first common port that accepts a connection on `host` now, shown as "Checking ports…".
    private func checkForOpenPort(on host: String) async -> Int? {
        isCheckingPorts = true
        defer { isCheckingPorts = false }
        return await probe.firstOpenPort(on: host, among: checkedPorts)
    }

    /// Saves the row for a device only the scan knew, as device detail does when it opens, so a
    /// draft names it by a stable ID (#571).
    private func saveRow(for scanned: DiscoveredDevice, openPort: Int?) -> LocalDevice? {
        guard let context else { return nil }
        let row = DeviceDetailViewModel.savedRow(
            ipAddress: scanned.ipAddress, scanned: scanned, networkID: networkID ?? scanned.networkProfileID, scan: scan, in: context
        )
        DeviceDetailViewModel.adopt(scanned, into: row)
        if let ports = scanned.openPorts, !ports.isEmpty {
            row.openPorts = ports
        } else if let openPort, row.openPorts?.isEmpty ?? true {
            // The port the draft found open just now.
            row.openPorts = [openPort]
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
