import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// The one value every iPhone surface reads while the Mac's inventory is live (#585 review 4, 6,
/// 8, 11): each saved device's Mac record, the devices only the Mac knows, which devices the
/// phone's own latest scan saw (and when), and one online count for the list, the dashboard and
/// the widget.
@Suite("Mac inventory overlay")
@MainActor
struct MacInventoryOverlayTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let network = UUID()
    let presence = PresenceSnapshot(lastScans: [network: now - 120], now: now)

    func availability(_ devices: [DeviceInfo]) -> MacInventory.Availability {
        let profile = NetworkProfile(
            id: Self.network, interfaceName: "en0", ipAddress: "192.168.77.100",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
            ),
            connectionType: .wifi, name: "Home", gatewayIP: "192.168.77.1", subnet: "192.168.77.0/24", isLocal: true, discoveryMethod: .auto
        )
        return MacInventory.availability(
            list: DeviceListPayload(
                devices: devices, network: InventoryNetwork(subnet: "192.168.77.0/24", gatewayIP: "192.168.77.254", name: nil, scanAge: 30)
            ),
            receivedAt: Self.now, connected: true, link: CompanionLinkPath(remoteAddress: "192.168.77.2", interface: .wifi),
            phone: PhoneNetwork(profile: profile, gatewayIP: "192.168.77.254"), viewing: Self.network, now: Self.now
        )
    }

    func mac(_ ip: String, mac: String = "", name: String, online: Bool = true) -> DeviceInfo {
        DeviceInfo(ipAddress: ip, macAddress: mac, hostname: name, isOnline: online, isDeviceOnline: online, lastSeenAge: 30)
    }

    func row(_ ip: String, mac: String = "", name: String, lastSeen: Date, status: DeviceStatus = .online) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: name, status: status, networkProfileID: Self.network)
        row.lastSeen = lastSeen
        return row
    }

    func scanned(_ ip: String, name: String) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: nil, latency: 3, discoveredAt: Self.now - 120, source: .local,
            networkProfileID: Self.network
        )
    }

    @Test func thePhonesSightingIsItsOwnLatestScansOnly() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: Self.now - 120)
        let lamp = row("192.168.77.21", name: "lamp", lastSeen: Self.now - 120)
        let overlay = MacInventoryOverlay.make(
            availability: availability([mac("192.168.77.20", name: "tv"), mac("192.168.77.21", name: "lamp")]),
            networkID: Self.network, rows: [tv, lamp], presence: presence,
            ownScan: OwnScan(date: Self.now - 120, devices: [scanned("192.168.77.20", name: "tv")])
        )
        let devices = DeviceGroups.project([tv, lamp])
        let tvDevice = try #require(devices.first { $0.ipAddress == "192.168.77.20" })
        let lampDevice = try #require(devices.first { $0.ipAddress == "192.168.77.21" })
        #expect(overlay.phoneSighting(for: tvDevice) == Self.now - 120)
        // Its last seen was stamped by the Mac's answer, not by the phone: no "Seen by this iPhone".
        #expect(overlay.phoneSighting(for: lampDevice) == nil)
    }

    @Test func aPastDeviceTheMacHasOnlineByMACIsShownAndCounted() throws {
        let printer = row("192.168.77.30", mac: "02:AA:00:00:00:30", name: "printer", lastSeen: Self.now - 9 * 86400, status: .offline)
        let overlay = MacInventoryOverlay.make(
            availability: availability([mac("192.168.77.30", mac: "02:AA:00:00:00:30", name: "printer")]),
            networkID: Self.network, rows: [printer], presence: presence, ownScan: nil
        )
        let device = try #require(DeviceGroups.project([printer]).first)
        #expect(presence.isPast(device))
        #expect(overlay.isShown(device, showPast: false, presence: presence))
        #expect(overlay.onlineCount(presence: presence) == 1)
    }

    @Test func oneOnlineCountForTheListTheDashboardAndTheWidget() {
        let tv = row("192.168.77.20", name: "tv", lastSeen: Self.now - 120)
        let nas = row("192.168.77.22", name: "nas", lastSeen: Self.now - 120, status: .offline)
        let overlay = MacInventoryOverlay.make(
            availability: availability([
                mac("192.168.77.20", name: "tv"), mac("192.168.77.22", name: "nas", online: false), mac("192.168.77.60", name: "doorbell")
            ]),
            networkID: Self.network, rows: [tv, nas], presence: presence, ownScan: nil
        )
        // The TV and the doorbell only the Mac knows are online; the NAS the Mac has offline isn't.
        #expect(overlay.onlineCount(presence: presence) == 2)
        #expect(overlay.macOnly.map(\.name) == ["doorbell"])
    }

    @Test func withoutALiveInventoryNothingIsOverlaid() throws {
        let tv = row("192.168.77.20", name: "tv", lastSeen: Self.now - 120)
        let overlay = MacInventoryOverlay.make(
            availability: .unavailable, networkID: Self.network, rows: [tv], presence: presence,
            ownScan: OwnScan(date: Self.now - 120, devices: [scanned("192.168.77.20", name: "tv")])
        )
        let device = try #require(DeviceGroups.project([tv]).first)
        #expect(overlay.inventory == nil)
        #expect(overlay.record(for: device) == nil)
        #expect(overlay.phoneSighting(for: device) == nil)
        #expect(overlay.macOnly.isEmpty)
    }
}
