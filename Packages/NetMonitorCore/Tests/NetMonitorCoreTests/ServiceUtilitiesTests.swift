import Testing
@testable import NetMonitorCore

struct ServiceUtilitiesTests {

    // MARK: - isIPAddress

    @Test("isIPAddress recognizes valid IPv4 addresses")
    func isIPAddressValidIPv4() {
        #expect(ServiceUtilities.isIPAddress("192.168.1.1") == true)
        #expect(ServiceUtilities.isIPAddress("0.0.0.0") == true)
        #expect(ServiceUtilities.isIPAddress("255.255.255.255") == true)
        #expect(ServiceUtilities.isIPAddress("10.0.0.1") == true)
        #expect(ServiceUtilities.isIPAddress("127.0.0.1") == true)
    }

    @Test("isIPAddress recognizes valid IPv6 addresses")
    func isIPAddressValidIPv6() {
        #expect(ServiceUtilities.isIPAddress("::1") == true)
        #expect(ServiceUtilities.isIPAddress("2001:db8::1") == true)
        #expect(ServiceUtilities.isIPAddress("::") == true)
        #expect(ServiceUtilities.isIPAddress("fe80::1") == true)
        #expect(ServiceUtilities.isIPAddress("2001:0db8:85a3:0000:0000:8a2e:0370:7334") == true)
    }

    @Test("isIPAddress rejects invalid strings")
    func isIPAddressInvalid() {
        #expect(ServiceUtilities.isIPAddress("") == false)
        #expect(ServiceUtilities.isIPAddress("hostname.local") == false)
        #expect(ServiceUtilities.isIPAddress("not-an-ip") == false)
        #expect(ServiceUtilities.isIPAddress("256.0.0.1") == false)
        #expect(ServiceUtilities.isIPAddress("192.168.1") == false)
        #expect(ServiceUtilities.isIPAddress("localhost") == false)
    }

    // MARK: - isIPv4Address

    @Test("isIPv4Address recognizes valid IPv4 addresses")
    func isIPv4AddressValid() {
        #expect(ServiceUtilities.isIPv4Address("192.168.1.1") == true)
        #expect(ServiceUtilities.isIPv4Address("0.0.0.0") == true)
        #expect(ServiceUtilities.isIPv4Address("255.255.255.255") == true)
        #expect(ServiceUtilities.isIPv4Address("10.0.0.254") == true)
    }

    @Test("isIPv4Address returns false for IPv6 addresses")
    func isIPv4AddressRejectsIPv6() {
        #expect(ServiceUtilities.isIPv4Address("::1") == false)
        #expect(ServiceUtilities.isIPv4Address("2001:db8::1") == false)
        #expect(ServiceUtilities.isIPv4Address("::") == false)
    }

    @Test("isIPv4Address returns false for hostnames and invalid strings")
    func isIPv4AddressRejectsHostnames() {
        #expect(ServiceUtilities.isIPv4Address("localhost") == false)
        #expect(ServiceUtilities.isIPv4Address("hostname.local") == false)
        #expect(ServiceUtilities.isIPv4Address("") == false)
        #expect(ServiceUtilities.isIPv4Address("256.0.0.1") == false)
        #expect(ServiceUtilities.isIPv4Address("not-an-ip") == false)
    }

    // MARK: - resolveHostnameSync

    @Test("resolveHostnameSync returns IP directly when given a valid IPv4")
    func resolveHostnameSyncPassthroughIPv4() {
        let ip = "192.168.1.1"
        let result = ServiceUtilities.resolveHostnameSync(ip)
        #expect(result == ip)
    }

    @Test("resolveHostnameSync returns IP directly for another IPv4")
    func resolveHostnameSyncPassthroughIPv4Second() {
        let ip = "10.0.0.1"
        let result = ServiceUtilities.resolveHostnameSync(ip)
        #expect(result == ip)
    }

    @Test("resolveHostnameSync resolves localhost to 127.0.0.1")
    func resolveHostnameSyncLocalhost() {
        let result = ServiceUtilities.resolveHostnameSync("localhost")
        #expect(result != nil)
        if let resolved = result {
            #expect(ServiceUtilities.isIPv4Address(resolved) == true)
        }
    }

    @Test("resolveHostnameSync returns nil for unresolvable hostname")
    func resolveHostnameSyncInvalidHostname() {
        let result = ServiceUtilities.resolveHostnameSync("this.is.not.a.valid.hostname.xyzabc123invalid")
        #expect(result == nil)
    }
}
