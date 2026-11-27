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

    /// Connects a new `identity`: one scan once a held network settles (the scan refused meanwhile,
    /// as asked, else the local network's), and option summaries for its questions.
    func wireIdentity() {
        identity?.onSettled = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let queued = self.queuedScan
                self.queuedScan = nil
                self.rescan(queued ?? .identified)
            }
        }
        identity?.describeOption = { [weak self] id in self?.identityOptionSummary(for: id) ?? IdentityOptionSummary() }
    }

    /// While identifying, refuses a scan and remembers it, a user's scan of a manual network winning
    /// over a local one. True when refused.
    func queueWhileIdentifying(_ reason: ScanReason) -> Bool {
        guard isIdentifyingNetwork else { return false }
        Logger.discovery.notice("Scan queued (\(reason.logLabel, privacy: .public)): identifying which network this is")
        if queuedScan?.manualNetwork == nil || reason.manualNetwork != nil {
            queuedScan = reason
        }
        return true
    }

    /// Ends probe `run` if it's still the latest: an obsolete probe ends nothing. Then runs a scan
    /// refused meanwhile, unless identification continues or holds the network: both scan when it
    /// settles (`onSettled`).
    private func endProbeRun(_ run: Int) {
        guard run == probeRun else { return }
        isProbing = false
        bonjourScanner.stopDiscovery()
        guard queuedScan != nil, identity?.isIdentifying != true else { return }
        Task { @MainActor [weak self] in
            // A manual network's scan runs now; a local one waits while the network is held (it scans
            // when it settles).
            guard let self, let queued = queuedScan, !isIdentifyingNetwork,
                  queued.manualNetwork != nil || identity?.heldNetworkIDs.isEmpty != false else { return }
            queuedScan = nil
            rescan(queued)
        }
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
        // Only the latest probe's engine may stop the shared browser.
        let pipeline = makePipeline { [weak self] in self?.probeRun == run }
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
