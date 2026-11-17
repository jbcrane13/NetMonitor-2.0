import Foundation
import os

private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "ARP")

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

        // Read the table before probing, so entries re-confirmed during this scan can be
        // told from ones left over from devices that may have gone (#378).
        let filter = context.subnetFilter
        let baseline = ARPCacheScanner.expiryByIP(ARPCacheScanner.readARPEntries().filter { filter($0.ip) })
        await accumulator.recordARPBaseline(baseline)

        // Fire UDP probes to populate the ARP cache
        ARPCacheScanner.populateARPCache(hosts: context.hosts)
        guard !Task.isCancelled else { return }
        await onProgress(0.3)

        // Read the ARP cache until it stops growing (#379). Filter to the target subnet
        // only: the cache holds entries from every interface (VPN, Docker, stale, etc.),
        // and those must not keep the loop waiting.
        let results = await ARPCacheScanner.pollUntilSettled(read: {
            ARPCacheScanner.readARPEntries().filter { filter($0.ip) }
        })
        guard !Task.isCancelled else { return }
        if results.isEmpty {
            // Expected on macOS 27, where sandboxed apps read an empty table (#401).
            logger.notice("ARP read returned 0 entries after probing \(context.hosts.count, privacy: .public) hosts")
        }
        await onProgress(0.8)

        // A stale entry alone is not evidence the device is still here; later phases
        // (ICMP, TCP, Bonjour, SSDP, the ARP re-check) can still confirm it.
        let refreshed = ARPCacheScanner.refreshedIPs(baseline: baseline, current: results)
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
            ), confirmsPresence: refreshed.contains(entry.ip))
        }

        await onProgress(1.0)
    }
}
