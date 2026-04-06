import Testing
@testable import NetworkScanKit

@Suite("IPv4Helpers")
struct IPv4HelpersTests {

    // MARK: - isValidIPv4Address

    @Test("valid addresses")
    func validAddresses() {
        #expect(isValidIPv4Address("192.168.1.1"))
        #expect(isValidIPv4Address("0.0.0.0"))
        #expect(isValidIPv4Address("255.255.255.255"))
        #expect(isValidIPv4Address("10.0.0.1"))
        #expect(isValidIPv4Address("172.16.0.1"))
    }

    @Test("invalid - wrong component count")
    func invalidComponentCount() {
        #expect(!isValidIPv4Address("192.168.1"))
        #expect(!isValidIPv4Address("192.168.1.1.1"))
        #expect(!isValidIPv4Address(""))
        #expect(!isValidIPv4Address("192"))
    }

    @Test("invalid - out of range")
    func invalidOutOfRange() {
        #expect(!isValidIPv4Address("256.0.0.0"))
        #expect(!isValidIPv4Address("0.0.0.256"))
        #expect(!isValidIPv4Address("999.999.999.999"))
    }

    @Test("invalid - non-numeric")
    func invalidNonNumeric() {
        #expect(!isValidIPv4Address("abc.def.ghi.jkl"))
        #expect(!isValidIPv4Address("a.b.c.d"))
        #expect(!isValidIPv4Address("192.168.1.x"))
    }

    @Test("invalid - leading zeros")
    func invalidLeadingZeros() {
        #expect(!isValidIPv4Address("01.02.03.04"))
        #expect(!isValidIPv4Address("192.168.001.001"))
    }

    // MARK: - cleanedIPv4Address

    @Test("strips zone ID suffix")
    func stripsZoneID() {
        #expect(cleanedIPv4Address("192.168.1.1%en0") == "192.168.1.1")
        #expect(cleanedIPv4Address("10.0.0.1%lo0") == "10.0.0.1")
    }

    @Test("passthrough valid IP without zone ID")
    func passthroughValidIP() {
        #expect(cleanedIPv4Address("192.168.1.1") == "192.168.1.1")
        #expect(cleanedIPv4Address("0.0.0.0") == "0.0.0.0")
    }

    @Test("returns nil for invalid IP")
    func nilForInvalidIP() {
        #expect(cleanedIPv4Address("256.0.0.1") == nil)
        #expect(cleanedIPv4Address("abc") == nil)
        #expect(cleanedIPv4Address("") == nil)
        #expect(cleanedIPv4Address("::1") == nil)
    }

    // MARK: - extractIPFromSSDPResponse

    @Test("extracts IP from LOCATION header")
    func extractsFromLocationHeader() {
        let response = "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.1:80/desc.xml\r\nST: upnp:rootdevice"
        #expect(extractIPFromSSDPResponse(response) == "192.168.1.1")
    }

    @Test("case insensitive LOCATION header match")
    func caseInsensitiveLocation() {
        let response = "location: http://10.0.0.1:1234/\r\nother: value"
        #expect(extractIPFromSSDPResponse(response) == "10.0.0.1")
    }

    @Test("falls back to any IP in response when no LOCATION header")
    func fallbackToBodyIP() {
        let response = "some ssdp response with 192.168.0.50 in body"
        #expect(extractIPFromSSDPResponse(response) == "192.168.0.50")
    }

    @Test("returns nil when no IP present")
    func returnsNilWhenNoIP() {
        #expect(extractIPFromSSDPResponse("no ip address here") == nil)
        #expect(extractIPFromSSDPResponse("") == nil)
    }

    // MARK: - firstIPv4Address

    @Test("finds IP in mixed text")
    func findsIPInMixedText() {
        #expect(firstIPv4Address(in: "host 192.168.1.100 end") == "192.168.1.100")
        #expect(firstIPv4Address(in: "http://10.0.0.1:8080/path") == "10.0.0.1")
    }

    @Test("returns first valid IP when multiple present")
    func returnsFirstValidIP() {
        let result = firstIPv4Address(in: "first 192.168.1.1 second 10.0.0.1")
        #expect(result == "192.168.1.1")
    }

    @Test("returns nil for text with no valid IP")
    func returnsNilForNoValidIP() {
        #expect(firstIPv4Address(in: "no ip here") == nil)
        #expect(firstIPv4Address(in: "") == nil)
        #expect(firstIPv4Address(in: "256.999.abc.xyz") == nil)
    }

    // MARK: - CIDR Parsing

    @Test("IPv4CIDR parsing valid /24")
    func cidrParsingValid24() throws {
        let cidr = try IPv4CIDR(parsing: "192.168.1.0/24")
        #expect(cidr.prefixLength == 24)
        #expect(cidr.usableHostCount == 254)
    }

    @Test("IPv4CIDR parsing valid /16")
    func cidrParsingValid16() throws {
        let cidr = try IPv4CIDR(parsing: "10.0.0.0/16")
        #expect(cidr.prefixLength == 16)
        #expect(cidr.usableHostCount == 65534)
    }

    @Test("IPv4CIDR parsing valid /30")
    func cidrParsingValid30() throws {
        let cidr = try IPv4CIDR(parsing: "192.168.1.0/30")
        #expect(cidr.prefixLength == 30)
        #expect(cidr.usableHostCount == 2)
        #expect(cidr.firstHost == cidr.networkAddress + 1)
        #expect(cidr.lastHost == cidr.broadcastAddress - 1)
    }

    @Test("IPv4CIDR parsing throws invalid format")
    func cidrParsingInvalidFormat() {
        #expect(throws: CIDRParseError.invalidFormat) {
            try IPv4CIDR(parsing: "192.168.1.0")
        }
        #expect(throws: CIDRParseError.invalidFormat) {
            try IPv4CIDR(parsing: "192.168.1.0/24/32")
        }
    }

    @Test("IPv4CIDR parsing throws invalid IP")
    func cidrParsingInvalidIP() {
        #expect(throws: CIDRParseError.invalidIPAddress) {
            try IPv4CIDR(parsing: "256.0.0.0/24")
        }
        #expect(throws: CIDRParseError.invalidIPAddress) {
            try IPv4CIDR(parsing: "abc.def.ghi.jkl/24")
        }
    }

    @Test("IPv4CIDR parsing throws invalid prefix")
    func cidrParsingInvalidPrefix() {
        #expect(throws: CIDRParseError.invalidPrefixLength) {
            try IPv4CIDR(parsing: "192.168.1.0/33")
        }
        #expect(throws: CIDRParseError.invalidPrefixLength) {
            try IPv4CIDR(parsing: "192.168.1.0/-1")
        }
        #expect(throws: CIDRParseError.invalidPrefixLength) {
            try IPv4CIDR(parsing: "192.168.1.0/abc")
        }
    }

    // MARK: - hostsInSubnet

    @Test("hostsInSubnet /30 returns 2 hosts")
    func hostsInSubnet30() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "192.168.1.0/30")
        #expect(hosts.count == 2)
        #expect(hosts[0] == "192.168.1.1")
        #expect(hosts[1] == "192.168.1.2")
    }

    @Test("hostsInSubnet /24 returns 254 hosts")
    func hostsInSubnet24() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "10.0.0.0/24")
        #expect(hosts.count == 254)
        #expect(hosts.first == "10.0.0.1")
        #expect(hosts.last == "10.0.0.254")
    }

    @Test("hostsInSubnet /16 returns empty (too large)")
    func hostsInSubnet16ReturnsEmpty() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "10.0.0.0/16")
        #expect(hosts.isEmpty)
    }

    @Test("hostsInSubnet /15 returns empty (too large)")
    func hostsInSubnet15ReturnsEmpty() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "10.0.0.0/15")
        #expect(hosts.isEmpty)
    }

    @Test("hostsInSubnet /32 returns empty (no hosts)")
    func hostsInSubnet32ReturnsEmpty() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "192.168.1.1/32")
        #expect(hosts.isEmpty)
    }

    @Test("hostsInSubnet /31 returns empty (no usable hosts)")
    func hostsInSubnet31ReturnsEmpty() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "192.168.1.0/31")
        #expect(hosts.isEmpty)
    }

    @Test("hostsInSubnet invalid CIDR returns empty")
    func hostsInSubnetInvalidReturnsEmpty() {
        #expect(IPv4Helpers.hostsInSubnet(cidr: "invalid").isEmpty)
        #expect(IPv4Helpers.hostsInSubnet(cidr: "256.0.0.0/24").isEmpty)
        #expect(IPv4Helpers.hostsInSubnet(cidr: "192.168.1.0/33").isEmpty)
        #expect(IPv4Helpers.hostsInSubnet(cidr: "").isEmpty)
    }

    @Test("hostsInSubnet handles non-zero network addresses")
    func hostsInSubnetNonZeroNetwork() {
        let hosts = IPv4Helpers.hostsInSubnet(cidr: "192.168.5.0/30")
        #expect(hosts.count == 2)
        #expect(hosts[0] == "192.168.5.1")
        #expect(hosts[1] == "192.168.5.2")
    }
}
