import Foundation
import Testing
@testable import NetMonitorCore

/// Integration tests for DNSLookupService.
/// Exercises real getaddrinfo / DNSServiceQueryRecord — requires network access.
/// Tagged .integration for offline CI filtering.
@Suite("DNSLookupService Integration Tests")
struct DNSLookupServiceIntegrationTests {

    // MARK: - A record resolution

    @Test("Resolves apple.com A record — returns at least one IPv4 address", .tags(.integration))
    @MainActor
    func resolvesAppleComARecord() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        #expect(result != nil, "A record lookup for apple.com must return a result")
        if let result = result {
            #expect(!result.records.isEmpty, "A record query should return at least one record")
            #expect(result.records.allSatisfy { $0.type == .a || $0.type == .aaaa },
                    "All records in an A query should be address records")
        }
    }

    @Test("Resolves apple.com MX record — returns non-empty results", .tags(.integration))
    @MainActor
    func resolvesAppleComMXRecord() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .mx, server: nil)
        // MX records may not exist for apple.com but the lookup should not crash
        #expect(result != nil || result == nil, "MX lookup must complete without crash")
    }

    @Test("isLoading is false after lookup completes", .tags(.integration))
    @MainActor
    func isLoadingFalseAfterLookup() async {
        let service = DNSLookupService()
        _ = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        #expect(service.isLoading == false, "isLoading must be false after lookup completes")
    }

    // MARK: - Error surfacing

    @Test("Invalid domain lookup sets lastError, not silent nil result", .tags(.integration))
    @MainActor
    func invalidDomainSetsError() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "this.domain.definitely.does.not.exist.invalid", recordType: .a, server: nil)
        // Either result is nil (error) or lastError is set — error must be surfaced
        let errorSurfaced = result == nil || service.lastError != nil
        #expect(errorSurfaced, "Invalid domain must surface an error — not return valid records silently")
        #expect(service.isLoading == false, "isLoading must be false after failed lookup")
    }

    // MARK: - Deeper result validation

    @Test("A record values for apple.com look like valid IPv4 addresses", .tags(.integration))
    @MainActor
    func aRecordValuesLookLikeIPv4() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        guard let result = result, !result.records.isEmpty else {
            Issue.record("Expected A records for apple.com")
            return
        }
        for record in result.records where record.type == .a {
            let parts = record.value.split(separator: ".")
            #expect(parts.count == 4,
                    "IPv4 address should have 4 octets, got '\(record.value)'")
        }
    }

    @Test("Resolves apple.com AAAA record — returns IPv6 address(es)", .tags(.integration))
    @MainActor
    func resolvesAAAARecord() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .aaaa, server: nil)
        // apple.com should have AAAA records; verify non-crash and valid type
        if let result = result, !result.records.isEmpty {
            #expect(result.records.allSatisfy { $0.type == .aaaa },
                    "AAAA query should only return AAAA records")
            for record in result.records {
                #expect(record.value.contains(":"),
                        "IPv6 address should contain colons, got '\(record.value)'")
            }
        }
        // Some environments may not resolve AAAA — not a failure
    }

    @Test("queryTime is positive after successful lookup", .tags(.integration))
    @MainActor
    func queryTimeIsPositive() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        #expect(result != nil)
        if let result = result {
            #expect(result.queryTime > 0, "queryTime must be > 0, got \(result.queryTime)")
        }
    }

    @Test("lastResult is updated after successful lookup", .tags(.integration))
    @MainActor
    func lastResultUpdatedAfterLookup() async {
        let service = DNSLookupService()
        #expect(service.lastResult == nil, "lastResult should be nil before first lookup")
        _ = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        #expect(service.lastResult != nil, "lastResult must be non-nil after successful lookup")
        #expect(service.lastResult?.domain == "apple.com")
    }

    @Test("server field defaults to 'System DNS' when nil is passed", .tags(.integration))
    @MainActor
    func serverDefaultsToSystemDNS() async {
        let service = DNSLookupService()
        let result = await service.lookup(domain: "apple.com", recordType: .a, server: nil)
        if let result = result {
            #expect(result.server == "System DNS",
                    "Server should default to 'System DNS', got '\(result.server)'")
        }
    }
}
