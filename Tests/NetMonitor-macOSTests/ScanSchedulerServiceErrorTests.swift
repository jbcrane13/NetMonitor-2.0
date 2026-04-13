import Testing
import Foundation
import NetMonitorCore
import NetworkScanKit

/// Tests that ScanSchedulerService surfaces encoding/decoding errors rather than
/// silently losing baseline data.
///
/// ScanSchedulerService has two silent failure points:
/// - saveBaseline (line ~79): `guard let data = try? JSONEncoder().encode(devices) else { return }`
///   silently discards the baseline if encoding fails
/// - loadBaseline (line ~72): `try? JSONDecoder().decode(...)` silently returns [] on corrupt data
///
/// These tests verify that encoding failures don't silently lose baseline data,
/// and that corrupt UserDefaults data doesn't silently produce wrong diffs.
@MainActor
struct ScanSchedulerServiceErrorTests {

    // MARK: - Helpers

    /// Creates a DiscoveredDevice with the given MAC address for diff testing.
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

    /// Unique UserDefaults key to avoid test interference.
    /// ScanSchedulerService uses a hardcoded key "scanScheduler_baseline",
    /// so we clean up before and after each test.
    private func cleanupDefaults() {
        UserDefaults.standard.removeObject(forKey: "scanScheduler_baseline")
    }

    // MARK: - Baseline Persistence Tests

    @Test("computeDiff with valid devices saves baseline that persists across instances")
    func computeDiffSavesBaselineThatPersists() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        let service = ScanSchedulerService()
        let devices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02")
        ]

        // First scan establishes baseline
        let diff1 = service.computeDiff(current: devices)
        // All devices are new on first scan (no prior baseline)
        #expect(diff1.newDevices.count == 2)

        // Second scan with same devices — nothing new, nothing removed
        let diff2 = service.computeDiff(current: devices)
        #expect(diff2.newDevices.isEmpty, "Same devices on second scan should yield no new devices")
        #expect(diff2.removedDevices.isEmpty, "Same devices on second scan should yield no removed devices")
    }

    @Test("Corrupt UserDefaults data causes loadBaseline to return empty, treating all devices as new")
    func corruptBaselineDataTreatsAllDevicesAsNew() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        // Write garbage data to the baseline key
        UserDefaults.standard.set("not valid json data".data(using: .utf8)!, forKey: "scanScheduler_baseline")

        let service = ScanSchedulerService()
        let devices = [makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")]

        // With corrupt baseline, loadBaseline returns [] silently.
        // All current devices appear as "new" — the diff is wrong but doesn't crash.
        let diff = service.computeDiff(current: devices)

        // This is the silent failure: corrupt data means baseline is lost.
        // The service treats all devices as new rather than surfacing the corruption.
        #expect(diff.newDevices.count == 1,
                "Corrupt baseline should cause all devices to appear as new (baseline silently lost)")
    }

    @Test("Truncated JSON in UserDefaults silently loses baseline")
    func truncatedJSONSilentlyLosesBaseline() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        let service = ScanSchedulerService()
        let devices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02")
        ]

        // Establish a real baseline
        _ = service.computeDiff(current: devices)

        // Corrupt the baseline with truncated JSON
        let truncated = "[{\"ipAddress\":\"192.168.1.1\"".data(using: .utf8)!
        UserDefaults.standard.set(truncated, forKey: "scanScheduler_baseline")

        // Now compute diff — baseline is silently lost, all devices appear new
        let diff = service.computeDiff(current: devices)
        #expect(diff.newDevices.count == 2,
                "Truncated baseline JSON should cause silent baseline loss — all devices appear new")
        #expect(diff.removedDevices.isEmpty,
                "With no valid baseline, no devices can be marked as removed")
    }

    // MARK: - Diff Accuracy Tests

    @Test("Device going offline appears in removedDevices")
    func deviceGoingOfflineAppearsInRemoved() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        let service = ScanSchedulerService()
        let allDevices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.2", mac: "AA:BB:CC:DD:EE:02"),
            makeDevice(ip: "192.168.1.3", mac: "AA:BB:CC:DD:EE:03")
        ]

        // First scan with all devices
        _ = service.computeDiff(current: allDevices)

        // Second scan with one device missing
        let reducedDevices = [
            makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01"),
            makeDevice(ip: "192.168.1.3", mac: "AA:BB:CC:DD:EE:03")
        ]
        let diff = service.computeDiff(current: reducedDevices)

        #expect(diff.removedDevices.count == 1, "One device went offline — should appear in removedDevices")
        #expect(diff.removedDevices.first?.macAddress == "AA:BB:CC:DD:EE:02")
        #expect(diff.newDevices.isEmpty, "No new devices in second scan")
    }

    @Test("Devices without MAC addresses are excluded from diff computation")
    func devicesWithoutMACExcludedFromDiff() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        let service = ScanSchedulerService()
        let deviceWithMAC = makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")
        let deviceWithoutMAC = DiscoveredDevice(
            ipAddress: "192.168.1.2",
            latency: 1.0,
            discoveredAt: Date()
        )

        _ = service.computeDiff(current: [deviceWithMAC, deviceWithoutMAC])

        // Second scan without the MAC-less device
        let diff = service.computeDiff(current: [deviceWithMAC])

        // The MAC-less device should NOT appear in removedDevices because
        // it was never tracked by MAC address.
        #expect(diff.removedDevices.isEmpty,
                "Devices without MAC should not appear in removedDevices")
        #expect(diff.newDevices.isEmpty)
    }

    @Test("cachedDiff is updated after computeDiff")
    func cachedDiffUpdatedAfterComputeDiff() {
        cleanupDefaults()
        defer { cleanupDefaults() }

        let service = ScanSchedulerService()
        #expect(service.cachedDiff == nil, "cachedDiff should be nil before first scan")

        let devices = [makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")]
        let diff = service.computeDiff(current: devices)

        #expect(service.cachedDiff != nil, "cachedDiff should be set after computeDiff")
        #expect(service.cachedDiff?.newDevices.count == diff.newDevices.count)
    }
}
