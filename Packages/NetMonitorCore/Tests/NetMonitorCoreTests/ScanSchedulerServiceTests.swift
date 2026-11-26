import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #603: the scheduler's diff is the last applied scan's device events, from the dispatcher a real
/// `ScanReconciler` feeds, never its own comparison of scans.
@Suite("ScanSchedulerService", .serialized)
@MainActor
final class ScanSchedulerServiceTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    nonisolated let suiteName = "ScanSchedulerServiceTests.\(UUID().uuidString)"
    let container: ModelContainer
    let dispatcher = DeviceEventDispatcher()

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// Scan times far enough apart that 3 misses also pass the 15-minute grace period.
    private func time(_ scan: Int) -> Date {
        start.addingTimeInterval(Double(scan) * 600)
    }

    private func device(_ ip: String, name: String?, mac: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 2, discoveredAt: start, source: .local,
            networkProfileID: home
        )
    }

    private var router: DiscoveredDevice {
        device("192.168.1.1", name: "router", mac: "00:1B:A9:00:00:01")
    }

    @discardableResult
    private func reconcile(_ scan: [DiscoveredDevice], at index: Int) throws -> ScanReconciler.Outcome {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return try ScanReconciler(context: ModelContext(container), history: ScanHistory(defaults: defaults), dispatcher: dispatcher)
            .reconcile(scan, networkProfileID: home, scanDate: time(index), now: time(index))
    }

    @Test("Before any scan delivered events there is no diff, and computeDiff is empty")
    func noDiffBeforeEvents() {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        #expect(service.getLastScanDiff() == nil)
        let diff = service.computeDiff(current: [router])
        #expect(diff.newDevices.isEmpty && diff.removedDevices.isEmpty && diff.changedDevices.isEmpty)
    }

    @Test("The network's first scan is the baseline: nothing is new")
    func baselineIsQuiet() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        try reconcile([router, device("192.168.1.20", name: "tv")], at: 0)
        #expect(service.getLastScanDiff() == nil)
    }

    @Test("A device that joins is new, named by its device, at its address, as of the scan")
    func joinedIsNew() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        try reconcile([router], at: 0)
        try reconcile([router, device("192.168.1.57", name: "Pixel-8")], at: 1)
        let diff = try #require(service.getLastScanDiff())
        #expect(diff.newDevices.map(\.ipAddress) == ["192.168.1.57"])
        #expect(diff.newDevices.map(\.displayName) == ["Pixel-8"])
        #expect(diff.scannedAt == time(1))
        #expect(service.computeDiff(current: []).newDevices.map(\.ipAddress) == ["192.168.1.57"], "computeDiff returns the last diff")
    }

    @Test("A device is removed only once it went offline under grace, with when it last answered")
    func removedAfterGrace() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        let camera = device("192.168.1.41", name: "Garage Camera", mac: "00:1B:A9:00:00:41")
        try reconcile([router, camera], at: 0)
        try reconcile([router], at: 1)
        try reconcile([router], at: 2)
        #expect(service.getLastScanDiff() == nil, "two misses are within grace")
        try reconcile([router], at: 3)
        let diff = try #require(service.getLastScanDiff())
        #expect(diff.removedDevices.map(\.displayName) == ["Garage Camera"])
        #expect(diff.removedDevices.first?.discoveredAt == time(0))
        #expect(diff.newDevices.isEmpty)
    }

    @Test("DHCP reuse without MACs: the newcomer is new, not changed (#603)")
    func dhcpReuseIsNewNotChanged() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        try reconcile([router, device("192.168.1.30", name: "printer")], at: 0)
        try reconcile([router, device("192.168.1.30", name: "phone")], at: 1)
        let diff = try #require(service.getLastScanDiff())
        #expect(diff.newDevices.map(\.displayName) == ["phone"])
        #expect(diff.changedDevices.isEmpty)
    }

    @Test("A known device at a new address is changed")
    func addressChangeIsChanged() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        try reconcile([router, device("192.168.1.30", name: "nas", mac: "00:1B:A9:00:00:30")], at: 0)
        try reconcile([router, device("192.168.1.31", name: "nas", mac: "00:1B:A9:00:00:30")], at: 1)
        let diff = try #require(service.getLastScanDiff())
        #expect(diff.changedDevices.map(\.ipAddress) == ["192.168.1.31"])
        #expect(diff.newDevices.isEmpty && diff.removedDevices.isEmpty)
    }

    @Test("A skipped reconcile (the same scan again) changes nothing; a quiet scan keeps the last diff")
    func skippedAndQuietKeepTheLastDiff() throws {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        try reconcile([router], at: 0)
        try reconcile([router, device("192.168.1.57", name: "Pixel-8")], at: 1)
        #expect(try reconcile([router, device("192.168.1.58", name: "other")], at: 1) == .skipped)
        try reconcile([router, device("192.168.1.57", name: "Pixel-8")], at: 2)
        let diff = try #require(service.getLastScanDiff())
        #expect(diff.scannedAt == time(1))
        #expect(diff.newDevices.map(\.displayName) == ["Pixel-8"])
    }

    @Test("A scheduler that went away stops listening")
    func unsubscribesWhenReleased() throws {
        var service: ScanSchedulerService? = ScanSchedulerService(dispatcher: dispatcher)
        weak let released = service
        service = nil
        #expect(released == nil)
        try reconcile([router], at: 0)
        try reconcile([router, device("192.168.1.57", name: "Pixel-8")], at: 1)
    }

    @Test("getLastScanDiff is nil before first scan; scheduling sets isScanDue later")
    func scheduling() {
        let service = ScanSchedulerService(dispatcher: dispatcher)
        #expect(service.getLastScanDiff() == nil)
        #expect(!service.isScanDue)
        service.scheduleNextScan(interval: -1)
        #expect(service.isScanDue)
        service.scheduleNextScan(interval: 3600)
        #expect(!service.isScanDue)
    }
}
