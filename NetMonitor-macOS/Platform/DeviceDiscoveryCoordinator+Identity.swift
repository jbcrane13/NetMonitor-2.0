import Foundation
import NetMonitorCore
import NetworkScanKit

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

    /// Ends probe `run` if it's still the latest: an obsolete probe ends nothing. Then runs a scan
    /// refused meanwhile, unless identification continues or holds the network: both scan when it
    /// settles (`onSettled`).
    private func endProbeRun(_ run: Int) {
        guard run == probeRun else { return }
        isProbing = false
        bonjourScanner.stopDiscovery()
        guard scanQueuedAfterIdentification, identity?.isIdentifying != true else { return }
        Task { @MainActor [weak self] in
            guard let self, scanQueuedAfterIdentification, !isIdentifyingNetwork, identity?.heldNetworkIDs.isEmpty != false else { return }
            rescan(.identified)
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
        let pipeline = makePipeline()
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
