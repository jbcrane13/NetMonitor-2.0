import Foundation

/// Discovers devices by firing UDP probes to trigger ARP resolution,
/// then reading the system ARP cache for IP/MAC pairs.
public struct ARPScanPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .arp
    public let displayName = "Scanning network…"
    public let weight: Double = 0.10

    public init() {}

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        // Fire UDP probes to populate the ARP cache
        ARPCacheScanner.populateARPCache(hosts: context.hosts)
        guard !Task.isCancelled else { return }
        await onProgress(0.3)

        // Read the ARP cache until it stops growing (#379). Filter to the target subnet
        // only: the cache holds entries from every interface (VPN, Docker, stale, etc.),
        // and those must not keep the loop waiting.
        let filter = context.subnetFilter
        let results = await ARPCacheScanner.pollUntilSettled(read: {
            ARPCacheScanner.readARPEntries().filter { filter($0.ip) }
        })
        guard !Task.isCancelled else { return }
        await onProgress(0.8)

        for entry in results {
            guard !Task.isCancelled else { return }
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: entry.ip,
                hostname: nil,
                vendor: nil,
                macAddress: entry.mac,
                latency: nil,
                discoveredAt: Date(),
                source: .local
            ))
        }

        await onProgress(1.0)
    }
}
