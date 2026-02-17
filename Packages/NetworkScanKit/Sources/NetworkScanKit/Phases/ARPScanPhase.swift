import Foundation

/// Discovers devices by firing UDP probes to trigger ARP resolution,
/// then reading the system ARP cache for IP/MAC pairs.
public struct ARPScanPhase: ScanPhase, Sendable {
    public let id = "arp"
    public let displayName = "Scanning network…"
    public let weight: Double = 0.10

    public init() {}

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        // Fire UDP probes to populate the ARP cache
        ARPCacheScanner.populateARPCache(hosts: context.hosts)
        await onProgress(0.3)

        // Wait for ARP resolution
        try? await Task.sleep(for: .seconds(2))
        await onProgress(0.6)

        // Read the ARP cache
        let results = ARPCacheScanner.readARPCache()
        await onProgress(0.8)

        // Upsert discovered devices — filter to target subnet only
        // (the ARP cache contains entries from all interfaces: VPN, Docker, stale, etc.)
        for (ip, mac) in results where context.subnetFilter(ip) {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: mac,
                latency: nil,
                discoveredAt: Date(),
                source: .local
            ))
        }

        await onProgress(1.0)
    }
}
