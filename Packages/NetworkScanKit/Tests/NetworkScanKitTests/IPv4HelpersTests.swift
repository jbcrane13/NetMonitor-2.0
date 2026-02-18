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
}
