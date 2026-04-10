import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - DeviceType

struct DeviceTypeTests {
    @Test func iconNames() {
        #expect(DeviceType.router.iconName == "wifi.router")
        #expect(DeviceType.computer.iconName == "desktopcomputer")
        #expect(DeviceType.laptop.iconName == "laptopcomputer")
        #expect(DeviceType.phone.iconName == "iphone")
        #expect(DeviceType.tablet.iconName == "ipad")
        #expect(DeviceType.tv.iconName == "appletv")
        #expect(DeviceType.speaker.iconName == "homepodmini")
        #expect(DeviceType.gaming.iconName == "gamecontroller")
        #expect(DeviceType.iot.iconName == "sensor")
        #expect(DeviceType.printer.iconName == "printer")
        #expect(DeviceType.camera.iconName == "web.camera")
        #expect(DeviceType.storage.iconName == "externaldrive")
        #expect(DeviceType.unknown.iconName == "questionmark.circle")
    }

    @Test func displayNames() {
        #expect(DeviceType.router.displayName == "Router")
        #expect(DeviceType.computer.displayName == "Computer")
        #expect(DeviceType.laptop.displayName == "Laptop")
        #expect(DeviceType.phone.displayName == "Phone")
        #expect(DeviceType.tablet.displayName == "Tablet")
        #expect(DeviceType.tv.displayName == "TV")
        #expect(DeviceType.speaker.displayName == "Speaker")
        #expect(DeviceType.gaming.displayName == "Gaming")
        #expect(DeviceType.iot.displayName == "IoT Device")
        #expect(DeviceType.printer.displayName == "Printer")
        #expect(DeviceType.camera.displayName == "Camera")
        #expect(DeviceType.storage.displayName == "Storage")
        #expect(DeviceType.unknown.displayName == "Unknown")
    }

    @Test func allCasesAreCovered() {
        #expect(DeviceType.allCases.count == 13)
    }
}

// MARK: - StatusType

struct StatusTypeTests {
    @Test func labels() {
        #expect(StatusType.online.label == "Online")
        #expect(StatusType.offline.label == "Offline")
        #expect(StatusType.idle.label == "Idle")
        #expect(StatusType.unknown.label == "Unknown")
    }

    @Test func icons() {
        #expect(StatusType.online.icon == "checkmark.circle.fill")
        #expect(StatusType.offline.icon == "xmark.circle.fill")
        #expect(StatusType.idle.icon == "moon.circle.fill")
        #expect(StatusType.unknown.icon == "questionmark.circle.fill")
    }

    @Test func allCasesAreCovered() {
        #expect(StatusType.allCases.count == 4)
    }
}

// MARK: - DeviceStatus

struct DeviceStatusTests {
    @Test func statusTypeMapping() {
        #expect(DeviceStatus.online.statusType == .online)
        #expect(DeviceStatus.offline.statusType == .offline)
        #expect(DeviceStatus.idle.statusType == .idle)
    }

    @Test func allCasesAreCovered() {
        #expect(DeviceStatus.allCases.count == 3)
    }
}

// MARK: - ConnectionType

struct ConnectionTypeTests {
    @Test func iconNames() {
        #expect(ConnectionType.wifi.iconName == "wifi")
        #expect(ConnectionType.cellular.iconName == "antenna.radiowaves.left.and.right")
        #expect(ConnectionType.ethernet.iconName == "cable.connector")
        #expect(ConnectionType.none.iconName == "wifi.slash")
    }

    @Test func displayNames() {
        #expect(ConnectionType.wifi.displayName == "Wi-Fi")
        #expect(ConnectionType.cellular.displayName == "Cellular")
        #expect(ConnectionType.ethernet.displayName == "Ethernet")
        #expect(ConnectionType.none.displayName == "No Connection")
    }

    @Test func decodesLowercaseRawValues() throws {
        func decode(_ raw: String) throws -> ConnectionType {
            let data = Data("\"\(raw)\"".utf8)
            return try JSONDecoder().decode(ConnectionType.self, from: data)
        }
        #expect(try decode("wifi") == .wifi)
        #expect(try decode("cellular") == .cellular)
        #expect(try decode("ethernet") == .ethernet)
        #expect(try decode("none") == .none)
    }

    @Test func decodesLegacyCapitalizedValues() throws {
        func decode(_ raw: String) throws -> ConnectionType {
            let data = Data("\"\(raw)\"".utf8)
            return try JSONDecoder().decode(ConnectionType.self, from: data)
        }
        #expect(try decode("WiFi") == .wifi)
        #expect(try decode("Cellular") == .cellular)
        #expect(try decode("Ethernet") == .ethernet)
        #expect(try decode("Unknown") == .none)
    }

    @Test func decodesUnknownAsNone() throws {
        let data = Data("\"bogus\"".utf8)
        let result = try JSONDecoder().decode(ConnectionType.self, from: data)
        #expect(result == .none)
    }
}

// MARK: - ToolType

struct ToolTypeTests {
    @Test func iconNames() {
        #expect(ToolType.ping.iconName == "arrow.up.arrow.down")
        #expect(ToolType.traceroute.iconName == "point.topleft.down.to.point.bottomright.curvepath")
        #expect(ToolType.dnsLookup.iconName == "globe")
        #expect(ToolType.portScan.iconName == "door.left.hand.open")
        #expect(ToolType.bonjourDiscovery.iconName == "bonjour")
        #expect(ToolType.speedTest.iconName == "speedometer")
        #expect(ToolType.whois.iconName == "doc.text.magnifyingglass")
        #expect(ToolType.wakeOnLan.iconName == "power")
        #expect(ToolType.networkScan.iconName == "network")
    }

    @Test func displayNames() {
        #expect(ToolType.ping.displayName == "Ping")
        #expect(ToolType.traceroute.displayName == "Traceroute")
        #expect(ToolType.dnsLookup.displayName == "DNS Lookup")
        #expect(ToolType.portScan.displayName == "Port Scanner")
        #expect(ToolType.bonjourDiscovery.displayName == "Bonjour Discovery")
        #expect(ToolType.speedTest.displayName == "Speed Test")
        #expect(ToolType.whois.displayName == "WHOIS")
        #expect(ToolType.wakeOnLan.displayName == "Wake on LAN")
        #expect(ToolType.networkScan.displayName == "Network Scan")
    }

    @Test func allCasesAreCovered() {
        #expect(ToolType.allCases.count == 19)
    }
}

// MARK: - TargetProtocol

struct TargetProtocolTests {
    @Test func displayNames() {
        #expect(TargetProtocol.icmp.displayName == "ICMP (Ping)")
        #expect(TargetProtocol.tcp.displayName == "TCP")
        #expect(TargetProtocol.http.displayName == "HTTP")
        #expect(TargetProtocol.https.displayName == "HTTPS")
    }

    @Test func defaultPorts() {
        #expect(TargetProtocol.icmp.defaultPort == nil)
        #expect(TargetProtocol.tcp.defaultPort == 80)
        #expect(TargetProtocol.http.defaultPort == 80)
        #expect(TargetProtocol.https.defaultPort == 443)
    }

    /// Regression test for bug_targetprotocol_uppercase: SwiftData stored uppercase "HTTPS"
    /// and the decoder crashed because TargetProtocol(rawValue:) is case-sensitive.
    /// Fix: case-insensitive Codable init (commit e6c74a0). Ensures it never regresses.
    @Test("Codable decode accepts uppercase raw values (regression: bug_targetprotocol_uppercase)")
    func decodeUppercase() throws {
        struct Wrapper: Codable { let proto: TargetProtocol }
        let cases: [(String, TargetProtocol)] = [
            (#"{"proto":"HTTPS"}"#, .https),
            (#"{"proto":"HTTP"}"#, .http),
            (#"{"proto":"TCP"}"#, .tcp),
            (#"{"proto":"ICMP"}"#, .icmp),
        ]
        for (json, expected) in cases {
            let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
            #expect(decoded.proto == expected, "Expected \(expected) decoding \(json)")
        }
    }

    @Test("Codable decode accepts mixed-case raw values")
    func decodeMixedCase() throws {
        struct Wrapper: Codable { let proto: TargetProtocol }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"proto":"Https"}"#.utf8))
        #expect(decoded.proto == .https)
    }

    @Test("Codable encode always writes lowercase")
    func encodeLowercase() throws {
        struct Wrapper: Codable { let proto: TargetProtocol }
        let data = try JSONEncoder().encode(Wrapper(proto: .https))
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"https\""))
        #expect(!json.contains("\"HTTPS\""))
    }
}

// MARK: - DNSRecordType

struct DNSRecordTypeTests {
    @Test func displayNameEqualsRawValue() {
        #expect(DNSRecordType.a.displayName == "A")
        #expect(DNSRecordType.aaaa.displayName == "AAAA")
        #expect(DNSRecordType.mx.displayName == "MX")
        #expect(DNSRecordType.txt.displayName == "TXT")
        #expect(DNSRecordType.cname.displayName == "CNAME")
        #expect(DNSRecordType.ns.displayName == "NS")
        #expect(DNSRecordType.soa.displayName == "SOA")
        #expect(DNSRecordType.ptr.displayName == "PTR")
    }

    @Test func allCasesAreCovered() {
        #expect(DNSRecordType.allCases.count == 8)
    }
}

// MARK: - PortScanPreset

struct PortScanPresetTests {
    @Test func displayNames() {
        #expect(PortScanPreset.common.displayName == "Common Ports")
        #expect(PortScanPreset.wellKnown.displayName == "Well-Known (1-1024)")
        #expect(PortScanPreset.extended.displayName == "Extended (1-10000)")
        #expect(PortScanPreset.web.displayName == "Web Ports")
        #expect(PortScanPreset.database.displayName == "Database Ports")
        #expect(PortScanPreset.mail.displayName == "Mail Ports")
        #expect(PortScanPreset.custom.displayName == "Custom Range")
    }

    @Test func isCustomOnlyForCustomCase() {
        #expect(PortScanPreset.custom.isCustom == true)
        for preset in PortScanPreset.allCases where preset != .custom {
            #expect(preset.isCustom == false)
        }
    }

    @Test func portsForWellKnown() {
        let ports = PortScanPreset.wellKnown.ports
        #expect(ports.count == 1024)
        #expect(ports.first == 1)
        #expect(ports.last == 1024)
    }

    @Test func portsForExtended() {
        let ports = PortScanPreset.extended.ports
        #expect(ports.count == 10000)
        #expect(ports.first == 1)
        #expect(ports.last == 10000)
    }

    @Test func portsForCustomIsEmpty() {
        #expect(PortScanPreset.custom.ports.isEmpty)
    }

    @Test func portsForCommonMatchesStaticList() {
        #expect(PortScanPreset.common.ports == PortScanPreset.commonPorts)
    }

    @Test func portsForWebMatchesStaticList() {
        #expect(PortScanPreset.web.ports == PortScanPreset.webPorts)
    }

    @Test func portsForDatabaseMatchesStaticList() {
        #expect(PortScanPreset.database.ports == PortScanPreset.databasePorts)
    }

    @Test func portsForMailMatchesStaticList() {
        #expect(PortScanPreset.mail.ports == PortScanPreset.mailPorts)
    }

    @Test func staticPortListContents() {
        #expect(PortScanPreset.commonPorts.contains(22))
        #expect(PortScanPreset.commonPorts.contains(80))
        #expect(PortScanPreset.commonPorts.contains(443))
        #expect(PortScanPreset.webPorts.contains(80))
        #expect(PortScanPreset.webPorts.contains(443))
        #expect(PortScanPreset.databasePorts.contains(3306))
        #expect(PortScanPreset.databasePorts.contains(5432))
        #expect(PortScanPreset.mailPorts.contains(25))
        #expect(PortScanPreset.mailPorts.contains(993))
    }
}

// MARK: - PortRange

struct PortRangeTests {
    @Test func defaultInit() {
        let range = PortRange()
        #expect(range.start == 1)
        #expect(range.end == 1024)
        #expect(range.isValid == true)
        #expect(range.count == 1024)
    }

    @Test func clampsBelowMinimum() {
        let range = PortRange(start: 0, end: -10)
        #expect(range.start == 1)
        #expect(range.end == 1)
    }

    @Test func clampsAboveMaximum() {
        let range = PortRange(start: 100000, end: 200000)
        #expect(range.start == 65535)
        #expect(range.end == 65535)
    }

    @Test func isValidWhenStartLessThanEnd() {
        let range = PortRange(start: 80, end: 443)
        #expect(range.isValid == true)
    }

    @Test func isInvalidWhenStartGreaterThanEnd() {
        let range = PortRange(start: 500, end: 100)
        #expect(range.isValid == false)
        #expect(range.ports.isEmpty)
        #expect(range.isEmpty)
    }

    @Test func singlePortRange() {
        let range = PortRange(start: 80, end: 80)
        #expect(range.isValid == true)
        #expect(range.ports == [80])
        #expect(range.count == 1)
    }

    @Test func portsArrayBoundaries() {
        let range = PortRange(start: 1, end: 3)
        #expect(range.ports == [1, 2, 3])
        #expect(range.count == 3)
    }

    @Test func negativeClampsToOne() {
        let range = PortRange(start: -100, end: 100)
        #expect(range.start == 1)
        #expect(range.end == 100)
        #expect(range.isValid == true)
    }

    @Test func maxValidRange() {
        let range = PortRange(start: 1, end: 65535)
        #expect(range.isValid == true)
        #expect(range.count == 65535)
    }

    @Test func equatableConformance() {
        #expect(PortRange(start: 1, end: 100) == PortRange(start: 1, end: 100))
        #expect(PortRange(start: 1, end: 100) != PortRange(start: 1, end: 200))
    }
}
