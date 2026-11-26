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

    // MARK: Members (#594 PR2)

    @Test func eachInterfaceThatAnsweredANewerMacScanIsASighting() {
        let scan = now.addingTimeInterval(-60)
        func member(_ ip: String, mac: String? = nil, answered: Bool = true) -> MemberInfo {
            MemberInfo(
                id: UUID(), ipAddress: ip, macAddress: mac, lastSeen: answered ? scan : now.addingTimeInterval(-9000),
                answeredLatestScan: answered, scanTime: scan, scanAge: now.timeIntervalSince(scan)
            )
        }
        let members = [member("192.168.7.10", mac: "AA:BB:CC:00:00:10"), member("192.168.7.40"), member("192.168.7.41", answered: false)]
        let list = DeviceListPayload(devices: [DeviceInfo(
            ipAddress: "192.168.7.10", macAddress: "AA:BB:CC:00:00:10", hostname: "studio", isOnline: true, members: members, isDeviceOnline: true
        )])
        func sightings(ownLastScan: Date?) -> [String] {
            DeviceDiscoveryService.companionSightings(
                list: list, receivedAt: now, macConnected: true, now: now, includes: { $0.hasPrefix("192.168.7.") }, profileID: nil,
                ownLastScan: ownLastScan
            ).devices.map(\.ipAddress)
        }
        #expect(sightings(ownLastScan: nil) == ["192.168.7.10", "192.168.7.40"])
        #expect(sightings(ownLastScan: scan.addingTimeInterval(-1)) == ["192.168.7.10", "192.168.7.40"])
        #expect(sightings(ownLastScan: scan).isEmpty, "a Mac scan no newer than the phone's own adds nothing")
    }

    @Test("The Mac's scan is placed on the phone's clock by its age at sending, so clock skew doesn't count (#619)")
    func clockSkewDoesNotCount() {
        func sightings(macClockAhead skew: TimeInterval, scanAgeAtSend age: TimeInterval, ownLastScan: Date) -> [String] {
            let member = MemberInfo(
                id: UUID(), ipAddress: "192.168.7.40", macAddress: nil, lastSeen: now, answeredLatestScan: true,
                scanTime: now.addingTimeInterval(skew - age), scanAge: age
            )
            let list = DeviceListPayload(devices: [DeviceInfo(
                ipAddress: "192.168.7.40", macAddress: "", hostname: "studio", isOnline: true, members: [member], isDeviceOnline: true
            )])
            return DeviceDiscoveryService.companionSightings(
                list: list, receivedAt: now, macConnected: true, now: now, includes: { _ in true }, profileID: nil, ownLastScan: ownLastScan
            ).devices.map(\.ipAddress)
        }
        // The Mac's clock runs 10 minutes fast: its scan a minute ago is older than the phone's 30 s ago.
        #expect(sightings(macClockAhead: 600, scanAgeAtSend: 60, ownLastScan: now.addingTimeInterval(-30)).isEmpty)
        // 10 minutes slow: its scan a minute ago is newer than the phone's two minutes ago.
        #expect(sightings(macClockAhead: -600, scanAgeAtSend: 60, ownLastScan: now.addingTimeInterval(-120)) == ["192.168.7.40"])
        // A negative age is a scan at sending, not one in the phone's future.
        #expect(sightings(macClockAhead: 0, scanAgeAtSend: -3600, ownLastScan: now.addingTimeInterval(-1)) == ["192.168.7.40"])
        #expect(sightings(macClockAhead: 0, scanAgeAtSend: -3600, ownLastScan: now.addingTimeInterval(1)).isEmpty)
    }

    @Test func oldAndNewPayloadsDecodeBothWays() throws {
        // A Mac before #594 PR2 sends no members: a new phone reads nil.
        let old = #"{"devices":[{"id":"\#(UUID().uuidString)","ipAddress":"192.168.7.60","macAddress":"","hostname":"tv","deviceType":"tv","isOnline":true}]}"#
        let decoded = try JSONDecoder().decode(DeviceListPayload.self, from: Data(old.utf8))
        #expect(decoded.devices.first?.members == nil && decoded.devices.first?.isDeviceOnline == nil)
        // A phone before #594 PR2 reads a new Mac's list: the extra keys are ignored.
        struct LegacyDeviceInfo: Decodable {
            let id: UUID, ipAddress: String, macAddress: String, hostname: String?, deviceType: String, isOnline: Bool
        }
        struct LegacyList: Decodable {
            let devices: [LegacyDeviceInfo]
        }
        let member = MemberInfo(id: UUID(), ipAddress: "192.168.7.40", macAddress: nil, lastSeen: now, answeredLatestScan: true, scanTime: now)
        let new = try JSONEncoder().encode(DeviceListPayload(devices: [DeviceInfo(
            ipAddress: "192.168.7.10", macAddress: "", hostname: "studio", isOnline: true, members: [member], isDeviceOnline: true
        )]))
        #expect(try JSONDecoder().decode(LegacyList.self, from: new).devices.map(\.ipAddress) == ["192.168.7.10"])
        #expect(try JSONDecoder().decode(DeviceListPayload.self, from: new).devices.first?.members == [member])
    }
}
