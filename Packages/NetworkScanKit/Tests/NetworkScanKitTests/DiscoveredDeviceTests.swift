import Testing
import Foundation
@testable import NetworkScanKit

@Suite("DiscoveredDevice")
struct DiscoveredDeviceTests {

    // MARK: - Convenience init

    @Test("convenience init sets expected fields")
    func convenienceInit() {
        let date = Date()
        let device = DiscoveredDevice(ipAddress: "192.168.1.1", latency: 5.0, discoveredAt: date)
        #expect(device.ipAddress == "192.168.1.1")
        #expect(device.latency == 5.0)
        #expect(device.discoveredAt == date)
        #expect(device.hostname == nil)
        #expect(device.vendor == nil)
        #expect(device.macAddress == nil)
        #expect(device.source == .local)
    }

    // MARK: - Full init

    @Test("full init with all fields")
    func fullInit() {
        let date = Date()
        let device = DiscoveredDevice(
            ipAddress: "10.0.0.1",
            hostname: "router.local",
            vendor: "Apple",
            macAddress: "aa:bb:cc:dd:ee:ff",
            latency: 2.5,
            discoveredAt: date,
            source: .bonjour
        )
        #expect(device.ipAddress == "10.0.0.1")
        #expect(device.hostname == "router.local")
        #expect(device.vendor == "Apple")
        #expect(device.macAddress == "aa:bb:cc:dd:ee:ff")
        #expect(device.latency == 2.5)
        #expect(device.discoveredAt == date)
        #expect(device.source == .bonjour)
    }

    @Test("full init with nil optional fields")
    func fullInitNilFields() {
        let device = DiscoveredDevice(
            ipAddress: "10.0.0.2",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .ssdp
        )
        #expect(device.hostname == nil)
        #expect(device.vendor == nil)
        #expect(device.macAddress == nil)
        #expect(device.latency == nil)
    }

    // MARK: - displayName

    @Test("displayName returns hostname when present")
    func displayNameWithHostname() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.5",
            hostname: "my-device.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
        #expect(device.displayName == "my-device.local")
    }

    @Test("displayName falls back to IP when hostname nil")
    func displayNameFallback() {
        let device = DiscoveredDevice(ipAddress: "192.168.1.5", latency: 1.0, discoveredAt: Date())
        #expect(device.displayName == "192.168.1.5")
    }

    // MARK: - latencyText

    @Test("latencyText under 1ms shows <1 ms")
    func latencyTextUnderOneMs() {
        let device = DiscoveredDevice(ipAddress: "192.168.1.1", latency: 0.5, discoveredAt: Date())
        #expect(device.latencyText == "<1 ms")
    }

    @Test("latencyText rounds to integer ms")
    func latencyTextRounded() {
        let device = DiscoveredDevice(ipAddress: "192.168.1.1", latency: 12.7, discoveredAt: Date())
        #expect(device.latencyText == "13 ms")
    }

    @Test("latencyText nil with macCompanion source")
    func latencyTextMacCompanion() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.1", hostname: nil, vendor: nil,
            macAddress: nil, latency: nil, discoveredAt: Date(), source: .macCompanion
        )
        #expect(device.latencyText == "via Mac")
    }

    @Test("latencyText nil with ssdp source")
    func latencyTextSSDP() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.1", hostname: nil, vendor: nil,
            macAddress: nil, latency: nil, discoveredAt: Date(), source: .ssdp
        )
        #expect(device.latencyText == "UPnP")
    }

    @Test("latencyText nil with bonjour source")
    func latencyTextBonjour() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.1", hostname: nil, vendor: nil,
            macAddress: nil, latency: nil, discoveredAt: Date(), source: .bonjour
        )
        #expect(device.latencyText == "Bonjour")
    }

    @Test("latencyText nil with local source shows dash")
    func latencyTextLocalNil() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.1", hostname: nil, vendor: nil,
            macAddress: nil, latency: nil, discoveredAt: Date(), source: .local
        )
        #expect(device.latencyText == "—")
    }

    // MARK: - ipSortKey

    @Test("ipSortKey sorts numerically not lexicographically")
    func ipSortKeyNumericalOrder() {
        let ip1 = "10.0.0.9"
        let ip2 = "10.0.0.10"
        let ip3 = "10.0.0.100"
        #expect(ip1.ipSortKey < ip2.ipSortKey)
        #expect(ip2.ipSortKey < ip3.ipSortKey)
    }

    @Test("ipSortKey computes correct value")
    func ipSortKeyValue() {
        // 192.168.1.1 = 192*16777216 + 168*65536 + 1*256 + 1
        let expected = 192 * 16_777_216 + 168 * 65_536 + 1 * 256 + 1
        #expect("192.168.1.1".ipSortKey == expected)
    }

    @Test("ipSortKey returns 0 for invalid IP")
    func ipSortKeyInvalid() {
        #expect("not.an.ip".ipSortKey == 0)
        #expect("".ipSortKey == 0)
    }

    // MARK: - BonjourServiceInfo

    @Test("BonjourServiceInfo init")
    func bonjourServiceInfoInit() {
        let info = BonjourServiceInfo(name: "MyDevice", type: "_http._tcp", domain: "local.")
        #expect(info.name == "MyDevice")
        #expect(info.type == "_http._tcp")
        #expect(info.domain == "local.")
    }
}
