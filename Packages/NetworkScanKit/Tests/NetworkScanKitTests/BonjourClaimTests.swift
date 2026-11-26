import Foundation
import Testing
@testable import NetworkScanKit

/// #594 (design v3.1): the Bonjour host each address answered for, kept as evidence. A Mac on
/// Ethernet and Wi-Fi advertises one host name on both addresses.
@Suite("Bonjour host claims")
struct BonjourClaimTests {

    @Test("Host targets normalise to a lowercased .local name; anything else is no claim", arguments: [
        ("Mini-Pro-1.local.", String?.some("mini-pro-1.local")),
        ("mini-pro-1.local", "mini-pro-1.local"),
        ("Blakes-Mac-2.local.%en0", "blakes-mac-2.local"),
        ("host.example.com.", nil),
        ("192.0.2.10", nil),
        (".local.", nil),
        ("", nil)
    ])
    func normalises(target: String, host: String?) {
        #expect(BonjourHostName.normalized(target) == host)
    }

    @Test("Model-default and generic names are generic, conflict suffix or not", arguments: [
        "iphone.local", "iPhone-2.local", "ipad.local", "macbook-pro.local", "MacBook-Air-3.local", "mac-mini.local",
        "apple-tv.local", "homepod.local", "android.local", "android-1a2b3c4d.local", "galaxy-s23.local", "pixel-8.local",
        "raspberrypi.local", "esp32-a1b2c3.local", "localhost.local", "printer.local", "chromecast.local", "iphone (2).local"
    ])
    func genericNames(host: String) {
        #expect(BonjourHostName.isGeneric(host, maker: nil, model: nil))
    }

    @Test("Owner-named and custom names are strong", arguments: [
        "blakes-iphone.local", "mini-pro-1.local", "office-printer.local", "studio.local", "living-room-tv.local"
    ])
    func strongNames(host: String) {
        #expect(!BonjourHostName.isGeneric(host, maker: nil, model: nil))
    }

    @Test("A name that is only the device's maker or model is generic")
    func makerOrModelName() {
        #expect(BonjourHostName.isGeneric("apple.local", maker: "Apple", model: nil))
        #expect(BonjourHostName.isGeneric("macmini9-1.local", maker: nil, model: "Macmini9,1"))
        #expect(BonjourHostName.isGeneric("sonos-2.local", maker: "Sonos", model: nil))
        #expect(!BonjourHostName.isGeneric("sonos-kitchen.local", maker: "Sonos", model: nil))
    }

    @Test("The full name is kept: a conflict suffix makes a different host")
    func fullNameKept() {
        #expect(BonjourHostName.normalized("blakes-mac.local.") != BonjourHostName.normalized("blakes-mac-2.local."))
    }

    @Test("A host on two in-subnet addresses gives one device per address, each with the claim")
    func oneDevicePerAddress() async {
        let service = BonjourServiceInfo(name: "Mac Mini Pro", type: "_ssh._tcp.", domain: "local.")
        let devices = await BonjourScanPhase.makeBonjourDevices(
            from: service, modelsByName: [:], subnetFilter: { $0.hasPrefix("192.0.2.") },
            resolver: { _ in BonjourResolution(hostTarget: "Mini-Pro-1.local.", port: 22) },
            addressResolver: { _ in ["127.0.0.1", "192.0.2.16", "169.254.1.2", "192.0.2.40"] }
        )
        #expect(devices.map(\.ipAddress) == ["192.0.2.16", "192.0.2.40"])
        #expect(devices.map(\.bonjourClaims) == [
            [HostClaim(host: "mini-pro-1.local", service: "Mac Mini Pro", address: "192.0.2.16")],
            [HostClaim(host: "mini-pro-1.local", service: "Mac Mini Pro", address: "192.0.2.40")]
        ])
        #expect(devices.allSatisfy { $0.hostname == "Mac Mini Pro" })
    }

    @Test("A host target that is an address, or not .local, makes a device with no claim")
    func addressTargetHasNoClaim() async {
        let service = BonjourServiceInfo(name: "Printer", type: "_ipp._tcp.", domain: "local.")
        let devices = await BonjourScanPhase.makeBonjourDevices(
            from: service, modelsByName: [:], subnetFilter: { _ in true },
            resolver: { _ in BonjourResolution(hostTarget: "192.0.2.9", port: 631) }, addressResolver: { _ in [] }
        )
        #expect(devices.map(\.ipAddress) == ["192.0.2.9"])
        #expect(devices.first?.bonjourClaims.isEmpty == true)
    }

    @Test("Claims survive Codable, withCached and withIdentity; old JSON decodes with none")
    func claimsRoundTrip() throws {
        let claim = HostClaim(host: "studio.local", service: "Studio", address: "192.0.2.5")
        let device = DiscoveredDevice(
            ipAddress: "192.0.2.5", hostname: "Studio", vendor: nil, macAddress: nil, latency: nil,
            discoveredAt: Date(timeIntervalSince1970: 0), source: .bonjour, bonjourClaims: [claim]
        )
        let decoded = try JSONDecoder().decode(DiscoveredDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded.bonjourClaims == [claim])
        #expect(device.withCached(true).bonjourClaims == [claim])
        #expect(device.withIdentity(DeviceIdentity()).bonjourClaims == [claim])

        let old = #"{"id":"\#(UUID().uuidString)","ipAddress":"192.0.2.5","discoveredAt":0,"source":"bonjour"}"#
        #expect(try JSONDecoder().decode(DiscoveredDevice.self, from: Data(old.utf8)).bonjourClaims.isEmpty)
    }

    @Test("The accumulator keeps every claim for an address, in order, once each, and through a latency update")
    func accumulatorKeepsAllClaims() async {
        let first = HostClaim(host: "studio.local", service: "Studio", address: "192.0.2.5")
        let second = HostClaim(host: "other.local", service: "Other", address: "192.0.2.5")
        let accumulator = ScanAccumulator()
        for claims in [[first], [second], [first]] {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: "192.0.2.5", hostname: nil, vendor: nil, macAddress: nil, latency: nil,
                discoveredAt: Date(), source: .bonjour, bonjourClaims: claims
            ))
        }
        await accumulator.setLatency(ip: "192.0.2.5", value: 2, source: .icmp)
        #expect(await accumulator.snapshot().first?.bonjourClaims == [first, second])
    }
}
