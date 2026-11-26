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

    /// #585 review 10: a list that carries `network` is an inventory Mac's, whatever the heartbeat
    /// said yet. It never joins the phone's own scan (that would save its devices); its answers
    /// refresh existing rows separately (`inventorySightings`).
    @Test func anInventoryListNeverJoinsThePhonesScanEvenBeforeTheHeartbeat() {
        let inventory = DeviceListPayload(
            devices: list.devices, network: InventoryNetwork(subnet: "192.168.7.0/24", gatewayIP: "192.168.7.1", name: nil, scanAge: 10)
        )
        let result = DeviceDiscoveryService.companionSightings(
            list: inventory, receivedAt: now.addingTimeInterval(-30), macConnected: true, now: now,
            includes: { $0.hasPrefix("192.168.7.") }, profileID: nil
        )
        #expect(result.devices.isEmpty)
        #expect(!result.fresh)
    }

    static let profile = NetworkProfile(
        interfaceName: "en0", ipAddress: "192.168.7.100",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80700, broadcastAddress: 0xC0A807FF, interfaceAddress: 0xC0A80764, netmask: 0xFFFFFF00
        ),
        connectionType: .wifi
    )

    func inventory(scanAge: TimeInterval = 10, answered: Bool = true) -> DeviceListPayload {
        let member = MemberInfo(
            id: UUID(), ipAddress: "192.168.7.60", macAddress: "AA:BB:CC:00:00:60", lastSeen: now, answeredLatestScan: answered,
            scanTime: now, scanAge: scanAge, isPrimary: true
        )
        return DeviceListPayload(
            devices: [DeviceInfo(
                ipAddress: "192.168.7.60", macAddress: "AA:BB:CC:00:00:60", hostname: "tv", isOnline: answered, members: [member],
                isDeviceOnline: true
            )],
            network: InventoryNetwork(subnet: "192.168.7.0/24", gatewayIP: "192.168.7.1", name: nil, scanAge: scanAge)
        )
    }

    func inventorySightings(_ list: DeviceListPayload, link: CompanionLinkPath? = CompanionLinkPath(remoteAddress: "192.168.7.2", interface: .wifi),
                            gateway: String? = "192.168.7.1", ownLastScan: Date? = nil) -> [String] {
        let availability = MacInventory.availability(
            list: list, receivedAt: now, link: link, phone: PhoneNetwork(profile: Self.profile, gatewayIP: gateway), viewing: Self.profile.id,
            presence: PresenceSnapshot(lastScans: [:], now: now)
        )
        return DeviceDiscoveryService.inventorySightings(
            list: list, availability: availability, receivedAt: now, profileID: Self.profile.id, ownLastScan: ownLastScan
        ).map(\.ipAddress)
    }

    @Test func aLiveInventoryGivesItsAnswersAsSightings() {
        #expect(inventorySightings(inventory()) == ["192.168.7.60"])
        // Missed the Mac's latest scan: no answer to give, even while the Mac shows it online within
        // its grace (#598: a grace-online member is never a fresh sighting).
        #expect(inventorySightings(inventory(answered: false)).isEmpty)
        // The Mac's scan is older than the phone's own: no newer answer (#619).
        #expect(inventorySightings(inventory(scanAge: 60), ownLastScan: now.addingTimeInterval(-30)).isEmpty)
    }

    @Test func anInventoryThatIsntLiveGivesNothing() {
        #expect(inventorySightings(inventory(), link: CompanionLinkPath(remoteAddress: "192.168.7.2", interface: .other)).isEmpty)
        #expect(inventorySightings(inventory(), gateway: "192.168.7.254").isEmpty)
        #expect(inventorySightings(inventory(scanAge: -1)).isEmpty)
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
        func sightings(macClockAhead skew: TimeInterval, scanAgeAtSend age: TimeInterval, ownLastScan: Date?) -> [String] {
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
        // A negative, non-finite or absurd age is rejected, not read as a scan at sending (#585 review):
        // a Mac whose clock went back would otherwise have its old answers renewed by every list.
        #expect(sightings(macClockAhead: 0, scanAgeAtSend: -3600, ownLastScan: now.addingTimeInterval(-1)).isEmpty)
        #expect(sightings(macClockAhead: 0, scanAgeAtSend: -3600, ownLastScan: nil).isEmpty)
        #expect(sightings(macClockAhead: 0, scanAgeAtSend: 1e300, ownLastScan: nil).isEmpty)
    }

    @Test("Only the primary interface's sighting carries the device's name, so a secondary one without a MAC matches its own row (#619)")
    @MainActor
    func secondaryInterfaceSightingHasNoBorrowedName() throws {
        let home = UUID()
        let primary = MemberInfo(
            id: UUID(), ipAddress: "192.168.7.10", macAddress: "AA:BB:CC:00:00:10", lastSeen: now, answeredLatestScan: true,
            scanTime: now, scanAge: 0, isPrimary: true
        )
        let secondary = MemberInfo(
            id: UUID(), ipAddress: "192.168.7.40", macAddress: nil, lastSeen: now, answeredLatestScan: true, scanTime: now, scanAge: 0,
            isPrimary: false
        )
        let list = DeviceListPayload(devices: [DeviceInfo(
            ipAddress: "192.168.7.10", macAddress: "AA:BB:CC:00:00:10", hostname: "studio", isOnline: true,
            members: [primary, secondary], isDeviceOnline: true
        )])
        let sightings = DeviceDiscoveryService.companionSightings(
            list: list, receivedAt: now, macConnected: true, now: now, includes: { _ in true }, profileID: home
        ).devices
        #expect(sightings.map(\.hostname) == ["studio", nil])

        // The phone already has the Wi-Fi interface as its own row, named by its own scan.
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let wifi = LocalDevice(ipAddress: "192.168.7.40", macAddress: "", hostname: "studio-wifi", networkProfileID: home)
        wifi.lastSeen = now.addingTimeInterval(-600)
        context.insert(wifi)
        try context.save()
        let suite = "CompanionSecondary.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = try ScanReconciler(context: context, history: ScanHistory(defaults: defaults))
            .reconcile(sightings, networkProfileID: home, scanDate: now, now: now)
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>()).filter { $0.ipAddress == "192.168.7.40" }
        #expect(rows.map(\.id) == [wifi.id], "the sighting is the phone's row, not a duplicate")
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
