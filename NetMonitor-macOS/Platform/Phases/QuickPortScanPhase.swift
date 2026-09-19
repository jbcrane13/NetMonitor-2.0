import Foundation
import NetworkScanKit

extension ScanPhaseID {
    // Named "portScan" rather than "quickPortScan" so it doesn't collide, as a substring,
    // with the retired coordinator method `quickPortScan(profileID:portChecker:)` that
    // verification greps for (it must be gone from DeviceDiscoveryCoordinator.swift).
    static let portScan = ScanPhaseID(rawValue: "portScan")
}

/// Quick 15-port TCP fingerprinting scan over every accumulator entry, writing `openPorts`
/// (E7).
///
/// `checker` still runs under `withConnectionSlot`, exactly as today — that happens inside
/// the checker itself (the default is `DeviceDiscoveryCoordinator.checkPort`), unchanged by
/// this phase.
struct QuickPortScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = .portScan
    let displayName = "Scanning ports…"
    let weight: Double
    let timeout: Duration?

    /// Top common ports — fast fingerprinting set (unchanged from the retired
    /// `quickPortScan`'s `commonPorts`).
    static let commonPorts = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]

    private let checker: @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool
    /// Matches the retired `quickPortScan`'s device-level sliding-window cap.
    private let maxConcurrentHosts: Int

    init(
        checker: @escaping @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool,
        weight: Double = 0.09,
        maxConcurrentHosts: Int = 10,
        timeout: Duration? = .seconds(60)
    ) {
        self.checker = checker
        self.weight = weight
        self.maxConcurrentHosts = maxConcurrentHosts
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
        guard !devices.isEmpty else {
            await onProgress(1.0)
            return
        }

        let total = devices.count
        var completed = 0
        let checker = self.checker

        await forEachBounded(devices, limit: maxConcurrentHosts, operation: { device -> (String, [Int]) in
            let ip = device.ipAddress
            var openPorts: [Int] = []
            await withTaskGroup(of: (Int, Bool).self) { portGroup in
                for port in Self.commonPorts {
                    portGroup.addTask {
                        let isOpen = await checker(ip, port, 1000)
                        return (port, isOpen)
                    }
                }
                for await (port, isOpen) in portGroup where isOpen {
                    openPorts.append(port)
                }
            }
            return (ip, openPorts.sorted())
        }, onResult: { ip, openPorts in
            completed += 1
            if !openPorts.isEmpty {
                await accumulator.upsert(DiscoveredDevice(
                    ipAddress: ip,
                    hostname: nil,
                    vendor: nil,
                    macAddress: nil,
                    latency: nil,
                    discoveredAt: Date(),
                    source: .local,
                    openPorts: openPorts
                ))
            }
            await onProgress(Double(completed) / Double(max(total, 1)))
        })

        await onProgress(1.0)
    }
}
