import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for WHOISService parser logic.
/// Uses a realistic fixture (TestFixtures/whois-example-com.txt) to verify
/// the real regex parser extracts fields correctly — no NWConnection involved.
///
/// The parse helpers are internal (nonisolated) so they can be called synchronously
/// without actor isolation.
struct WHOISServiceContractTests {

    // MARK: - Fixture loading

    private static let fixture: String = {
        guard let url = Bundle.module.url(forResource: "whois-example-com.txt", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }()

    private var fixture: String { Self.fixture }

    // MARK: - parseField

    @Test("parseField extracts Registrar from WHOIS fixture")
    func parseFieldExtractsRegistrar() {
        let service = WHOISService()
        let registrar = service.parseField(from: fixture, field: "Registrar")
        #expect(registrar != nil, "Registrar field must be present in fixture")
        #expect(registrar?.contains("Internet Assigned Numbers Authority") == true,
                "Expected IANA registrar, got: \(registrar ?? "nil")")
    }

    @Test("parseField returns nil for missing field")
    func parseFieldReturnsNilForMissingField() {
        let service = WHOISService()
        let result = service.parseField(from: fixture, field: "NonExistentField12345")
        #expect(result == nil)
    }

    @Test("parseField is case-insensitive for field name")
    func parseFieldIsCaseInsensitive() {
        let service = WHOISService()
        let lower = service.parseField(from: fixture, field: "registrar")
        let upper = service.parseField(from: fixture, field: "REGISTRAR")
        #expect(lower != nil)
        #expect(lower == upper)
    }

    @Test("parseField extracts Domain Name correctly")
    func parseFieldExtractsDomainName() {
        let service = WHOISService()
        let domain = service.parseField(from: fixture, field: "Domain Name")
        #expect(domain == "EXAMPLE.COM")
    }

    // MARK: - parseDate

    @Test("parseDate extracts Registry Expiry Date from fixture")
    func parseDateExtractsExpiryDate() {
        let service = WHOISService()
        let expiryDate = service.parseDate(from: fixture, fields: ["Registry Expiry Date", "Expiration Date"])
        #expect(expiryDate != nil, "Registry Expiry Date must parse from fixture")
        // Fixture expiry is 2028-08-13 — must be in the future
        let now = Date()
        #expect(expiryDate! > now, "Expiry date should be in the future (fixture: 2028-08-13)")
    }

    @Test("parseDate extracts Creation Date from fixture")
    func parseDateExtractsCreationDate() {
        let service = WHOISService()
        let creationDate = service.parseDate(from: fixture, fields: ["Creation Date", "Created"])
        #expect(creationDate != nil, "Creation Date must parse from fixture")
        // Fixture creation is 1995-08-14
        let calendar = Calendar.current
        let year = calendar.component(.year, from: creationDate!)
        #expect(year == 1995, "Creation year should be 1995, got: \(year)")
    }

    @Test("parseDate extracts Updated Date from fixture")
    func parseDateExtractsUpdatedDate() {
        let service = WHOISService()
        let updatedDate = service.parseDate(from: fixture, fields: ["Updated Date"])
        #expect(updatedDate != nil, "Updated Date must parse from fixture")
        let calendar = Calendar.current
        let year = calendar.component(.year, from: updatedDate!)
        #expect(year == 2023, "Updated year should be 2023, got: \(year)")
    }

    @Test("parseDate returns nil for missing date fields")
    func parseDateReturnsNilForMissingFields() {
        let service = WHOISService()
        let result = service.parseDate(from: fixture, fields: ["NonExistentDate"])
        #expect(result == nil)
    }

    @Test("parseDate handles ISO8601 format with Z suffix")
    func parseDateHandlesISO8601WithZ() {
        let service = WHOISService()
        let rawData = "Registry Expiry Date: 2030-01-15T12:00:00Z"
        let date = service.parseDate(from: rawData, fields: ["Registry Expiry Date"])
        #expect(date != nil, "ISO8601 date with Z suffix must parse")
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date!)
        #expect(year == 2030)
    }

    // MARK: - parseNameservers

    @Test("parseNameservers extracts both name servers from fixture")
    func parseNameserversExtractsBoth() {
        let service = WHOISService()
        let nameservers = service.parseNameservers(from: fixture)
        #expect(nameservers.count == 2, "Fixture has 2 name servers, got: \(nameservers.count)")
        #expect(nameservers.contains("a.iana-servers.net"),
                "Should contain a.iana-servers.net (lowercased), got: \(nameservers)")
        #expect(nameservers.contains("b.iana-servers.net"),
                "Should contain b.iana-servers.net (lowercased), got: \(nameservers)")
    }

    @Test("parseNameservers returns empty for text with no name servers")
    func parseNameserversReturnsEmptyForNoNameServers() {
        let service = WHOISService()
        let result = service.parseNameservers(from: "Domain Name: EXAMPLE.COM\nRegistrar: SomeRegistrar")
        #expect(result.isEmpty)
    }

    @Test("parseNameservers lowercases all entries")
    func parseNameserversLowercases() {
        let service = WHOISService()
        let rawData = "Name Server: NS1.EXAMPLE.COM\nName Server: NS2.EXAMPLE.COM"
        let nameservers = service.parseNameservers(from: rawData)
        #expect(nameservers.allSatisfy { $0 == $0.lowercased() },
                "All nameservers must be lowercased, got: \(nameservers)")
    }

    // MARK: - parseStatus

    @Test("parseStatus extracts three domain statuses from fixture")
    func parseStatusExtractsThreeStatuses() {
        let service = WHOISService()
        let statuses = service.parseStatus(from: fixture)
        #expect(statuses.count == 3, "Fixture has 3 Domain Status lines, got: \(statuses.count)")
    }

    @Test("parseStatus includes clientDeleteProhibited")
    func parseStatusIncludesDeleteProhibited() {
        let service = WHOISService()
        let statuses = service.parseStatus(from: fixture)
        #expect(statuses.contains { $0.contains("clientDeleteProhibited") })
    }

    @Test("parseStatus returns empty for text with no status")
    func parseStatusReturnsEmptyForNoStatus() {
        let service = WHOISService()
        let result = service.parseStatus(from: "Domain Name: EXAMPLE.COM")
        #expect(result.isEmpty)
    }

    // MARK: - Full lookup roundtrip (WHOISResult construction)

    @Test("WHOISResult constructed from parsed fixture fields has correct structure")
    func whoisResultFromParsedFields() {
        let service = WHOISService()
        let result = WHOISResult(
            query: "example.com",
            registrar: service.parseField(from: fixture, field: "Registrar"),
            creationDate: service.parseDate(from: fixture, fields: ["Creation Date", "Created"]),
            expirationDate: service.parseDate(from: fixture, fields: ["Registry Expiry Date", "Expiration Date"]),
            updatedDate: service.parseDate(from: fixture, fields: ["Updated Date"]),
            nameServers: service.parseNameservers(from: fixture),
            status: service.parseStatus(from: fixture),
            rawData: fixture
        )

        #expect(result.registrar?.contains("Internet Assigned Numbers Authority") == true)
        #expect(result.creationDate != nil)
        #expect(result.expirationDate != nil)
        #expect(result.expirationDate! > result.creationDate!)
        #expect(result.nameServers.count == 2)
        #expect(result.status.count == 3)
        #expect(!result.rawData.isEmpty)
    }
}

/// Integration tests — require real network access to a WHOIS server.
/// Tagged .integration so they can be excluded in offline CI environments.
struct WHOISServiceIntegrationTests {

    @Test("Real WHOIS lookup for google.com returns non-empty response", .tags(.integration))
    func realLookupForGoogleCom() async throws {
        let service = WHOISService()
        let result = try await service.lookup(query: "google.com")
        #expect(result.query == "google.com")
        #expect(!result.rawData.isEmpty, "Real WHOIS response must not be empty")
        // Registrar should be present for a registered domain
        #expect(result.registrar != nil, "google.com should have a registrar")
    }

    @Test("Real WHOIS lookup returns at least one nameserver for google.com", .tags(.integration))
    func realLookupHasNameservers() async throws {
        let service = WHOISService()
        let result = try await service.lookup(query: "google.com")
        #expect(!result.nameServers.isEmpty, "google.com should have nameservers in WHOIS")
    }

    @Test("Real WHOIS lookup for google.com has future expiry date", .tags(.integration))
    func realLookupHasFutureExpiry() async throws {
        let service = WHOISService()
        let result = try await service.lookup(query: "google.com")
        #expect(result.expirationDate != nil, "google.com should have an expiry date")
        if let expiry = result.expirationDate {
            #expect(expiry > Date(), "google.com expiry should be in the future")
        }
    }
}
