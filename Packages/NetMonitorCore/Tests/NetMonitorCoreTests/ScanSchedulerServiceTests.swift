import Foundation
import Testing
import NetworkScanKit
@testable import NetMonitorCore

// .serialized: prevents parallel test execution within this suite.
// ScanSchedulerService persists baseline to UserDefaults.standard — parallel
// tests race on that shared key, causing state bleed between tests.
@Suite("ScanSchedulerService", .serialized)
struct ScanSchedulerServiceTests {

    /// Runs before each test (Swift Testing creates a fresh struct per @Test).
    /// Clears UserDefaults baseline so every test starts from a clean slate.
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

    // MARK: - Schedule next scan: correct interval calculation

    @Test("scheduleNextScan sets isScanDue based on interval")
    @MainActor
    func scheduleNextScanSetsInterval() {
        let service = ScanSchedulerService()
        #expect(service.isScanDue == false, "Before scheduling, scan should not be due")

        // Schedule with a very small interval (essentially immediate)
        service.scheduleNextScan(interval: 0)
        #expect(service.isScanDue == true, "After scheduling with 0 interval, scan should be due immediately")
    }

    @Test("scheduleNextScan with future interval: scan is not yet due")
    @MainActor
    func scheduleNextScanFutureInterval() {
        let service = ScanSchedulerService()
        service.scheduleNextScan(interval: 3600) // 1 hour from now
        #expect(service.isScanDue == false, "Scan should not be due for future interval")
    }

    @Test("scheduleNextScan can be called multiple times, last wins")
    @MainActor
    func scheduleNextScanMultipleCalls() {
        let service = ScanSchedulerService()
        service.scheduleNextScan(interval: 0) // immediate
        #expect(service.isScanDue == true)

        service.scheduleNextScan(interval: 3600) // reschedule to future
        #expect(service.isScanDue == false, "Rescheduling to future should make scan not due")
    }

    // MARK: - Compute diff: new, removed, and changed devices

    @Test("computeDiff detects both new and removed devices simultaneously")
    @MainActor
    func computeDiffDetectsNewAndRemovedSimultaneously() {
        let service = ScanSchedulerService()
        let deviceA = makeDevice(mac: "AA:BB:CC:DD:EE:10", ip: "192.168.1.10")
        let deviceB = makeDevice(mac: "AA:BB:CC:DD:EE:11", ip: "192.168.1.11")

        // Baseline: [A]
        _ = service.computeDiff(current: [deviceA])

        // Next scan: [B] (A removed, B new)
        let diff = service.computeDiff(current: [deviceB])

        #expect(diff.newDevices.count == 1)
        #expect(diff.newDevices.first?.macAddress == "AA:BB:CC:DD:EE:11")
        #expect(diff.removedDevices.count == 1)
        #expect(diff.removedDevices.first?.macAddress == "AA:BB:CC:DD:EE:10")
    }

    @Test("computeDiff changedDevices is always empty in current implementation")
    @MainActor
    func computeDiffChangedDevicesAlwaysEmpty() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:20", ip: "192.168.1.20")
        _ = service.computeDiff(current: [device])

        // Same MAC but different IP — current implementation does not detect changes
        let deviceUpdated = makeDevice(mac: "AA:BB:CC:DD:EE:20", ip: "192.168.1.21")
        let diff = service.computeDiff(current: [deviceUpdated])

        #expect(diff.changedDevices.isEmpty, "changedDevices is not computed in current implementation")
    }

    @Test("computeDiff with many devices works correctly")
    @MainActor
    func computeDiffManyDevices() {
        let service = ScanSchedulerService()
        // Clear baseline
        _ = service.computeDiff(current: [])

        // Generate 50 devices
        var devices: [DiscoveredDevice] = []
        for i in 0..<50 {
            let mac = String(format: "AA:BB:CC:DD:%02X:%02X", i / 256, i % 256)
            devices.append(makeDevice(mac: mac, ip: "192.168.1.\(i + 1)"))
        }

        let diff = service.computeDiff(current: devices)
        #expect(diff.newDevices.count == 50)
        #expect(diff.removedDevices.isEmpty)
    }

    // MARK: - State persistence across service restarts

    @Test("Baseline persists across new ScanSchedulerService instances")
    @MainActor
    func baselinePersistsAcrossInstances() {
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:30", ip: "192.168.1.30")

        // First instance: establish baseline
        let service1 = ScanSchedulerService()
        _ = service1.computeDiff(current: [device])

        // Second instance: should load persisted baseline
        let service2 = ScanSchedulerService()
        let diff = service2.computeDiff(current: [device])

        // Same device present in both — no changes
        #expect(diff.newDevices.isEmpty, "Device should not appear as new if persisted in baseline")
        #expect(diff.removedDevices.isEmpty)
    }

    @Test("getLastScanDiff returns result after computeDiff")
    @MainActor
    func getLastScanDiffReturnsAfterCompute() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:40", ip: "192.168.1.40")
        let diff = service.computeDiff(current: [device])
        let cached = service.getLastScanDiff()

        #expect(cached != nil)
        #expect(cached?.newDevices.count == diff.newDevices.count)
    }

    // MARK: - ScanDiff convenience helpers

    @Test("ScanDiff hasChanges returns true when new devices exist")
    @MainActor
    func scanDiffHasChangesWithNewDevices() {
        let service = ScanSchedulerService()
        _ = service.computeDiff(current: [])

        let device = makeDevice(mac: "AA:BB:CC:DD:EE:50", ip: "192.168.1.50")
        let diff = service.computeDiff(current: [device])

        #expect(diff.hasChanges == true)
        #expect(diff.totalChanges == 1)
    }

    @Test("ScanDiff hasChanges returns false when no changes")
    @MainActor
    func scanDiffHasChangesNoChanges() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:60", ip: "192.168.1.60")
        _ = service.computeDiff(current: [device])

        let diff = service.computeDiff(current: [device])
        #expect(diff.hasChanges == false)
        #expect(diff.totalChanges == 0)
    }

    @Test("ScanDiff summaryText describes changes correctly")
    @MainActor
    func scanDiffSummaryText() {
        let service = ScanSchedulerService()
        _ = service.computeDiff(current: [])

        let device = makeDevice(mac: "AA:BB:CC:DD:EE:70", ip: "192.168.1.70")
        let diff = service.computeDiff(current: [device])

        #expect(diff.summaryText.contains("1 new"))
    }

    @Test("ScanDiff summaryText for no changes returns 'No changes'")
    @MainActor
    func scanDiffSummaryTextNoChanges() {
        let service = ScanSchedulerService()
        let device = makeDevice(mac: "AA:BB:CC:DD:EE:80", ip: "192.168.1.80")
        _ = service.computeDiff(current: [device])
        let diff = service.computeDiff(current: [device])

        #expect(diff.summaryText == "No changes")
    }

    @Test("Devices with empty MAC strings are excluded from diff")
    @MainActor
    func devicesWithEmptyMACExcludedFromDiff() {
        let service = ScanSchedulerService()
        _ = service.computeDiff(current: [])

        let emptyMAC = DiscoveredDevice(
            id: UUID(),
            ipAddress: "192.168.1.99",
            hostname: nil,
            vendor: nil,
            macAddress: "",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
        let diff = service.computeDiff(current: [emptyMAC])
        #expect(diff.newDevices.isEmpty, "Devices with empty MAC should be excluded")
    }
}
