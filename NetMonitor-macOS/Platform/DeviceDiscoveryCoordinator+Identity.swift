import Foundation
import NetMonitorCore
import NetworkScanKit
import os

/// Network identification on the coordinator (#628 PR B).
extension DeviceDiscoveryCoordinator {
    /// Whether a detail probe that started with `token` may save to its row: still current, and its
    /// network not held by identification (#628 PR B).
    func mayWrite(_ token: JoinToken) -> Bool {
        guard isCurrent(token) else { return false }
        guard let identity, let network = token.networkID else { return true }
        if identity.heldNetworkIDs.contains(network) {
            return false
        }
        return network != networkProfileManager.localProfile?.id || identity.authorizes(network)
    }

    /// The network's last scan as its rows are presented: none while identification holds them (#645),
    /// for readers such as Ask that would otherwise cite held rows as current.
    func presentedLastScan(for profileID: UUID?) -> Date? {
        presence().lastScan(for: profileID)
    }

    /// What a question shows for one network (#645): its saved devices, its last scan and a name the
    /// user gave it. Never the generated name, the same at every site on one subnet.
    func identityOptionSummary(for id: UUID) -> IdentityOptionSummary {
        IdentityOptionSummary(
            savedDevices: DeviceGroups.project(fetchDevices(for: id)).count,
            lastScanned: lastScanTime(for: id),
            name: networkProfileManager.profiles.first { $0.id == id }?.customName
        )
    }

    /// Connects a new `identity`: the local network's scan once a held network settles, and option
    /// summaries for its questions.
    func wireIdentity() {
        identity?.onSettled = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.localScanQueued = true
                self.runQueuedScanIfFree()
            }
        }
        identity?.describeOption = { [weak self] id in self?.identityOptionSummary(for: id) ?? IdentityOptionSummary() }
    }

    /// While identifying, refuses a scan and remembers it (#645 round 4):
    /// - a manual network's scan waits only for the probe (it shares the Bonjour browser), and runs
    ///   for that network when the probe ends; the local network's question doesn't hold it;
    /// - any scan of the local network runs once it's identified, under the identified ID, never
    ///   under the tentative one it was asked for. True when refused.
    func queueWhileIdentifying(_ reason: ScanReason) -> Bool {
        if let manual = reason.manualNetwork {
            guard isProbing else { return false }
            queuedManual = manual
        } else {
            guard isIdentifyingNetwork else { return false }
            localScanQueued = true
        }
        Logger.discovery.notice("Scan queued (\(reason.logLabel, privacy: .public)): identifying which network this is")
        return true
    }

    /// A scan of `profile` (nil: the local network) is starting: what was queued for it is done.
    func noteScanStarting(_ profile: NetworkProfile?) {
        if let profile, profile.id == queuedManual?.id {
            queuedManual = nil
        }
        if profile == nil || profile?.id == networkProfileManager.localProfile?.id {
            localScanQueued = false
        }
    }

    /// Runs what was queued once the coordinator is free: a manual network's scan when no probe runs,
    /// then (`includingLocal`) the local network's once it's identified. The local one is started only
    /// by settling or by the scan before it ending, so it runs once.
    func runQueuedScanIfFree(includingLocal: Bool = true) {
        guard !isScanning, !isProbing else { return }
        if let manual = queuedManual {
            queuedManual = nil
            rescan(.user(manual))
        } else if includingLocal, localScanQueued, identity?.isIdentifying != true, identity?.heldNetworkIDs.isEmpty != false {
            localScanQueued = false
            rescan(.identified)
        }
    }

    /// Whether identification holds a scan for `profileID` (#628 PR B, #645 round 4): the local
    /// network until it's identified with its router unchanged, and any network that was only
    /// tentative for this connection, so nothing commits under an ID never identified here.
    func identityHolds(_ profileID: UUID?) -> Bool {
        guard let identity, let profileID else { return false }
        if profileID == networkProfileManager.localProfile?.id {
            return !identity.authorizes(profileID)
        }
        return identity.wasOnlyTentative(profileID)
    }

    /// Ends probe `run` if it's still the latest: an obsolete probe ends nothing. Then runs what was
    /// queued, as far as identification allows.
    private func endProbeRun(_ run: Int) {
        guard run == probeRun else { return }
        isProbing = false
        bonjourScanner.stopDiscovery()
        Task { @MainActor [weak self] in self?.runQueuedScanIfFree(includingLocal: false) }
    }

    /// Whether identification is under way, so a scan asked for now is refused and one follows it.
    var isIdentifyingNetwork: Bool {
        isProbing || identity?.isIdentifying == true
    }

    /// The identification probe (#628 PR B): a scan of the current network with its own sink, for
    /// a legacy network's history. It compares what answers with the legacy network's saved devices
    /// (`LegacyOverlap`, anchored at the routed gateway) and never reconciles, records, publishes or
    /// calls the scan-completed handlers. Nil when the gateway is unknown or the probe was cancelled.
    func identificationProbe(legacy: UUID) async -> Bool? {
        probeRun += 1
        let run = probeRun
        isProbing = true
        defer { endProbeRun(run) }
        // One user of the Bonjour browser at a time: let a running scan finish first.
        await scanTask?.value
        guard !Task.isCancelled, run == probeRun else { return nil }
        // Names come from Bonjour as in a scan: on macOS 27 there are no MACs, so the gateway's name is
        // the only anchor.
        bonjourScanner.startDiscovery()
        // Only the latest probe's engine may stop the shared browser. A controller's inventory may be
        // another site's (a reachable UniFi controller of the old one): the probe matches only what
        // this network answers.
        let full = makePipeline { [weak self] in self?.probeRun == run }
        let pipeline = ScanPipeline(steps: full.steps.compactMap { step in
            let phases = step.phases.filter { $0.id != .unifiInventory }
            return phases.isEmpty ? nil : ScanPipeline.Step(phases: phases, concurrent: step.concurrent)
        })
        let context = makeScanContext()
        let devices = await ScanEngine().scan(pipeline: pipeline, context: context) { _, _ in }
        guard !Task.isCancelled, let gateway = gatewayIP() else { return nil }
        let observed = devices.filter { !$0.isCached }.map {
            LegacyOverlap.Observation(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.hostname)
        }
        let saved = fetchDevices(for: legacy).map {
            LegacyOverlap.SavedDevice(
                deviceID: $0.deviceGroupID ?? $0.id, ipAddress: $0.ipAddress, macAddress: $0.macAddress,
                name: $0.hostname ?? $0.resolvedHostname
            )
        }
        // No saved devices: no history to mix with.
        return saved.isEmpty || LegacyOverlap.isClear(gatewayIP: gateway, observed: observed, saved: saved)
    }
}
