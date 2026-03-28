import Testing
import Foundation
@testable import NetworkScanKit

/// DeviceNameResolver tests.
///
/// The resolver performs DNS PTR lookups via getnameinfo with a 3-second timeout.
/// Most tests here exercise the resolution logic against known IPs and verify
/// timeout/graceful-failure behavior.
///
/// Note: Tests tagged .integration depend on the host's DNS resolver and may
/// produce different results in different environments.

struct DeviceNameResolverTests {

    // MARK: - Construction

    @Test("DeviceNameResolver can be constructed")
    func construction() {
        let resolver = DeviceNameResolver()
        _ = resolver
    }

    // MARK: - Known IP resolution (localhost)

    @Test("Resolves 127.0.0.1 to localhost or similar hostname", .tags(.integration))
    func resolvesLocalhostIP() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "127.0.0.1")
        // Most systems resolve 127.0.0.1 to "localhost" or a variant
        #expect(result != nil, "127.0.0.1 should resolve to a hostname on most systems")
        if let result {
            #expect(result.lowercased().contains("localhost") || !result.isEmpty)
        }
    }

    // MARK: - Unknown/invalid IP graceful handling

    @Test("Returns nil for unresolvable RFC 5737 documentation IP")
    func unresolvedIPReturnsNil() async {
        let resolver = DeviceNameResolver()
        // 192.0.2.1 is TEST-NET-1 (RFC 5737) — unlikely to have PTR records
        let result = await resolver.resolve(ipAddress: "192.0.2.1")
        #expect(result == nil, "Documentation IP should not resolve to a hostname")
    }

    @Test("Returns nil for invalid IP address string")
    func invalidIPReturnsNil() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "not-an-ip")
        #expect(result == nil, "Invalid IP string should return nil")
    }

    @Test("Returns nil for empty IP address string")
    func emptyIPReturnsNil() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "")
        #expect(result == nil, "Empty IP string should return nil")
    }

    @Test("Returns nil for IPv6 address (only IPv4 supported)")
    func ipv6ReturnsNil() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "::1")
        #expect(result == nil, "IPv6 address should return nil (resolver uses AF_INET only)")
    }

    @Test("Returns nil for partial IP address")
    func partialIPReturnsNil() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "192.168")
        #expect(result == nil, "Partial IP should return nil")
    }

    // MARK: - Timeout behavior

    @Test("Resolver completes within reasonable time for unreachable IP")
    func completesWithinTimeout() async {
        let resolver = DeviceNameResolver()
        let start = ContinuousClock.now

        // Use a non-routable IP to test timeout behavior
        _ = await resolver.resolve(ipAddress: "198.51.100.1")

        let elapsed = ContinuousClock.now - start
        // Should complete within ~4 seconds (3s timeout + overhead)
        #expect(elapsed < .seconds(5), "Resolver should respect 3-second timeout")
    }

    // MARK: - Concurrent resolution

    @Test("Concurrent resolutions do not interfere with each other")
    func concurrentResolutions() async {
        let resolver = DeviceNameResolver()

        async let r1 = resolver.resolve(ipAddress: "127.0.0.1")
        async let r2 = resolver.resolve(ipAddress: "192.0.2.1")
        async let r3 = resolver.resolve(ipAddress: "not-valid")

        let results = await [r1, r2, r3]

        // 127.0.0.1 should resolve, others should not
        // Main point: no crash from concurrent use
        #expect(results[1] == nil)
        #expect(results[2] == nil)
    }

    @Test("Multiple sequential resolutions of same IP are consistent", .tags(.integration))
    func sequentialResolutionsConsistent() async {
        let resolver = DeviceNameResolver()

        let first = await resolver.resolve(ipAddress: "127.0.0.1")
        let second = await resolver.resolve(ipAddress: "127.0.0.1")

        #expect(first == second, "Same IP should resolve to same hostname")
    }

    // MARK: - Result filtering

    @Test("Resolver does not return IP as its own hostname")
    func doesNotReturnIPAsHostname() async {
        let resolver = DeviceNameResolver()
        // Use an IP unlikely to have reverse DNS
        let ip = "198.51.100.99"
        let result = await resolver.resolve(ipAddress: ip)
        // If resolved, the result must not be the IP itself
        if let result {
            #expect(result != ip, "Resolver should not return the IP as the hostname")
        }
    }

    @Test("Resolver does not return empty string as hostname")
    func doesNotReturnEmptyHostname() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "127.0.0.1")
        if let result {
            #expect(!result.isEmpty, "Resolved hostname should not be empty")
        }
    }

    // MARK: - Sendable conformance

    @Test("DeviceNameResolver is Sendable and can be shared across tasks")
    func sendableConformance() async {
        let resolver = DeviceNameResolver()

        await withTaskGroup(of: String?.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await resolver.resolve(ipAddress: "192.0.2.\(i)")
                }
            }
            for await _ in group {
                // Just drain results — verifying no crash
            }
        }
    }
}
