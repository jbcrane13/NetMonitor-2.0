import Foundation
import NetMonitorCore
import NetworkScanKit
import Testing
@testable import NetMonitor_iOS

/// #585: while the connected Mac's inventory is live, the device list shows each device's state
/// from the Mac with that source, the phone's own sighting apart from it, and devices only the Mac
/// knows (shown, never saved). Without it the list is the phone's own, as before.
@Suite("SavedDeviceList with the Mac's inventory")
@MainActor
struct SavedDeviceListMacInventoryTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let home = UUID()
    private static let subnet = "192.168.77.0/24"

    private func row(_ ip: String, mac: String = "", status: DeviceStatus = .online, lastSeen: Date) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: "host-\(ip)", status: status, networkProfileID: home)
        row.lastSeen = lastSeen
        return row
    }

    private func inventory(_ devices: [DeviceInfo]) -> MacInventory.Availability {
        MacInventory.availability(
            list: DeviceListPayload(
                devices: devices, network: InventoryNetwork(subnet: Self.subnet, gatewayIP: nil, name: "Home", scanAge: 60)
            ),
            receivedAt: now, connected: true, offersInventory: true, subnet: Self.subnet, now: now
        )
    }

    private func macDevice(_ ip: String, name: String, online: Bool) -> DeviceInfo {
        DeviceInfo(ipAddress: ip, macAddress: "", hostname: name, isOnline: online, isDeviceOnline: online, lastSeenAge: 120)
    }

    /// The phone last scanned an hour ago: on its own it can't say the device is online now.
    private var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: now - 3600], now: now)
    }

    @Test func aDeviceBothKnowShowsTheMacsStateAndThePhonesSightingApart() throws {
        let tv = row("192.168.77.20", lastSeen: now - 3600)
        let list = SavedDeviceList(
            saved: [tv], network: home, sort: .ip, showPast: false, presence: presence,
            inventory: inventory([macDevice("192.168.77.20", name: "tv", online: true)])
        )
        guard case .saved(let device)? = list.entries.first else {
            Issue.record("Expected the saved TV")
            return
        }
        #expect(list.freshness(of: device) == .online)
        #expect(list.statusText(device) == "Online · from your Mac · last seen 2 min ago")
        #expect(list.phoneSightingText(device)?.hasPrefix("Seen by this iPhone at ") == true)
        #expect(list.onlineCount == 1)
        #expect(list.sourceText == "From your Mac · scanned 1 min ago")
    }

    /// The phone measured a latency, but the Mac has the device offline: no latency beside "Offline".
    @Test func noLatencyBesideTheMacsOffline() throws {
        let tv = row("192.168.77.20", lastSeen: now)
        tv.lastLatency = 12
        let phoneScan = PresenceSnapshot(lastScans: [home: now], now: now)
        let list = SavedDeviceList(
            saved: [tv], network: home, sort: .ip, showPast: false, presence: phoneScan,
            inventory: inventory([macDevice("192.168.77.20", name: "tv", online: false)])
        )
        let device = try #require(DeviceGroups.project([tv]).first)
        #expect(list.freshness(of: device) == .offline)
        #expect(list.latencyText(device) == nil)
    }

    @Test func aDeviceOnlyThePhoneKnowsKeepsItsOwnState() throws {
        let printer = row("192.168.77.30", lastSeen: now - 3600)
        let list = SavedDeviceList(
            saved: [printer], network: home, sort: .ip, showPast: false, presence: presence,
            inventory: inventory([macDevice("192.168.77.20", name: "tv", online: true)])
        )
        let device = try #require(list.entries.compactMap { entry -> DeviceProjection? in
            if case .saved(let device) = entry {
                device
            } else {
                nil
            }
        }.first)
        #expect(list.freshness(of: device) == .notCheckedRecently)
        #expect(list.statusText(device) == presence.statusText(device))
        #expect(list.phoneSightingText(device) != nil)
    }

    @Test func aDeviceOnlyTheMacKnowsIsListedNotSaved() {
        let list = SavedDeviceList(
            saved: [], network: home, sort: .ip, showPast: false, presence: presence,
            inventory: inventory([macDevice("192.168.77.50", name: "doorbell", online: true)])
        )
        guard case .mac(let record)? = list.entries.first else {
            Issue.record("Expected the Mac's doorbell: \(list.entries.map(\.id))")
            return
        }
        #expect(record.name == "doorbell")
        #expect(list.entries.first?.destination == nil)
        #expect(list.onlineCount == 1)
    }

    @Test func withoutTheInventoryTheListIsThePhonesOwn() throws {
        let tv = row("192.168.77.20", lastSeen: now - 3600)
        let list = SavedDeviceList(saved: [tv], network: home, sort: .ip, showPast: false, presence: presence)
        guard case .saved(let device)? = list.entries.first else {
            Issue.record("Expected the saved TV")
            return
        }
        #expect(list.entries.count == 1)
        #expect(list.freshness(of: device) == .notCheckedRecently)
        #expect(list.statusText(device) == presence.statusText(device))
        #expect(list.phoneSightingText(device) == nil)
        #expect(list.sourceText == nil)
    }

    // MARK: - Device detail agrees with the list

    /// A row saved without a network is listed with the current network, so detail looks the Mac's
    /// record up there too, among the same rows.
    @Test func detailFindsTheSameRecordAsTheList() throws {
        let unfiled = LocalDevice(ipAddress: "192.168.77.20", macAddress: "", hostname: "tv")
        let rows = [unfiled, row("192.168.77.30", lastSeen: now)]
        let availability = inventory([macDevice("192.168.77.20", name: "tv", online: true)])
        let list = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence, inventory: availability)
        let device = try #require(DeviceGroups.project([unfiled]).first)
        #expect(list.macRecord(for: device)?.name == "tv")
        #expect(MacConnectionService.macRecord(of: device, availability: availability, rows: rows)?.name == "tv")
    }

    @Test func detailUsesTheRowsNetworkOrTheCurrentOneForRowsWithout() throws {
        let local = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.77.100",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
            ),
            connectionType: .wifi
        )
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: "test.inventory.\(UUID().uuidString)")!
        let service = MacConnectionService(
            insightClient: CompanionInsightClient(send: { _ in false }),
            networkProfileManager: NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [local] }),
            macStore: PairedMacStore(backing: InMemoryCompanionSecretStore()), defaults: defaults
        )
        #expect(service.profile(for: local.id)?.subnetCIDR == "192.168.77.0/24")
        #expect(service.profile(for: nil)?.id == local.id)
        #expect(service.profile(for: UUID()) == nil)
    }
}
