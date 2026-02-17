import Foundation

/// Resolves hostnames for discovered devices that are missing one,
/// using reverse DNS (PTR) lookups.
public struct ReverseDNSScanPhase: ScanPhase, Sendable {
    public let id = "reverseDNS"
    public let displayName = "Resolving names…"
    public let weight: Double = 0.08

    /// Maximum number of concurrent PTR lookups.
    let maxConcurrentResolves: Int

    public init(maxConcurrentResolves: Int = 20) {
        self.maxConcurrentResolves = maxConcurrentResolves
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        let devices = await accumulator.snapshot()
        let devicesNeedingNames = devices.filter { $0.hostname == nil }
        guard !devicesNeedingNames.isEmpty else {
            await onProgress(1.0)
            return
        }

        let nameResolver = DeviceNameResolver()
        let total = devicesNeedingNames.count
        var resolved = 0

        await withTaskGroup(of: (String, String?).self) { group in
            var pending = 0
            var iterator = devicesNeedingNames.makeIterator()

            while pending < maxConcurrentResolves, let device = iterator.next() {
                pending += 1
                group.addTask {
                    let name = await nameResolver.resolve(ipAddress: device.ipAddress)
                    return (device.ipAddress, name)
                }
            }

            for await (ip, hostname) in group {
                pending -= 1
                resolved += 1

                if let hostname {
                    await accumulator.upsert(DiscoveredDevice(
                        ipAddress: ip,
                        hostname: hostname,
                        vendor: nil,
                        macAddress: nil,
                        latency: nil,
                        discoveredAt: Date(),
                        source: .local
                    ))
                }

                let progress = Double(resolved) / Double(max(total, 1))
                await onProgress(progress)

                if let nextDevice = iterator.next() {
                    pending += 1
                    group.addTask {
                        let name = await nameResolver.resolve(ipAddress: nextDevice.ipAddress)
                        return (nextDevice.ipAddress, name)
                    }
                }
            }
        }

        await onProgress(1.0)
    }
}
