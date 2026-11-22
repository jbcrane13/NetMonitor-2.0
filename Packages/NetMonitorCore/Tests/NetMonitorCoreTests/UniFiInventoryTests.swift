import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// UniFi Network integration API responses (shapes from Network 11.1, 2026-11-21) and how
/// they fill devices the scan found.
struct UniFiInventoryParsingTests {

    private let devicesJSON = """
    {"offset":0,"limit":200,"count":2,"totalCount":2,"data":[
     {"id":"a","name":"U7 Pro","model":"U7 Pro","macAddress":"28:70:4e:00:00:04","ipAddress":"192.168.2.4",
      "state":"ONLINE","supported":true,"firmwareVersion":"8.0","firmwareUpdatable":false,"features":[],"interfaces":[]},
     {"id":"b","name":"Montrose Cloud Gateway Max","model":"UCG Max","macAddress":"28:70:4e:00:00:01","ipAddress":"203.0.113.9"}
    ]}
    """

    private let clientsJSON = """
    {"offset":0,"limit":200,"count":3,"totalCount":3,"data":[
     {"type":"WIRELESS","id":"c","name":"Meross Smart Bulb 1f:57","connectedAt":"2026-11-20T10:00:00Z",
      "ipAddress":"192.168.2.183","macAddress":"c4:e7:ae:00:1f:57","uplinkDeviceId":"a","access":{"type":"DEFAULT"}},
     {"type":"WIRELESS","id":"d","name":"5c:e7:53:04:d0:3e","ipAddress":"192.168.2.243","macAddress":"5c:e7:53:04:d0:3e"},
     {"type":"VPN","id":"e","name":"Remote"}
    ]}
    """

    @Test("Devices and clients decode, UniFi devices first, entries without an IP dropped")
    func decodes() throws {
        let devices = try JSONDecoder().decode(UniFiNetworkService.Page<UniFiNetworkService.DeviceRecord>.self, from: Data(devicesJSON.utf8))
        let clients = try JSONDecoder().decode(UniFiNetworkService.Page<UniFiNetworkService.ClientRecord>.self, from: Data(clientsJSON.utf8))
        let entries = UniFiNetworkService.entries(devices: devices.data, clients: clients.data)
        #expect(entries.map(\.ipAddress) == ["192.168.2.4", "203.0.113.9", "192.168.2.183", "192.168.2.243"])
        #expect(entries[0] == UniFiInventoryEntry(
            ipAddress: "192.168.2.4", name: "U7 Pro", model: "U7 Pro", macAddress: "28:70:4e:00:00:04", isUniFiDevice: true
        ))
        #expect(entries[2].name == "Meross Smart Bulb")
        #expect(entries[2].model == nil)
        #expect(entries[3].name == nil)
    }

    @Test("Generated names lose their MAC tail; real names stay", arguments: [
        ("Meross Smart Bulb 1f:57", "Meross Smart Bulb"),
        ("Lutron-05143dcc b4:3f", "Lutron-05143dcc"),
        ("Blake’s  iPhone", "Blake’s  iPhone"),
        ("Ecobee Thermostat ", "Ecobee Thermostat")
    ])
    func cleansNames(raw: String, clean: String) {
        #expect(UniFiNetworkService.cleanName(raw) == clean)
    }

    @Test("Names that are only a MAC, or empty, give nothing")
    func dropsMACNames() {
        #expect(UniFiNetworkService.cleanName("5c:e7:53:04:d0:3e") == nil)
        #expect(UniFiNetworkService.cleanName("  ") == nil)
        #expect(UniFiNetworkService.cleanName(nil) == nil)
    }

}

private struct FixedInventory: UniFiNetworkServiceProtocol {
    let entries: [UniFiInventoryEntry]
    func inventory() async -> [UniFiInventoryEntry] { entries }
}

struct UniFiInventoryPhaseTests {

    private func found(_ ip: String, hostname: String? = nil, vendor: String? = nil, model: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: hostname, vendor: vendor, macAddress: nil,
            latency: 1, discoveredAt: Date(), source: .local,
            identity: DeviceIdentity(model: IdentityValue(model, source: .bonjour))
        )
    }

    private func client(_ ip: String, _ name: String?, mac: String?) -> UniFiInventoryEntry {
        UniFiInventoryEntry(ipAddress: ip, name: name, model: nil, macAddress: mac, isUniFiDevice: false)
    }

    private func run(_ entries: [UniFiInventoryEntry], found devices: [DiscoveredDevice]) async -> [String: DiscoveredDevice] {
        let accumulator = ScanAccumulator()
        for device in devices {
            await accumulator.upsert(device)
        }
        let phase = UniFiInventoryPhase(
            service: FixedInventory(entries: entries),
            vendorForMAC: { $0.lowercased().hasPrefix("d8:a0:11") ? "WiZ" : nil }
        )
        let context = ScanContext(hosts: [], subnetFilter: { $0.hasPrefix("192.168.2.") }, localIP: nil)
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        return await Dictionary(uniqueKeysWithValues: accumulator.snapshot().map { ($0.ipAddress, $0) })
    }

    @Test("A fixed-IP UniFi access point gets Ubiquiti, its model and its name")
    func unifiDevice() async {
        let result = await run(
            [UniFiInventoryEntry(ipAddress: "192.168.2.4", name: "U7 Pro", model: "U7 Pro", macAddress: "28:70:4e:00:00:04", isUniFiDevice: true)],
            found: [found("192.168.2.4")]
        )
        #expect(result["192.168.2.4"]?.identity.maker == IdentityValue("Ubiquiti", source: .unifi))
        #expect(result["192.168.2.4"]?.identity.model == IdentityValue("U7 Pro", source: .unifi))
        #expect(result["192.168.2.4"]?.displayName == "U7 Pro")
        // A public MAC is recorded, normalized, so the device match can key the device by it (#461).
        #expect(result["192.168.2.4"]?.macAddress == "28:70:4E:00:00:04")
    }

    @Test("A client's maker comes from its MAC, else from the name UniFi gave it")
    func clients() async {
        let result = await run([
            client("192.168.2.108", "wiz_fcd4aa", mac: "d8:a0:11:aa:d4:aa"),
            client("192.168.2.183", "Meross Smart Bulb", mac: "c4:e7:ae:00:1f:57"),
            client("192.168.2.163", "Aqara Hub M3", mac: "18:c2:3c:4a:02:54")
        ], found: [found("192.168.2.108"), found("192.168.2.183", hostname: "mt7687-4.local"), found("192.168.2.163")])
        // The MAC's maker is a MAC-prefix maker (`vendor`); a maker read from UniFi's
        // fingerprint name is a guess (ADR-022, #462 Q16).
        #expect(result["192.168.2.108"]?.vendor == "WiZ")
        #expect(result["192.168.2.108"]?.maker == "WiZ")
        #expect(result["192.168.2.183"]?.identity.maker == IdentityValue("Meross", source: .hostnameGuess))
        #expect(result["192.168.2.183"]?.hostname == "mt7687-4.local")
        #expect(result["192.168.2.183"]?.identity.friendlyName == IdentityValue("Meross Smart Bulb", source: .unifi))
        #expect(result["192.168.2.163"]?.maker == "Aqara")
        #expect(result["192.168.2.163"]?.identity.model == IdentityValue("Hub M3", source: .hostnameGuess))
    }

    @Test("Keeps what the scan already knew, and ignores devices it didn't find")
    func fillOnly() async {
        let result = await run([
            client("192.168.2.12", "LivingRoom AppleTv", mac: "8c:26:aa:00:00:12"),
            UniFiInventoryEntry(ipAddress: "192.168.2.99", name: "Hue Bridge", model: nil, macAddress: nil, isUniFiDevice: false),
            UniFiInventoryEntry(ipAddress: "203.0.113.9", name: "Gateway", model: "UCG Max", macAddress: nil, isUniFiDevice: true)
        ], found: [found("192.168.2.12", hostname: "Living room", vendor: "Apple", model: "AppleTV14,1")])
        #expect(result["192.168.2.12"]?.vendor == "Apple")
        #expect(result["192.168.2.12"]?.modelName == "AppleTV14,1")
        #expect(result["192.168.2.12"]?.hostname == "Living room")
        #expect(result["192.168.2.99"] == nil)
        #expect(result["203.0.113.9"] == nil)
    }

    @Test("A device's own UPnP maker outranks the maker from its MAC")
    func announcedMakerOutranksMAC() async {
        let bulb = DiscoveredDevice(
            ipAddress: "192.168.2.108", hostname: nil, vendor: nil, macAddress: nil, latency: 1, discoveredAt: Date(),
            source: .ssdp, identity: DeviceIdentity(maker: IdentityValue("Signify", source: .upnp))
        )
        let result = await run([client("192.168.2.108", nil, mac: "d8:a0:11:aa:d4:aa")], found: [bulb])
        #expect(result["192.168.2.108"]?.vendor == "WiZ")
        #expect(result["192.168.2.108"]?.maker == "Signify")
    }

    @Test("An entry whose MAC contradicts the scan's is another site's device and is skipped")
    func contradictingMACSkipsTheEntry() async {
        let scanned = DiscoveredDevice(
            ipAddress: "192.168.2.20", hostname: nil, vendor: nil, macAddress: "28:70:4E:00:00:20",
            latency: 1, discoveredAt: Date(), source: .local
        )
        let result = await run([
            UniFiInventoryEntry(ipAddress: "192.168.2.20", name: "Other Site AP", model: "U6 Lite", macAddress: "28:70:4e:00:00:99", isUniFiDevice: true),
            UniFiInventoryEntry(ipAddress: "192.168.2.20", name: "Office AP", model: "U7 Pro", macAddress: "28:70:4e:00:00:20", isUniFiDevice: true)
        ], found: [scanned])
        #expect(result["192.168.2.20"]?.friendlyName == "Office AP")
        #expect(result["192.168.2.20"]?.modelName == "U7 Pro")
    }

    @Test("A private MAC says nothing about the maker")
    func privateMAC() async {
        let result = await run(
            [UniFiInventoryEntry(ipAddress: "192.168.2.144", name: nil, model: nil, macAddress: "7e:8d:13:00:57:56", isUniFiDevice: false)],
            found: [found("192.168.2.144")]
        )
        #expect(result["192.168.2.144"]?.maker == nil)
        // Nor is it recorded: a nameless device without a MAC wouldn't adopt it (#461).
        #expect(result["192.168.2.144"]?.macAddress == nil)
    }

    @Test("A MAC the scan already read wins over the controller's")
    func scanMACWins() async {
        let result = await run(
            [client("192.168.2.12", "Printer", mac: "3c:22:fb:00:00:99")],
            found: [DiscoveredDevice(
                ipAddress: "192.168.2.12", hostname: nil, vendor: nil, macAddress: "3C:22:FB:00:00:12",
                latency: nil, discoveredAt: Date(), source: .local
            )]
        )
        #expect(result["192.168.2.12"]?.macAddress == "3C:22:FB:00:00:12")
    }

    @Test("The controller's MAC doesn't name the maker when the scan read a different MAC")
    func scanMACDecidesMaker() async {
        func scanned(_ mac: String) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: "192.168.2.12", hostname: nil, vendor: nil, macAddress: mac,
                latency: nil, discoveredAt: Date(), source: .local
            )
        }
        // The IP was reassigned: the controller still lists a WiZ bulb there.
        let stale = await run([client("192.168.2.12", nil, mac: "d8:a0:11:aa:d4:aa")], found: [scanned("3C:22:FB:00:00:12")])
        #expect(stale["192.168.2.12"]?.macAddress == "3C:22:FB:00:00:12")
        #expect(stale["192.168.2.12"]?.vendor == nil)
        #expect(stale["192.168.2.12"]?.maker == nil)

        // The same MAC, written differently, still names the maker.
        let same = await run([client("192.168.2.12", nil, mac: "d8:a0:11:aa:d4:aa")], found: [scanned("D8:A0:11:AA:D4:AA")])
        #expect(same["192.168.2.12"]?.vendor == "WiZ")
    }
}
