import Foundation
import NetMonitorCore
import NetworkScanKit
import Testing
@testable import NetMonitor_iOS

/// #585: while the connected Mac's inventory is live for the list's network, the list shows each
/// device's state from the Mac with that source, "Seen by this iPhone" only where the phone's own
/// latest scan saw the device, the Mac's maker and model where the phone has none, devices only the
/// Mac knows (shown, never saved), and a phone-past device the Mac has online. Without it the list is
/// the phone's own.
@Suite("SavedDeviceList with the Mac's inventory")
@MainActor
struct SavedDeviceListMacInventoryTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let home = UUID()

    private func row(_ ip: String, mac: String = "", name: String, status: DeviceStatus = .online, lastSeen: Date) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: name, status: status, networkProfileID: home)
        row.lastSeen = lastSeen
        return row
    }

    private func availability(_ devices: [DeviceInfo]) -> MacInventory.Availability {
        let profile = NetworkProfile(
            id: home, interfaceName: "en0", ipAddress: "192.168.77.100",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
            ),
            connectionType: .wifi, name: "Home", gatewayIP: "192.168.77.1", subnet: "192.168.77.0/24", isLocal: true, discoveryMethod: .auto
        )
        return MacInventory.availability(
            list: DeviceListPayload(
                devices: devices, network: InventoryNetwork(subnet: "192.168.77.0/24", gatewayIP: "192.168.77.254", name: "Home", scanAge: 60)
            ),
            receivedAt: now, link: CompanionLinkPath(remoteAddress: "192.168.77.2", interface: .wifi),
            phone: PhoneNetwork(profile: profile, gatewayIP: "192.168.77.254"), viewing: home,
            presence: PresenceSnapshot(lastScans: [:], now: now)
        )
    }

    private func macDevice(
        _ ip: String, mac: String = "", name: String, online: Bool, identity: DeviceIdentity? = nil
    ) -> DeviceInfo {
        DeviceInfo(
            ipAddress: ip, macAddress: mac, hostname: name, isOnline: online, isDeviceOnline: online, lastSeenAge: 120,
            identity: identity.map(InventoryIdentity.init)
        )
    }

    /// The phone last scanned an hour ago: on its own it can't say the device is online now.
    private var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: now - 3600], now: now)
    }

    private func list(
        _ rows: [LocalDevice], mac: [DeviceInfo], ownScan: OwnScan? = nil, showPast: Bool = false
    ) -> (SavedDeviceList, MacInventoryOverlay) {
        let overlay = MacInventoryOverlay.make(availability: availability(mac), networkID: home, rows: rows, presence: presence, ownScan: ownScan)
        return (SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: showPast, presence: presence, overlay: overlay), overlay)
    }

    private func saved(_ list: SavedDeviceList) -> [DeviceProjection] {
        list.entries.compactMap { entry in
            if case .saved(let device) = entry {
                return device
            }
            return nil
        }
    }

    @Test func aDeviceBothKnowShowsTheMacsStateWithItsSource() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now - 600)
        let (list, overlay) = list([tv], mac: [macDevice("192.168.77.20", name: "tv", online: true)])
        let device = try #require(saved(list).first)
        #expect(list.freshness(of: device) == .online)
        #expect(list.statusText(device) == "Online · from your Mac · Last seen 2 min ago")
        #expect(list.sourceText == "From your Mac · scanned 1 min ago")
        // One number: the list's, the overlay's (the dashboard's and the widget's).
        #expect(list.onlineCount == 1)
        #expect(overlay.onlineCount(presence: presence) == list.onlineCount)
    }

    @Test func seenByThisIPhoneOnlyWhenItsOwnLatestScanSawTheDevice() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now - 3600)
        let lamp = row("192.168.77.21", name: "lamp", lastSeen: now - 3600)
        let scan = OwnScan(date: now - 3600, devices: [
            DiscoveredDevice(
                ipAddress: "192.168.77.20", hostname: "tv", vendor: nil, macAddress: nil, latency: 3, discoveredAt: now - 3600,
                source: .local, networkProfileID: home
            )
        ])
        let (list, _) = list(
            [tv, lamp], mac: [macDevice("192.168.77.20", name: "tv", online: true), macDevice("192.168.77.21", name: "lamp", online: true)],
            ownScan: scan
        )
        let devices = saved(list)
        let tvDevice = try #require(devices.first { $0.ipAddress == "192.168.77.20" })
        let lampDevice = try #require(devices.first { $0.ipAddress == "192.168.77.21" })
        #expect(list.phoneSightingText(tvDevice)?.hasPrefix("Seen by this iPhone") == true)
        #expect(list.phoneSightingText(lampDevice) == nil)
    }

    @Test func theMacsMakerAndModelShowWhenThePhoneHasNone() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now - 600)
        let identity = DeviceIdentity(maker: IdentityValue("Sonos", source: .upnp), model: IdentityValue("Era 100", source: .bonjour))
        let (list, _) = list([tv], mac: [macDevice("192.168.77.20", name: "tv", online: true, identity: identity)])
        let device = try #require(saved(list).first)
        #expect(list.macIdentityText(device) == "Sonos Era 100 · from your Mac")
        // Shown only: nothing is written onto the row.
        #expect(tv.maker == nil)
        #expect(tv.modelName == nil)
    }

    @Test func aDeviceOnlyTheMacKnowsIsListedNotSaved() {
        let (list, _) = list([], mac: [macDevice("192.168.77.50", name: "doorbell", online: true)])
        guard case .mac(let record)? = list.entries.first else {
            Issue.record("Expected the Mac's doorbell: \(list.entries.map(\.id))")
            return
        }
        #expect(record.name == "doorbell")
        #expect(list.entries.first?.destination == nil)
        #expect(list.onlineCount == 1)
    }

    @Test func aPhonePastDeviceTheMacHasOnlineIsShownAndCounted() throws {
        let printer = row("192.168.77.30", mac: "02:AA:00:00:00:30", name: "printer", status: .offline, lastSeen: now - 9 * 86400)
        let (list, _) = list([printer], mac: [macDevice("192.168.77.30", mac: "02:AA:00:00:00:30", name: "printer", online: true)])
        #expect(saved(list).map(\.ipAddress) == ["192.168.77.30"])
        #expect(list.pastCount == 0)
        #expect(list.onlineCount == 1)
    }

    /// The phone measured a latency, but the Mac has the device offline: no latency beside "Offline".
    @Test func noLatencyBesideTheMacsOffline() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now)
        tv.lastLatency = 12
        let phoneScan = PresenceSnapshot(lastScans: [home: now], now: now)
        let overlay = MacInventoryOverlay.make(
            availability: availability([macDevice("192.168.77.20", name: "tv", online: false)]), networkID: home, rows: [tv],
            presence: phoneScan, ownScan: nil
        )
        let list = SavedDeviceList(saved: [tv], network: home, sort: .ip, showPast: false, presence: phoneScan, overlay: overlay)
        let device = try #require(saved(list).first)
        #expect(list.freshness(of: device) == .offline)
        #expect(list.latencyText(device) == nil)
    }

    /// Devin on #624: a cached (unconfirmed) phone sighting at the Mac record's address shows the
    /// Mac's current status instead; a live phone sighting there is the phone's.
    @Test func aCachedPhoneSightingGivesWayToTheMacsRecord() {
        func found(cached: Bool) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: "192.168.77.50", hostname: "doorbell", vendor: nil, macAddress: nil, latency: nil, discoveredAt: now,
                source: .local, networkProfileID: home, isCached: cached
            )
        }
        let overlay = MacInventoryOverlay.make(
            availability: availability([macDevice("192.168.77.50", name: "doorbell", online: true)]), networkID: home, rows: [],
            presence: presence, ownScan: nil
        )
        let cached = SavedDeviceList(
            saved: [], live: [found(cached: true)], network: home, sort: .ip, showPast: false, presence: presence, overlay: overlay
        )
        #expect(cached.entries.map(\.id).allSatisfy { $0.hasPrefix("mac-") })
        #expect(cached.entries.count == 1)
        let live = SavedDeviceList(
            saved: [], live: [found(cached: false)], network: home, sort: .ip, showPast: false, presence: presence, overlay: overlay
        )
        #expect(live.entries.map(\.id).allSatisfy { $0.hasPrefix("found-") })
        #expect(live.entries.count == 1)
    }

    /// Devin on #624: a latency hidden beside the Mac's "Offline" doesn't sort the row first.
    @Test func aHiddenLatencyDoesNotSortARowFirst() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now)
        tv.lastLatency = 2
        let nas = row("192.168.77.30", name: "nas", lastSeen: now)
        nas.lastLatency = 40
        let phoneScan = PresenceSnapshot(lastScans: [home: now], now: now)
        let overlay = MacInventoryOverlay.make(
            availability: availability([
                macDevice("192.168.77.20", name: "tv", online: false), macDevice("192.168.77.30", name: "nas", online: true)
            ]),
            networkID: home, rows: [tv, nas], presence: phoneScan, ownScan: nil
        )
        let list = SavedDeviceList(saved: [tv, nas], network: home, sort: .latency, showPast: false, presence: phoneScan, overlay: overlay)
        #expect(list.entries.map(\.ipAddress) == ["192.168.77.30", "192.168.77.20"])
    }

    @Test func anotherNetworksOverlayIsIgnored() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now - 3600)
        let overlay = MacInventoryOverlay.make(
            availability: availability([macDevice("192.168.77.20", name: "tv", online: true)]), networkID: UUID(), rows: [tv],
            presence: presence, ownScan: nil
        )
        let list = SavedDeviceList(saved: [tv], network: home, sort: .ip, showPast: false, presence: presence, overlay: overlay)
        let device = try #require(saved(list).first)
        #expect(list.freshness(of: device) == .notCheckedRecently)
        #expect(list.sourceText == nil)
    }

    @Test func withoutTheInventoryTheListIsThePhonesOwn() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: now - 3600)
        let list = SavedDeviceList(saved: [tv], network: home, sort: .ip, showPast: false, presence: presence)
        let device = try #require(saved(list).first)
        #expect(list.entries.count == 1)
        #expect(list.freshness(of: device) == .notCheckedRecently)
        #expect(list.statusText(device) == presence.statusText(device))
        #expect(list.phoneSightingText(device) == nil)
        #expect(list.sourceText == nil)
    }
}
