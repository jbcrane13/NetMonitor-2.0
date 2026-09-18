import Testing
@testable import NetworkScanKit

struct ScanPhaseIDTests {

    // MARK: - Built-in static members

    @Test("built-in static members have the expected raw values")
    func builtInRawValues() {
        #expect(ScanPhaseID.arp.rawValue == "arp")
        #expect(ScanPhaseID.bonjour.rawValue == "bonjour")
        #expect(ScanPhaseID.tcpProbe.rawValue == "tcpProbe")
        #expect(ScanPhaseID.ssdp.rawValue == "ssdp")
        #expect(ScanPhaseID.icmpLatency.rawValue == "icmpLatency")
        #expect(ScanPhaseID.reverseDNS.rawValue == "reverseDNS")
    }

    // MARK: - RawRepresentable

    @Test("init(rawValue:) round-trips through rawValue")
    func rawValueRoundTrip() {
        let id = ScanPhaseID(rawValue: "custom-phase")
        #expect(id.rawValue == "custom-phase")
    }

    // MARK: - ExpressibleByStringLiteral

    @Test("a string literal is equal to the matching static member")
    func stringLiteralEqualsStaticMember() {
        let id: ScanPhaseID = "arp"
        #expect(id == ScanPhaseID.arp)
        #expect(ScanPhaseID.arp == "arp")
    }

    @Test("init(rawValue:) is equal to the equivalent string literal")
    func rawValueInitEqualsStringLiteral() {
        #expect(ScanPhaseID(rawValue: "arp") == "arp")
    }

    // MARK: - Hashable / Equatable

    @Test("distinct phase IDs are not equal and hash differently")
    func distinctIDsAreUnequal() {
        #expect(ScanPhaseID.arp != ScanPhaseID.bonjour)
        let ids: Set<ScanPhaseID> = [.arp, .bonjour, .tcpProbe, .ssdp, .icmpLatency, .reverseDNS]
        #expect(ids.count == 6)
    }

    @Test("a custom platform phase ID is usable as a Set element alongside built-ins")
    func customPhaseIDCoexistsWithBuiltIns() {
        let ids: Set<ScanPhaseID> = [.arp, "wifiRSSI"]
        #expect(ids.count == 2)
        #expect(ids.contains("wifiRSSI"))
    }
}
