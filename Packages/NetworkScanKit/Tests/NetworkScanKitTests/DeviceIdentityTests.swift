import Foundation
import Testing
@testable import NetworkScanKit

/// Maker and model from hostnames and from UniFi discovery replies (#439).
struct HostnameIdentityTests {

    @Test("A UniFi switch's hostname gives Ubiquiti and its product name")
    func unifiSwitch() {
        let identity = HostnameIdentity.parse(hostname: "unifi-pro-max-16-switch.lan.windingbrook.net")
        #expect(identity == HostnameIdentity(maker: "Ubiquiti", model: "UniFi Pro Max 16 Switch"))
    }

    @Test("Hostnames map to maker and model", arguments: [
        ("Blakes-MacBook-Pro.local", "Apple", "MacBook Pro"),
        ("usw24-poe", "Ubiquiti", "USW24 PoE"),
        ("brother-hl-l2350dw", "Brother", "HL L2350DW"),
        ("esp32-a1b2c3", "Espressif", "ESP32"),
        ("tp-link-deco-m5", "TP-Link", "Deco M5"),
        ("Living-Room-Apple-TV", "Apple", "Apple TV"),
        // Real names from Blake's LAN (2026-11-20).
        ("u7-pro-max.lan.windingbrook.net", "Ubiquiti", "U7 Pro Max"),
        ("meross-mss620-ee73.lan.windingbrook.net", "Meross", "MSS620"),
        ("Aqara-Hub-M3-8548.lan.windingbrook.net", "Aqara", "Hub M3"),
        ("GL-SFT1200.lan.windingbrook.net", "GL.iNet", "SFT1200"),
        ("lr-atv.lan.windingbrook.net", "Apple", "Apple TV")
    ])
    func hostnames(hostname: String, maker: String, model: String) {
        #expect(HostnameIdentity.parse(hostname: hostname) == HostnameIdentity(maker: maker, model: model))
    }

    @Test("A brand with no model word gives the maker only")
    func makerOnly() {
        #expect(HostnameIdentity.parse(hostname: "hp-printer") == HostnameIdentity(maker: "HP", model: nil))
        #expect(HostnameIdentity.parse(hostname: "sonos-kitchen") == HostnameIdentity(maker: "Sonos", model: nil))
        // A room number is not a model.
        #expect(HostnameIdentity.parse(hostname: "sonos-bedroom-2") == HostnameIdentity(maker: "Sonos", model: nil))
    }

    @Test("Owner names and duplicate-name suffixes stay out of the model")
    func defaultDeviceNames() {
        #expect(HostnameIdentity.parse(hostname: "iPhone-de-Juan") == HostnameIdentity(maker: "Apple", model: "iPhone"))
        #expect(HostnameIdentity.parse(hostname: "iPhone-von-Max") == HostnameIdentity(maker: "Apple", model: "iPhone"))
        #expect(HostnameIdentity.parse(hostname: "Johns-MacBook-Pro-2.local") == HostnameIdentity(maker: "Apple", model: "MacBook Pro"))
    }

    @Test("Software named after a brand is not that brand's hardware")
    func softwareNames() {
        #expect(HostnameIdentity.parse(hostname: "unifi-controller") == nil)
        #expect(HostnameIdentity.parse(hostname: "plex-server") == nil)
    }

    @Test("Fills only empty fields, and a model only when the known maker agrees")
    func fills() {
        let identity = HostnameIdentity(maker: "Ubiquiti", model: "UniFi Pro Max 16 Switch")
        #expect(identity.fills(knownMaker: nil, knownModel: nil) == ("Ubiquiti", "UniFi Pro Max 16 Switch"))
        #expect(identity.fills(knownMaker: "Ubiquiti Inc", knownModel: nil) == (nil, "UniFi Pro Max 16 Switch"))
        #expect(identity.fills(knownMaker: "Raspberry Pi", knownModel: nil) == (nil, nil))
        #expect(identity.fills(knownMaker: "", knownModel: "USW24") == ("Ubiquiti", nil))
    }

    @Test("Names without a brand, and addresses, give nothing")
    func noBrand() {
        #expect(HostnameIdentity.parse(hostname: "office-printer.lan") == nil)
        #expect(HostnameIdentity.parse(hostname: "192.168.2.2") == nil)
        #expect(HostnameIdentity.parse(hostname: "HP1A2B3C") == nil)
        // A bare "u" is not a UniFi model; "u7" is.
        #expect(HostnameIdentity.parse(hostname: "u-boot") == nil)
        // A brand word in the domain, not the device's own label, doesn't count.
        #expect(HostnameIdentity.parse(hostname: "desk.unifi.example") == nil)
    }
}

struct HostnameIdentityPhaseTests {

    private func device(hostname: String?, vendor: String? = nil, model: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: "192.168.2.2", hostname: hostname, vendor: vendor, macAddress: nil,
            latency: nil, discoveredAt: Date(), source: .local, modelName: model
        )
    }

    @Test("Fills an empty maker and model through the accumulator")
    func fillsEmptyFields() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(device(hostname: "unifi-pro-max-16-switch.lan.windingbrook.net"))
        let context = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        await HostnameIdentityPhase().execute(context: context, accumulator: accumulator) { _ in }
        let result = await accumulator.snapshot().first
        #expect(result?.vendor == "Ubiquiti")
        #expect(result?.modelName == "UniFi Pro Max 16 Switch")
    }

    @Test("Never replaces a maker or model from a better source")
    func keepsBetterSources() {
        // A model already known (Bonjour, UPnP, UniFi discovery) stays; nothing else to fill.
        #expect(HostnameIdentityPhase.update(for: device(hostname: "unifi-switch-24", vendor: "Ubiquiti Inc", model: "USW24")) == nil)
        // An agreeing MAC-prefix maker stays, and the model is filled.
        let update = HostnameIdentityPhase.update(for: device(hostname: "unifi-pro-max-16-switch", vendor: "Ubiquiti Inc"))
        #expect(update?.vendor == nil)
        #expect(update?.modelName == "UniFi Pro Max 16 Switch")
        // A maker that disagrees with the hostname blocks the hostname's model.
        #expect(HostnameIdentityPhase.update(for: device(hostname: "unifi-pro-max-16-switch", vendor: "Raspberry Pi")) == nil)
    }
}

struct UbiquitiDiscoveryTests {

    /// Builds a discovery reply: header (version 1, command 0, length) then type/length/value fields.
    private func reply(_ fields: [(UInt8, String)], version: UInt8 = 0x01) -> [UInt8] {
        var body: [UInt8] = []
        // A MAC+IP field first, as real replies have.
        body += [0x02, 0x00, 0x0a, 0x28, 0x70, 0x4e, 0x00, 0x00, 0x01, 0xc0, 0xa8, 0x02, 0x01]
        for (type, text) in fields {
            let value = Array(text.utf8)
            body += [type, UInt8(value.count >> 8), UInt8(value.count & 0xff)] + value
        }
        return [version, 0x00, UInt8(body.count >> 8), UInt8(body.count & 0xff)] + body
    }

    @Test("Reads name and platform from a UniFi gateway's reply")
    func parsesGatewayReply() {
        let bytes = reply([(0x0b, "Montrose-Cloud-Gateway-Max"), (0x0c, "UCGMAX"), (0x03, "6.0.17"), (0x15, "UCGMAX")])
        #expect(UbiquitiDiscovery.parse(bytes) == UbiquitiDeviceInfo(name: "Montrose-Cloud-Gateway-Max", model: "UCGMAX"))
    }

    @Test("A controller's role name is not taken as a model")
    func ignoresControllerRole() {
        let controller = reply([(0x0b, "UCTRL-2870"), (0x15, "uum_controller")], version: 0x02)
        #expect(UbiquitiDiscovery.parse(controller) == UbiquitiDeviceInfo(name: "UCTRL-2870", model: nil))
        // Both replies from one gateway: the platform reply's model and the first name win.
        let merged = UbiquitiDiscovery.collect([
            (ip: "192.168.2.1", bytes: reply([(0x0b, "Montrose-Cloud-Gateway-Max"), (0x0c, "UCGMAX")])),
            (ip: "192.168.2.1", bytes: controller)
        ])
        #expect(merged == ["192.168.2.1": UbiquitiDeviceInfo(name: "Montrose-Cloud-Gateway-Max", model: "UCGMAX")])
    }

    @Test("Rejects other traffic and truncated replies")
    func rejectsGarbage() {
        #expect(UbiquitiDiscovery.parse([]) == nil)
        #expect(UbiquitiDiscovery.parse(Array("HTTP/1.1 200 OK".utf8)) == nil)
        var truncated = reply([(0x0c, "UCGMAX")])
        truncated.removeLast(3)
        #expect(UbiquitiDiscovery.parse(truncated) == nil)
    }

    @Test("The phase records maker, model and name for answering devices in the subnet")
    func phaseUpserts() async {
        let phase = UbiquitiDiscoveryPhase(discover: { _ in
            [
                "192.168.2.1": UbiquitiDeviceInfo(name: "Montrose-Cloud-Gateway-Max", model: "UCGMAX"),
                "10.0.0.9": UbiquitiDeviceInfo(name: "elsewhere", model: "U6PRO")
            ]
        })
        let accumulator = ScanAccumulator()
        let context = ScanContext(hosts: [], subnetFilter: { $0.hasPrefix("192.168.2.") }, localIP: nil)
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        let devices = await accumulator.snapshot()
        #expect(devices.count == 1)
        #expect(devices.first?.vendor == "Ubiquiti")
        #expect(devices.first?.modelName == "UCGMAX")
        #expect(devices.first?.friendlyName == "Montrose-Cloud-Gateway-Max")
    }

    @Test("A reply with a name but no model code doesn't make the device Ubiquiti")
    func nameOnlyReplyHasNoMaker() async {
        let phase = UbiquitiDiscoveryPhase(discover: { _ in ["192.168.2.40": UbiquitiDeviceInfo(name: "pi-controller", model: nil)] })
        let accumulator = ScanAccumulator()
        let context = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        let device = await accumulator.snapshot().first
        #expect(device?.vendor == nil)
        #expect(device?.manufacturer == nil)
        #expect(device?.friendlyName == "pi-controller")
    }
}
