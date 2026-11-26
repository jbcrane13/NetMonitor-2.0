import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// The connected Mac's inventory as the phone shows it (#585): live only while the link is up, the
/// Mac advertised `inventory.v1`, the list covers the phone's network and the Mac's scan is recent
/// on the phone's clock. Records are found by MAC, else looked up by address; nothing is created.
@Suite("Mac inventory")
struct MacInventoryTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let subnet = "192.168.77.0/24"

    static func device(
        _ ip: String, mac: String = "", name: String? = nil, online: Bool = true, lastSeenAge: TimeInterval? = 30,
        lastChangedAge: TimeInterval? = nil, identity: DeviceIdentity? = nil
    ) -> DeviceInfo {
        DeviceInfo(
            ipAddress: ip, macAddress: mac, hostname: name, vendor: nil, isOnline: online, isDeviceOnline: online,
            lastSeenAge: lastSeenAge, lastChangedAge: lastChangedAge, identity: identity.map(InventoryIdentity.init)
        )
    }

    static func list(_ devices: [DeviceInfo], subnet: String = subnet, scanAge: TimeInterval? = 60) -> DeviceListPayload {
        DeviceListPayload(devices: devices, network: InventoryNetwork(subnet: subnet, gatewayIP: nil, name: "Home", scanAge: scanAge))
    }

    static func availability(
        _ list: DeviceListPayload?, receivedAt: Date? = now, connected: Bool = true, offersInventory: Bool = true,
        subnet: String? = subnet, now: Date = now
    ) -> MacInventory.Availability {
        MacInventory.availability(
            list: list, receivedAt: receivedAt, connected: connected, offersInventory: offersInventory, subnet: subnet, now: now
        )
    }

    static func live(_ list: DeviceListPayload) throws -> MacInventory {
        guard case .live(let inventory) = availability(list) else {
            throw Unavailable()
        }
        return inventory
    }

    struct Unavailable: Error {}

    static func row(_ ip: String, mac: String = "") -> DeviceProjection {
        DeviceGroups.project([LocalDevice(ipAddress: ip, macAddress: mac)])[0]
    }

    // MARK: - Liveness

    @Test func liveWithTheMacScanPlacedOnThePhonesClock() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20")], scanAge: 120))
        #expect(inventory.scanTime == Self.now.addingTimeInterval(-120))
        #expect(inventory.sourceText(now: Self.now.addingTimeInterval(60)) == "From your Mac · scanned 3 min ago")
    }

    @Test func noInventoryWithoutTheLinkTheCapabilityOrAList() {
        let list = Self.list([Self.device("192.168.77.20")])
        #expect(Self.availability(list, connected: false) == .unavailable)
        #expect(Self.availability(list, offersInventory: false) == .unavailable)
        // A link drop clears the receive time (#598): the list left over is no evidence.
        #expect(Self.availability(list, receivedAt: nil) == .unavailable)
        #expect(Self.availability(nil) == .unavailable)
        // A list from a Mac before inventory.v1 has no network or scan age.
        #expect(Self.availability(DeviceListPayload(devices: [Self.device("192.168.77.20")])) == .unavailable)
    }

    @Test func anOldMacScanFallsBackToThePhone() {
        let list = Self.list([Self.device("192.168.77.20")], scanAge: 60)
        // Grace is 15 minutes: the Mac's scan is 16 minutes old by now.
        #expect(Self.availability(list, now: Self.now.addingTimeInterval(15 * 60)) == .unavailable)
    }

    @Test func anotherNetworkIsNamedNotShown() {
        let list = Self.list([Self.device("10.0.0.20")], subnet: "10.0.0.0/24")
        #expect(Self.availability(list) == .otherNetwork(name: "Home"))
    }

    // MARK: - Records

    @Test func recordStatesAndTimesComeFromTheMac() throws {
        let inventory = try Self.live(Self.list([
            Self.device("192.168.77.20", name: "speaker", online: true, lastSeenAge: 90, lastChangedAge: 7200),
            Self.device("192.168.77.21", name: "printer", online: false, lastSeenAge: 4000)
        ]))
        let online = try #require(inventory.records.first { $0.ipAddress == "192.168.77.20" })
        #expect(online.state == .online)
        #expect(online.lastSeen == Self.now.addingTimeInterval(-90))
        #expect(online.lastChanged == Self.now.addingTimeInterval(-7200))
        #expect(online.name == "speaker")
        let offline = try #require(inventory.records.first { $0.ipAddress == "192.168.77.21" })
        #expect(offline.state == .offline)
        #expect(offline.lastChanged == nil)
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

    @Test func aRecordSaysItsStateComesFromTheMac() throws {
        let inventory = try Self.live(Self.list([
            Self.device("192.168.77.20", online: true, lastSeenAge: 120), Self.device("192.168.77.21", online: false, lastSeenAge: nil)
        ]))
        let seen = try #require(inventory.records.first { $0.ipAddress == "192.168.77.20" })
        #expect(seen.statusText(now: Self.now) == "Online · from your Mac · last seen 2 min ago")
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
        #expect(record.statusText(now: earlier) == "Online · from your Mac · last seen 2 min ago")
        #expect(record.changedText(now: earlier) == "Last changed 1 hour ago, from your Mac")
    }

    @Test func aRecordWithoutALoggedChangeSaysNothingOfIt() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", lastChangedAge: nil)]))
        #expect(try #require(inventory.records.first).changedText(now: Self.now) == nil)
    }

    @Test func thePhonesOwnSightingSaysWhenThisIPhoneSawIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US")
        // 2026-09-21 14:13:20 UTC.
        // The formatter puts a narrow no-break space before "PM".
        func text(_ date: Date) -> String {
            MacInventory.phoneSightingText(date, now: Self.now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(text(Self.now - 600) == "Seen by this iPhone at 2:03 PM")
        #expect(text(Self.now - 2 * 86400) == "Seen by this iPhone on Sep 19 at 2:13 PM")
    }

    // MARK: - Matching

    @Test func matchesByMACWhenBothHaveOne() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.99", mac: "02:AA:00:00:00:01", name: "laptop")]))
        let phone = Self.row("192.168.77.20", mac: "02:aa:00:00:00:01")
        let matches = inventory.matches([phone])
        #expect(matches.record(for: phone)?.name == "laptop")
        #expect(matches.macOnly.isEmpty)
    }

    @Test func looksUpByAddressWhenAMACIsMissing() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "tv")]))
        let phone = Self.row("192.168.77.20", mac: "02:AA:00:00:00:01")
        #expect(inventory.matches([phone]).record(for: phone)?.name == "tv")
    }

    @Test func differentMACsNeverMatchAtTheSameAddress() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", mac: "02:BB:00:00:00:02", name: "new tenant")]))
        let phone = Self.row("192.168.77.20", mac: "02:AA:00:00:00:01")
        let matches = inventory.matches([phone])
        #expect(matches.record(for: phone) == nil)
        #expect(matches.macOnly.map(\.name) == ["new tenant"])
    }

    @Test func anAmbiguousLookupGetsNoRecord() throws {
        // Two phone devices at one address (an old row and a new one): neither gets the Mac's record,
        // and it isn't listed as the Mac's alone either.
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "tv")]))
        let first = Self.row("192.168.77.20"), second = Self.row("192.168.77.20")
        let matches = inventory.matches([first, second])
        #expect(matches.record(for: first) == nil)
        #expect(matches.record(for: second) == nil)
        #expect(matches.macOnly.isEmpty)
    }

    @Test func aMACMatchWinsOverAnAddressLookup() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", mac: "02:AA:00:00:00:01", name: "laptop")]))
        let byMAC = Self.row("192.168.77.30", mac: "02:AA:00:00:00:01"), byAddress = Self.row("192.168.77.20")
        let matches = inventory.matches([byMAC, byAddress])
        #expect(matches.record(for: byMAC)?.name == "laptop")
        #expect(matches.record(for: byAddress) == nil)
    }

    @Test func devicesOnlyTheMacKnowsAreListedApart() throws {
        let inventory = try Self.live(Self.list([Self.device("192.168.77.20", name: "tv"), Self.device("192.168.77.50", name: "doorbell")]))
        let phone = Self.row("192.168.77.20"), phoneOnly = Self.row("192.168.77.60")
        let matches = inventory.matches([phone, phoneOnly])
        #expect(matches.macOnly.map(\.name) == ["doorbell"])
        #expect(matches.record(for: phoneOnly) == nil)
    }
}
