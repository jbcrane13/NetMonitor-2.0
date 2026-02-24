import Foundation
import Testing
import NetworkScanKit
@testable import NetMonitorCore

@Suite("ScanSchedulerService")
struct ScanSchedulerServiceTests {

    /// Swift Testing creates a fresh struct for every @Test, so this init()
    /// runs before each test — guarantees a clean UserDefaults baseline state.
    init() {
        UserDefaults.standard.removeObject(forKey: "scanScheduler_baseline")
    }

    private func makeDevice(mac: String, ip: String) -> DiscoveredDevice {
        DiscoveredDevice(
            id: UUID(),
            ipAddress: ip,
            hostname: nil,
            vendor: nil,
            macAddress: mac,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
    }

    @Test("computeDiff detects new devices not in baseline")
    @MainActor
    func computeDiffDetectsNewDevices() {
        // Clear any previous baseline by running an empty scan first
        let service = ScanSchedulerService()
        _ = service.computeDiff(current: [])

        let newDevice = makeDevice(mac: "AA:BB:CC:DD:EE:01", ip: "192.168.1.10")
        let diff = service.computeDiff(current: [newDevice])

        #expect(diff.newDevices.count == 1)
        #expect(diff.newDevices.first?.macAddress == "AA:BB:CC:DD:EE:01")
        #expect(diff.removedDevices.isEmpty)
    }

    @Test("computeDiff detects removed devices that were in baseline")
    @MainActor
    func computeDiffDetectsRemovedDevices() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:02", ip: "192.168.1.11")

        // Establish baseline with the device
        _ = service.computeDiff(current: [device])

        // Next scan — device is gone
        let diff = service.computeDiff(current: [])

        #expect(diff.removedDevices.count == 1)
        #expect(diff.removedDevices.first?.macAddress == "AA:BB:CC:DD:EE:02")
        #expect(diff.newDevices.isEmpty)
    }

    @Test("computeDiff: stable set yields empty new and removed arrays")
    @MainActor
    func computeDiffStableSetIsEmpty() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:03", ip: "192.168.1.12")

        // Establish baseline
        _ = service.computeDiff(current: [device])

        // Same device still present
        let diff = service.computeDiff(current: [device])

        #expect(diff.newDevices.isEmpty)
        #expect(diff.removedDevices.isEmpty)
    }

    @Test("computeDiff on empty scan returns empty diff")
    @MainActor
    func computeDiffEmptyScanEmptyDiff() {
        let service = ScanSchedulerService()
        // No prior baseline, empty current
        let diff = service.computeDiff(current: [])

        #expect(diff.newDevices.isEmpty)
        #expect(diff.removedDevices.isEmpty)
        #expect(diff.changedDevices.isEmpty)
    }

    @Test("computeDiff caches result in cachedDiff")
    @MainActor
    func computeDiffCachesResult() {
        let service = ScanSchedulerService()
        #expect(service.cachedDiff == nil)

        let device = makeDevice(mac: "AA:BB:CC:DD:EE:04", ip: "192.168.1.13")
        _ = service.computeDiff(current: [device])

        #expect(service.cachedDiff != nil)
    }

    @Test("getLastScanDiff returns nil before first scan")
    @MainActor
    func getLastScanDiffNilBeforeFirstScan() {
        let service = ScanSchedulerService()
        #expect(service.getLastScanDiff() == nil)
    }

    @Test("Devices without MAC addresses are excluded from diff")
    @MainActor
    func devicesWithoutMACExcludedFromDiff() {
        let service = ScanSchedulerService()
        // Clear baseline
        _ = service.computeDiff(current: [])

        // Device with no MAC
        let noMAC = DiscoveredDevice(ipAddress: "192.168.1.20", latency: 1.0, discoveredAt: Date())
        let diff = service.computeDiff(current: [noMAC])

        // Devices without MAC are skipped in diff logic
        #expect(diff.newDevices.isEmpty)
    }
}
