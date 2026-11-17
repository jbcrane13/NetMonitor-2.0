import Foundation

/// Re-reads the ARP table after the latency phase and confirms devices whose entry
/// was re-confirmed during the scan (#378).
///
/// Some devices drop ICMP and have no open TCP ports, yet still answer ARP. Pinging
/// them makes the kernel re-check their entry, so its expiry moves forward even with
/// no ping reply (measured on macOS 27.2). Without this phase those devices would be
/// shown as cached although they are on the network.
public struct ARPRecheckPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .arpRecheck
    public let displayName = "Confirming devices…"
    public let weight: Double = 0.01

    private let readEntries: @Sendable () -> [ARPEntry]

    public init() {
        self.init(readEntries: ARPCacheScanner.readARPEntries)
    }

    /// Test seam: supplies the ARP table instead of reading the system one.
    init(readEntries: @escaping @Sendable () -> [ARPEntry]) {
        self.readEntries = readEntries
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)
        let unconfirmed = await accumulator.unconfirmedDeviceIPs()
        guard !unconfirmed.isEmpty, !Task.isCancelled else {
            await onProgress(1.0)
            return
        }

        let baseline = await accumulator.arpBaselineExpiries()
        let current = readEntries().filter { unconfirmed.contains($0.ip) }
        let refreshed = ARPCacheScanner.refreshedIPs(baseline: baseline, current: current)
        await accumulator.confirmPresence(ips: refreshed.intersection(unconfirmed))
        await onProgress(1.0)
    }
}
