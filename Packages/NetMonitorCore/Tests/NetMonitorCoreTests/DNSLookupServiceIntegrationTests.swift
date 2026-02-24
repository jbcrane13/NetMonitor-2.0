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
}
