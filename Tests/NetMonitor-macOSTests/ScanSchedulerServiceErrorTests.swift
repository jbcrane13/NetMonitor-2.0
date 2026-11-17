import Testing
import Foundation
import NetMonitorCore
import NetworkScanKit

/// Tests that ScanSchedulerService handles bad stored data safely and reports removals
/// after the grace period (#393).
///
/// Since #393 the service keeps every device it has seen (DeviceChangeTracker) instead of
/// only the previous scan. Corrupt stored data now reads as "no state": the next scan is a
/// baseline, so it can't flood the user with "new device" alerts.
@MainActor
struct ScanSchedulerServiceErrorTests {

    // MARK: - Helpers

    private func makeDevice(ip: String, mac: String) -> DiscoveredDevice {
        DiscoveredDevice(
            id: UUID(),
            ipAddress: ip,
            hostname: nil,
            vendor: nil,
            macAddress: mac,
            latency: 1.0,
            discoveredAt: Date(),
            source: .local
        )
    }

    /// A fresh defaults suite per test. The grace policy needs two missed scans and no
    /// minimum time, so removals can be tested without waiting.
    private func makeService(_ defaults: UserDefaults) -> ScanSchedulerService {
        ScanSchedulerService(defaults: defaults, policy: DeviceGracePolicy(missedScans: 2, interval: 0))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ScanSchedulerServiceErrorTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite) ?? .standard, suite)
    }

    // MARK: - Persistence

    @Test("Known devices persist across instances")
    func knownDevicesPersistAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02")
        ]

        let first = makeService(defaults).computeDiff(current: devices)
        #expect(first.newDevices.isEmpty, "The first scan is a baseline")

        let second = makeService(defaults).computeDiff(current: devices)
        #expect(second.newDevices.isEmpty, "Same devices on a new instance are not new")
        #expect(second.removedDevices.isEmpty)
    }

    @Test("Corrupt stored registry reads as no state: a baseline, not a burst of new devices")
    func corruptRegistryIsABaseline() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not valid json data".utf8), forKey: "deviceChangeRegistry")

        let diff = makeService(defaults).computeDiff(current: [makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")])

        #expect(diff.newDevices.isEmpty)
    }

    @Test("Truncated old baseline JSON seeds nothing and doesn't crash")
    func truncatedOldBaselineSeedsNothing() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("[{\"ipAddress\":\"192.168.1.1\"".utf8), forKey: "scanScheduler_baseline")
        let devices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02")
        ]

        let diff = makeService(defaults).computeDiff(current: devices)

        #expect(diff.newDevices.isEmpty, "With nothing seeded, the first scan is a baseline")
        #expect(diff.removedDevices.isEmpty)
    }

    // MARK: - Diff accuracy

    @Test("A device going offline appears in removedDevices after the grace period")
    func deviceGoingOfflineAppearsInRemoved() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = makeService(defaults)
        let allDevices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02"),
            makeDevice(ip: "192.168.1.3", mac: "AA:BB:CC:DD:EE:03")
        ]
        let reducedDevices = [allDevices[0], allDevices[2]]

        _ = service.computeDiff(current: allDevices)
        let oneMiss = service.computeDiff(current: reducedDevices)
        #expect(oneMiss.removedDevices.isEmpty, "One missed scan is never enough")

        let diff = service.computeDiff(current: reducedDevices)
        #expect(diff.removedDevices.map(\.macAddress) == ["AA:BB:CC:DD:EE:02"])
        #expect(diff.newDevices.isEmpty)
    }

    @Test("Devices without MAC addresses are tracked by IP")
    func devicesWithoutMACAreTrackedByIP() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = makeService(defaults)
        let deviceWithMAC = makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")
        let deviceWithoutMAC = DiscoveredDevice(ipAddress: "192.168.1.2", latency: 1.0, discoveredAt: Date())

        _ = service.computeDiff(current: [deviceWithMAC, deviceWithoutMAC])
        _ = service.computeDiff(current: [deviceWithMAC])
        let diff = service.computeDiff(current: [deviceWithMAC])

        #expect(diff.removedDevices.map(\.ipAddress) == ["192.168.1.2"])
        #expect(diff.newDevices.isEmpty)
    }

    @Test("cachedDiff is updated after computeDiff")
    func cachedDiffUpdatedAfterComputeDiff() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = makeService(defaults)
        #expect(service.cachedDiff == nil, "cachedDiff should be nil before first scan")

        let diff = service.computeDiff(current: [makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")])

        #expect(service.cachedDiff != nil, "cachedDiff should be set after computeDiff")
        #expect(service.cachedDiff?.newDevices.count == diff.newDevices.count)
    }
}
