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

    /// The identification probe (#628 PR B): a scan of the current network with its own sink, for
    /// a legacy network's history. It compares what answers with the legacy network's saved devices
    /// (`LegacyOverlap`, anchored at the routed gateway) and never reconciles, records, publishes or
    /// calls the scan-completed handlers. Nil when the gateway is unknown or the probe was cancelled.
    func identificationProbe(legacy: UUID) async -> Bool? {
        isProbing = true
        defer { isProbing = false }
        // One user of the Bonjour browser at a time: let a running scan finish first.
        await scanTask?.value
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
