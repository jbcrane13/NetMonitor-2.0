import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// The connected Mac's inventory as the phone shows it (#585): live only while the link is up and
/// on-link over Wi-Fi or Ethernet, the phone is on the network it is viewing now, that network's
/// subnet and routed gateway are the Mac's, and the Mac's scan is recent on the phone's clock.
/// Records match the phone's devices by the `PresenceMatch` rule; nothing is created.
@Suite("Mac inventory")
struct MacInventoryTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let gateway = "192.168.77.254"
    static let home = NetworkProfile(
        interfaceName: "en0", ipAddress: "192.168.77.100",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
        ),
        connectionType: .wifi
    )
    static let phone = PhoneNetwork(profile: home, gatewayIP: gateway)
    static let wifiLink = CompanionLinkPath(remoteAddress: "192.168.77.10", interface: .wifi)

    static func device(
        _ ip: String, mac: String = "", name: String? = nil, online: Bool = true, deviceOnline: Bool? = nil,
        lastSeenAge: TimeInterval? = 30, lastChangedAge: TimeInterval? = nil, identity: DeviceIdentity? = nil
    ) -> DeviceInfo {
        DeviceInfo(
            ipAddress: ip, macAddress: mac, hostname: name, vendor: nil, isOnline: online, isDeviceOnline: deviceOnline ?? online,
            lastSeenAge: lastSeenAge, lastChangedAge: lastChangedAge, identity: identity.map(InventoryIdentity.init)
        )
    }

    static func list(
        _ devices: [DeviceInfo], subnet: String? = "192.168.77.0/24", gateway: String? = gateway, scanAge: TimeInterval? = 60
    ) -> DeviceListPayload {
        DeviceListPayload(devices: devices, network: InventoryNetwork(subnet: subnet, gatewayIP: gateway, name: "Home", scanAge: scanAge))
    }

    static func availability(
        _ list: DeviceListPayload?, receivedAt: Date? = now, connected: Bool = true, link: CompanionLinkPath? = wifiLink,
        phone: PhoneNetwork? = phone, viewing: UUID? = home.id, now: Date = now
    ) -> MacInventory.Availability {
        MacInventory.availability(
            list: list, receivedAt: receivedAt, connected: connected, link: link, phone: phone, viewing: viewing, now: now
        )
    }

    static func live(_ list: DeviceListPayload) throws -> MacInventory {
        guard case .live(let inventory) = availability(list) else {
            throw Unavailable()
        }
        return inventory
    }

    struct Unavailable: Error {}

    static func row(_ ip: String, mac: String = "", name: String? = nil, lastSeen: Date = now) -> DeviceProjection {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: name)
        row.lastSeen = lastSeen
        return DeviceGroups.project([row])[0]
    }

    static func matches(_ inventory: MacInventory, _ devices: [DeviceProjection], past: Set<UUID> = []) -> MacInventory.Matches {
        inventory.matches(devices, now: now, window: DeviceGracePolicy().interval, previousScan: nil) { past.contains($0.id) }
    }

    // MARK: - Liveness

    @Test func liveWithTheMacScanPlacedOnThePhonesClock() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20")], scanAge: 120))
        #expect(inventory.scanTime == Self.now.addingTimeInterval(-120))
        #expect(inventory.sourceText(now: Self.now.addingTimeInterval(60)) == "From your Mac · scanned 3 min ago")
    }

    @Test func noInventoryWithoutTheLinkOrAList() {
        let list = Self.list([Self.device("192.168.77.20")])
        #expect(Self.availability(list, connected: false) == .unavailable)
        // A link drop clears the receive time (#598): the list left over is no evidence.
        #expect(Self.availability(list, receivedAt: nil) == .unavailable)
        #expect(Self.availability(nil) == .unavailable)
        // A list from a Mac before inventory.v1 has no network: its capability is the list's own.
        #expect(Self.availability(DeviceListPayload(devices: [Self.device("192.168.77.20")])) == .unavailable)
    }

    @Test func anOldMacScanFallsBackToThePhone() {
        let list = Self.list([Self.device("192.168.77.20")], scanAge: 60)
        // Grace is 15 minutes: the Mac's scan is 16 minutes old by now.
        #expect(Self.availability(list, now: Self.now.addingTimeInterval(15 * 60)) == .unavailable)
    }

    @Test func theGraceIsTheCallersPolicy() {
        let list = Self.list([Self.device("192.168.77.20")], scanAge: 60)
        let short = MacInventory.availability(
            list: list, receivedAt: Self.now, connected: true, link: Self.wifiLink, phone: Self.phone, viewing: Self.home.id,
            now: Self.now.addingTimeInterval(120), policy: DeviceGracePolicy(interval: 90)
        )
        #expect(short == .unavailable)
    }

    // MARK: - The phone is on that network, now

    @Test func anotherSubnetOrGatewayIsNamedNotShown() {
        #expect(Self.availability(Self.list([], subnet: "10.0.0.0/24")) == .otherNetwork(name: "Home"))
        // Two sites with the same CIDR, told apart by the routed gateway.
        #expect(Self.availability(Self.list([], gateway: "192.168.77.1")) == .otherNetwork(name: "Home"))
    }

    @Test func failsClosedWithoutTheNetworksIdentity() {
        // No routed gateway on either side, or no subnet from the Mac: unknown, not "same".
        #expect(Self.availability(Self.list([], gateway: nil)) == .unavailable)
        #expect(Self.availability(Self.list([]), phone: PhoneNetwork(profile: Self.home, gatewayIP: nil)) == .unavailable)
        #expect(Self.availability(Self.list([], subnet: nil)) == .unavailable)
        // Not on a network now (cellular, or Wi-Fi off).
        #expect(Self.availability(Self.list([]), phone: nil) == .unavailable)
    }

    @Test func viewingASavedProfileThatIsntTheCurrentNetworkShowsNothing() {
        // A selected "Office" profile with the same CIDR, viewed while at home.
        #expect(Self.availability(Self.list([]), viewing: UUID()) == .unavailable)
    }

    @Test func theLinkMustBeOnLinkOverWiFiOrEthernet() {
        let list = Self.list([Self.device("192.168.77.20")])
        func live(_ link: CompanionLinkPath?) -> Bool {
            if case .live = Self.availability(list, link: link) {
                return true
            }
            return false
        }
        #expect(live(CompanionLinkPath(remoteAddress: "192.168.77.10", interface: .wifi)))
        #expect(live(CompanionLinkPath(remoteAddress: "192.168.77.10", interface: .wiredEthernet)))
        // Bonjour often resolves the Mac to its scoped IPv6 link-local address: on-link by definition.
        #expect(live(CompanionLinkPath(remoteAddress: "fe80::1c2b:3aff:fe4d:5e6f%en0", interface: .wifi)))
        #expect(!live(CompanionLinkPath(remoteAddress: "192.168.77.10", interface: .cellular)))
        // A VPN tunnel is `.other`.
        #expect(!live(CompanionLinkPath(remoteAddress: "192.168.77.10", interface: .other)))
        #expect(!live(CompanionLinkPath(remoteAddress: "127.0.0.1", interface: .loopback)))
        // Routed from another site with the same CIDR: the Mac's address isn't on this link.
        #expect(!live(CompanionLinkPath(remoteAddress: "10.8.0.4", interface: .wifi)))
        #expect(!live(CompanionLinkPath(remoteAddress: "2001:db8::4", interface: .wifi)))
        #expect(!live(CompanionLinkPath(remoteAddress: nil, interface: .wifi)))
        #expect(!live(nil))
    }

    // MARK: - Wire numbers

    @Test func aNegativeOrAbsurdScanAgeIsRejected() {
        #expect(Self.availability(Self.list([], scanAge: -5)) == .unavailable)
        #expect(Self.availability(Self.list([], scanAge: 1e300)) == .unavailable)
        #expect(Self.availability(Self.list([], scanAge: .nan)) == .unavailable)
        #expect(Self.availability(Self.list([], scanAge: .infinity)) == .unavailable)
    }

    @Test func absurdDeviceAgesAreDroppedAndRenderSafely() throws {
        let inventory = try Self.live(Self.list([
            Self.device("192.168.77.20", lastSeenAge: 1e300, lastChangedAge: -3),
            Self.device("192.168.77.21", lastSeenAge: .nan, lastChangedAge: .infinity)
        ]))
        for record in inventory.records {
            #expect(record.lastSeen == nil)
            #expect(record.lastChanged == nil)
            #expect(record.statusText(now: Self.now) == "Online · from your Mac")
            #expect(record.changedText(now: Self.now) == nil)
        }
    }

    @Test func relativeTimeIsSafeForAnyInterval() {
        #expect(PresenceFreshness.relativeText(since: .distantPast, now: Self.now).hasSuffix("days ago"))
        #expect(PresenceFreshness.relativeText(since: Date(timeIntervalSince1970: -1e300), now: Self.now).hasSuffix("days ago"))
        #expect(PresenceFreshness.relativeText(since: Date(timeIntervalSince1970: .nan), now: Self.now) == "just now")
    }

    // MARK: - Records

    @Test func onlineOnlyWhenTheDeviceAnsweredTheMacsLatestScan() throws {
        let inventory = try Self.live(Self.list([
            Self.device("192.168.77.20", online: true, lastSeenAge: 90, lastChangedAge: 7200),
            // Missed the Mac's latest scan but still inside the Mac's grace: not "Online".
            Self.device("192.168.77.21", online: false, deviceOnline: true, lastSeenAge: 400),
            Self.device("192.168.77.22", online: false, deviceOnline: false, lastSeenAge: 4000)
        ]))
        func record(_ ip: String) -> MacInventory.Record? {
            inventory.records.first { $0.ipAddress == ip }
        }
        #expect(record("192.168.77.20")?.state == .online)
        #expect(record("192.168.77.20")?.lastSeen == Self.now.addingTimeInterval(-90))
        #expect(record("192.168.77.20")?.lastChanged == Self.now.addingTimeInterval(-7200))
        #expect(record("192.168.77.21")?.state == .notCheckedRecently)
        #expect(record("192.168.77.22")?.state == .offline)
    }

    @Test func recordCarriesTheMacsMakerAndModel() throws {
        let identity = DeviceIdentity(
            maker: IdentityValue("Sonos", source: .upnp), model: IdentityValue("Era 100", source: .bonjour),
            friendlyName: IdentityValue("Kitchen", source: .upnp)
        )
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", identity: identity)]))
        let record = try #require(inventory.records.first)
        #expect(record.name == "Kitchen")
        #expect(record.maker == "Sonos")
        #expect(record.model == "Era 100")
    }

    // MARK: - Wording

    @Test func aRecordSaysItsStateComesFromTheMacInTheAppsWording() throws {
        let inventory = try Self.live(Self.list([
            Self.device("192.168.77.20", online: true, lastSeenAge: 120),
            Self.device("192.168.77.21", online: false, lastSeenAge: nil)
        ]))
        let seen = try #require(inventory.records.first { $0.ipAddress == "192.168.77.20" })
        #expect(seen.statusText(now: Self.now) == "Online · from your Mac · Last seen 2 min ago")
        #expect(seen.accessibilityText(now: Self.now) == "Online, from your Mac, last seen 2 min ago")
        let unseen = try #require(inventory.records.first { $0.ipAddress == "192.168.77.21" })
        #expect(unseen.statusText(now: Self.now) == "Offline · from your Mac")
    }

    /// The phone's presence clock ticks once a minute, so `now` can be a little before the list
    /// arrived; the Mac's ages are never read as younger than they were when sent.
    @Test func agesNeverReadYoungerThanSent() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", lastSeenAge: 120, lastChangedAge: 3600)], scanAge: 60))
        let earlier = Self.now.addingTimeInterval(-50)
        #expect(inventory.sourceText(now: earlier) == "From your Mac · scanned 1 min ago")
        let record = try #require(inventory.records.first)
        #expect(record.statusText(now: earlier) == "Online · from your Mac · Last seen 2 min ago")
        #expect(record.changedText(now: earlier) == "Last changed 1 hour ago, from your Mac")
    }

    @Test func thePhonesOwnSightingSaysWhenThisIPhoneSawIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US")
        // 2026-09-21 14:13:20 UTC. The formatter puts a narrow no-break space before "PM".
        func text(_ date: Date) -> String {
            MacInventory.phoneSightingText(date, now: Self.now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(text(Self.now - 600) == "Seen by this iPhone at 2:03 PM")
        #expect(text(Self.now - 2 * 86400) == "Seen by this iPhone on Sep 19 at 2:13 PM")
    }

    // MARK: - Matching (the PresenceMatch rule)

    @Test func matchesByMACWhenBothHaveOne() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.99", mac: "02:AA:00:00:00:01", name: "laptop")]))
        let phone = Self.row("192.168.77.20", mac: "02:aa:00:00:00:01", name: "laptop")
        let matches = Self.matches(inventory, [phone])
        #expect(matches.record(for: phone)?.name == "laptop")
        #expect(matches.macOnly.isEmpty)
    }

    @Test func differentMACsNeverMatchAtTheSameAddress() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", mac: "02:BB:00:00:00:02", name: "new-tenant")]))
        let phone = Self.row("192.168.77.20", mac: "02:AA:00:00:00:01")
        let matches = Self.matches(inventory, [phone])
        #expect(matches.record(for: phone) == nil)
        #expect(matches.macOnly.map(\.name) == ["new-tenant"])
    }

    /// The lead's case: Dad's iPad was at .20 hours ago; a guest TV has .20 now, and the Mac reads no
    /// MACs. Two different names are two devices.
    @Test func anOldRowAndANewDeviceAtTheSameAddressStayApart() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "guest-tv")]))
        let iPad = Self.row("192.168.77.20", name: "dads-ipad", lastSeen: Self.now - 6 * 3600)
        let matches = Self.matches(inventory, [iPad])
        #expect(matches.record(for: iPad) == nil)
        #expect(matches.macOnly.map(\.name) == ["guest-tv"])
    }

    @Test func anUnknownNameMatchesOnlyARowSeenThereWithinGrace() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: nil)]))
        let recent = Self.row("192.168.77.20", lastSeen: Self.now - 300)
        #expect(Self.matches(inventory, [recent]).record(for: recent) != nil)
        let old = Self.row("192.168.77.20", lastSeen: Self.now - 6 * 3600)
        let matches = Self.matches(inventory, [old])
        #expect(matches.record(for: old) == nil)
        #expect(matches.macOnly.count == 1)
    }

    @Test func aPastRowIsNeverMatchedByAddress() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "printer")]))
        let past = Self.row("192.168.77.20", name: "printer", lastSeen: Self.now - 8 * 86400)
        #expect(Self.matches(inventory, [past], past: [past.id]).record(for: past) == nil)
        // By MAC it is the same device, past or not.
        let macInventory = try Self.live(Self.list([Self.device("192.168.77.20", mac: "02:AA:00:00:00:09", name: "printer")]))
        let pastWithMAC = Self.row("192.168.77.20", mac: "02:AA:00:00:00:09", name: "printer", lastSeen: Self.now - 8 * 86400)
        #expect(Self.matches(macInventory, [pastWithMAC], past: [pastWithMAC.id]).record(for: pastWithMAC) != nil)
    }

    @Test func devicesOnlyTheMacKnowsAreListedApart() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "tv"), Self.device("192.168.77.50", name: "doorbell")]))
        let phone = Self.row("192.168.77.20", name: "tv"), phoneOnly = Self.row("192.168.77.60", name: "nas")
        let matches = Self.matches(inventory, [phone, phoneOnly])
        #expect(matches.record(for: phone)?.name == "tv")
        #expect(matches.macOnly.map(\.name) == ["doorbell"])
        #expect(matches.record(for: phoneOnly) == nil)
    }
}
