import Foundation
import NetMonitorCore
import NetworkScanKit

extension ScanPhaseID {
    static let vendorLookup = ScanPhaseID(rawValue: "vendorLookup")
}

/// Fills `vendor` for accumulator entries that have a MAC and no vendor yet.
///
/// `MACVendorLookupService` is a `URLSession`-backed actor (local OUI table first, then
/// macvendors.com). `lookupTimeout` races each device's lookup against a hard deadline in
/// addition to `ScanPhase.timeout` (E6) — a per-lookup bound, not just a per-phase one — so
/// one slow or unreachable macvendors.com request degrades that single device to "no vendor"
/// instead of consuming the whole phase's budget.
struct VendorLookupPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = .vendorLookup
    let displayName = "Looking up vendors…"
    let weight: Double
    let timeout: Duration?

    private let service: MACVendorLookupService
    /// Matches the retired `resolveDeviceVendors`'s sliding-window cap.
    private let maxConcurrentLookups: Int
    private let lookupTimeout: Duration

    init(
        service: MACVendorLookupService,
        weight: Double = 0.05,
        maxConcurrentLookups: Int = 5,
        lookupTimeout: Duration = .seconds(6),
        timeout: Duration? = .seconds(45)
    ) {
        self.service = service
        self.weight = weight
        self.maxConcurrentLookups = maxConcurrentLookups
        self.lookupTimeout = lookupTimeout
        self.timeout = timeout
    }

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let devices = await accumulator.snapshot()
        let candidates = devices.filter { device in
            guard let mac = device.macAddress, !mac.isEmpty else { return false }
            return device.vendor == nil || device.vendor?.isEmpty == true
        }
        guard !candidates.isEmpty else {
            await onProgress(1.0)
            return
        }

        let total = candidates.count
        var completed = 0
        let service = self.service
        let lookupTimeout = self.lookupTimeout

        await forEachBounded(candidates, limit: maxConcurrentLookups, operation: { device -> (String, String?) in
            let mac = device.macAddress ?? ""
            let vendor = await Self.lookupWithTimeout(service: service, macAddress: mac, timeout: lookupTimeout)
            return (device.ipAddress, vendor)
        }, onResult: { ip, vendor in
            completed += 1
            if let vendor, !vendor.isEmpty {
                await accumulator.upsert(DiscoveredDevice(
                    ipAddress: ip,
                    hostname: nil,
                    vendor: vendor,
                    macAddress: nil,
                    latency: nil,
                    discoveredAt: Date(),
                    source: .local
                ))
            }
            await onProgress(Double(completed) / Double(max(total, 1)))
        })

        await onProgress(1.0)
    }

    /// Races a lookup against `timeout`; whichever finishes first wins and the loser is
    /// cancelled. A hung `URLSession` call degrades to "no vendor" rather than blocking the
    /// bounded-concurrency slot it holds for the rest of the phase.
    private static func lookupWithTimeout(
        service: MACVendorLookupService,
        macAddress: String,
        timeout: Duration
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await service.lookupVendorEnhanced(macAddress: macAddress) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let firstResult = await group.next()
            group.cancelAll()
            return firstResult.flatMap { $0 }
        }
    }
}
