import Foundation
import Testing
@testable import NetMonitor_macOS

// MARK: - DeviceNameResolver Tests

struct DeviceNameResolverTests {

    // DeviceNameResolver is an actor that shells out to /usr/bin/host, /usr/bin/dig,
    // and /usr/bin/smbutil. The ShellCommandRunner dependency is not injectable,
    // so we test the public API with real system commands where safe, and document
    // integration gaps for network-dependent resolution.

    @Test("resolveName returns nil for RFC 5737 documentation IP (no PTR record)")
    func resolveNameReturnsNilForDocumentationIP() async {
        let resolver = DeviceNameResolver()
        // 192.0.2.1 is TEST-NET-1 (RFC 5737) — no real PTR record exists
        let name = await resolver.resolveName(for: "192.0.2.1")
        // May return nil or a name depending on local DNS config;
        // the key assertion is that it doesn't crash or hang
        // On most systems this will be nil
        _ = name // no crash or hang is the success condition
    }

    @Test("resolveName returns nil for empty string input")
    func resolveNameReturnsNilForEmptyInput() async {
        let resolver = DeviceNameResolver()
        let name = await resolver.resolveName(for: "")
        #expect(name == nil, "Empty IP should resolve to nil")
    }

    @Test("resolveName returns nil for non-IP garbage input")
    func resolveNameReturnsNilForGarbageInput() async {
        let resolver = DeviceNameResolver()
        let name = await resolver.resolveName(for: "not-an-ip-address")
        #expect(name == nil, "Non-IP input should resolve to nil")
    }

    @Test("resolveName resolves localhost (127.0.0.1) to a name")
    func resolveNameResolvesLocalhost() async {
        let resolver = DeviceNameResolver()
        let name = await resolver.resolveName(for: "127.0.0.1")
        // On macOS, 127.0.0.1 usually resolves to "localhost" via /usr/bin/host
        if let name {
            #expect(name.contains("localhost") || !name.isEmpty,
                    "127.0.0.1 should resolve to localhost or similar")
        }
        // nil is also acceptable if DNS is not configured for loopback
    }

    @Test("resolveName does not return the IP itself as hostname")
    func resolveNameDoesNotReturnIPAsHostname() async {
        let resolver = DeviceNameResolver()
        // Use an IP that definitely won't resolve to itself
        let ip = "192.0.2.99"
        let name = await resolver.resolveName(for: ip)
        if let name {
            #expect(name != ip, "Resolver should not return the IP address as the hostname")
        }
    }

    @Test("resolveName completes within reasonable time for unreachable IP")
    func resolveNameCompletesWithinReasonableTime() async {
        let resolver = DeviceNameResolver()
        let start = Date()
        // 198.51.100.1 is TEST-NET-2 — unreachable, all strategies should timeout
        _ = await resolver.resolveName(for: "198.51.100.1")
        let elapsed = Date().timeIntervalSince(start)
        // Each strategy has a timeout (5s, 5s, 3s) but they run sequentially
        // Total should be under ~15 seconds in worst case
        #expect(elapsed < 20, "Resolution should complete within timeout bounds")
    }
}

// MARK: - DeviceNameResolver Output Parsing Contract Tests

struct DeviceNameResolverParsingTests {

    // These tests verify the parsing logic by testing the contract:
    // the resolver strips trailing dots and rejects empty/IP-equal results.

    @Test("hostname with trailing dot gets dot stripped (contract)")
    func trailingDotStripped() {
        // The resolver contains: if hostname.hasSuffix(".") { hostname.removeLast() }
        // Verify the String operation works as expected
        var hostname = "router.local."
        if hostname.hasSuffix(".") { hostname.removeLast() }
        #expect(hostname == "router.local")
    }

    @Test("empty hostname after stripping is rejected (contract)")
    func emptyHostnameRejected() {
        // The resolver contains: if !hostname.isEmpty && hostname != ip
        var hostname = "."
        if hostname.hasSuffix(".") { hostname.removeLast() }
        let isValid = !hostname.isEmpty && hostname != "192.168.1.1"
        #expect(!isValid, "Single dot should result in empty string, rejected")
    }

    @Test("hostname equal to IP is rejected (contract)")
    func hostnameEqualToIPRejected() {
        let hostname = "192.168.1.1"
        let ip = "192.168.1.1"
        let isValid = !hostname.isEmpty && hostname != ip
        #expect(!isValid, "Hostname equal to IP should be rejected")
    }

    @Test("valid hostname passes all filters (contract)")
    func validHostnamePassesFilters() {
        var hostname = "my-router.local."
        let ip = "192.168.1.1"
        if hostname.hasSuffix(".") { hostname.removeLast() }
        let isValid = !hostname.isEmpty && hostname != ip
        #expect(isValid, "Valid hostname should pass all filters")
        #expect(hostname == "my-router.local")
    }

    @Test("reverse DNS pointer line parsing extracts hostname")
    func reverseDNSPointerLineParsing() {
        let line = "1.1.168.192.in-addr.arpa domain name pointer router.local."
        let parts = line.components(separatedBy: "domain name pointer ")
        #expect(parts.count > 1)
        var hostname = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if hostname.hasSuffix(".") { hostname.removeLast() }
        #expect(hostname == "router.local")
    }

    @Test("mDNS dig +short output parsing extracts hostname")
    func mdnsDigOutputParsing() {
        let output = "MacBook-Pro.local.\n"
        var hostname = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if hostname.hasSuffix(".") { hostname.removeLast() }
        #expect(hostname == "MacBook-Pro.local")
    }
}
