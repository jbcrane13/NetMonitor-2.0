import Testing
import Foundation
import NetworkScanKit
import SwiftData
@testable import NetMonitorCore

/// The paired Mac's device list counts as devices answering now only while the Mac is connected and
/// the list is recent (#598); otherwise it adds cached sightings, which never count as answers.
@Suite("Companion sightings")
struct CompanionSightingsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let home = UUID()
    let list = DeviceListPayload(devices: [
        DeviceInfo(ipAddress: "192.168.7.60", macAddress: "AA:BB:CC:00:00:60", hostname: "tv", vendor: nil, deviceType: "tv", isOnline: true),
        DeviceInfo(ipAddress: "192.168.7.61", macAddress: "", hostname: "gone", vendor: nil, deviceType: "unknown", isOnline: false),
        DeviceInfo(ipAddress: "10.0.0.9", macAddress: "", hostname: "elsewhere", vendor: nil, deviceType: "unknown", isOnline: true)
    ])

    func sightings(receivedAt: Date?, connected: Bool) -> (devices: [DiscoveredDevice], fresh: Bool) {
        DeviceDiscoveryService.companionSightings(
            list: list, receivedAt: receivedAt, macConnected: connected, now: now,
            includes: { $0.hasPrefix("192.168.7.") }, profileID: nil
        )
    }

    @Test func aRecentListFromAConnectedMacIsFresh() {
        let result = sightings(receivedAt: now.addingTimeInterval(-30), connected: true)
        #expect(result.fresh)
        // Only the online devices on the scanned network.
        #expect(result.devices.map(\.ipAddress) == ["192.168.7.60"])
    }

    @Test func aListFromADisconnectedMacIsStale() {
        #expect(!sightings(receivedAt: now.addingTimeInterval(-30), connected: false).fresh)
        // A dropped link clears the receive time.
        #expect(!sightings(receivedAt: nil, connected: true).fresh)
    }

    @Test func aListOlderThanTheBoundIsStale() {
        let old = now.addingTimeInterval(-DeviceDiscoveryService.companionListFreshness)
        #expect(!sightings(receivedAt: old, connected: true).fresh)
        #expect(DeviceDiscoveryService.companionListFreshness == 120)
    }

    @Test func aFreshListIsMergedAndAStaleOneIsNot() async {
        let merged = ScanAccumulator()
        await DeviceDiscoveryService.mergeCompanion(sightings(receivedAt: now.addingTimeInterval(-30), connected: true), into: merged)
        #expect(await merged.snapshot().map(\.ipAddress) == ["192.168.7.60"])

        let dropped = ScanAccumulator()
        await DeviceDiscoveryService.mergeCompanion(sightings(receivedAt: nil, connected: false), into: dropped)
        #expect(await dropped.snapshot().isEmpty)
    }

    /// Codex on ebceade6: DHCP gave Alice's old address to Bob. The phone sees Bob there without a
    /// MAC; the disconnected Mac's stale list still has Alice there with her MAC. Alice's MAC and
    /// name never reach Bob, so her row isn't marked online and her name and notes stay hers.
    @MainActor
    @Test func aStaleListNeverLendsItsIdentityToALiveObservation() async throws {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "bob-tv", vendor: nil, macAddress: nil, latency: 4, discoveredAt: now,
            source: .local, networkProfileID: home
        ))
        let alicesList = DeviceListPayload(devices: [DeviceInfo(
            ipAddress: "192.168.7.20", macAddress: "AA:BB:CC:00:00:20", hostname: "alice-iphone", vendor: "Apple", isOnline: true
        )])
        let stale = DeviceDiscoveryService.companionSightings(
            list: alicesList, receivedAt: nil, macConnected: false, now: now, includes: { _ in true }, profileID: home
        )
        await DeviceDiscoveryService.mergeCompanion(stale, into: accumulator)
        let scan = await accumulator.snapshot()
        #expect(scan.count == 1)
        #expect(scan.first?.macAddress == nil)
        #expect(scan.first?.hostname == "bob-tv")
        #expect(scan.first?.vendor == nil)

        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let alice = LocalDevice(ipAddress: "192.168.7.20", macAddress: "AA:BB:CC:00:00:20", hostname: "alice-iphone",
                                status: .offline, networkProfileID: home)
        alice.notes = "Alice"
        alice.lastSeen = now.addingTimeInterval(-3 * 86400)
        context.insert(alice)
        let suite = "CompanionSightingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try ScanReconciler(context: context, history: ScanHistory(defaults: defaults))
            .reconcile(scan, networkProfileID: home, scanDate: now, now: now)

        #expect(alice.status == .offline)
        #expect(alice.notes == "Alice")
        #expect(alice.hostname == "alice-iphone")
        let bob = try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first { $0.id != alice.id })
        #expect(bob.hostname == "bob-tv")
        #expect(bob.macAddress.isEmpty)
        #expect(bob.notes == nil)
    }
}
