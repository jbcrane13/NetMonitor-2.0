import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - WHOISService.serverForDomain Tests

struct WHOISServerForDomainTests {

    @Test("serverForDomain returns custom server for .com domain")
    func comDomainReturnsVerisign() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.com")
        #expect(server == "whois.verisign-grs.com")
    }

    @Test("serverForDomain returns custom server for .org domain")
    func orgDomainReturnsPIR() async {
        let service = WHOISService()
        let server = await service.serverForDomain("wikipedia.org")
        #expect(server == "whois.pir.org")
    }

    @Test("serverForDomain returns custom server for .io domain")
    func ioDomainReturnsNICIO() async {
        let service = WHOISService()
        let server = await service.serverForDomain("domain.io")
        #expect(server == "whois.nic.io")
    }

    @Test("serverForDomain returns default for unknown TLD")
    func unknownTLDReturnsDefault() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.xyz")
        #expect(server == "whois.iana.org")
    }

    @Test("serverForDomain is case-insensitive")
    func caseInsensitive() async {
        let service = WHOISService()
        let server1 = await service.serverForDomain("EXAMPLE.COM")
        let server2 = await service.serverForDomain("example.com")
        #expect(server1 == server2)
    }

    @Test("serverForDomain handles IP addresses by returning default")
    func ipAddressReturnsDefault() async {
        let service = WHOISService()
        let server = await service.serverForDomain("192.0.2.1")
        #expect(server == "whois.iana.org")
    }
}

// MARK: - WHOISService.parseField Tests

struct WHOISParseFieldTests {

    @Test("parseField extracts registrar from canonical WHOIS response")
    func extractsRegistrarField() {
        let service = WHOISService()
        let rawData = """
        Domain Name: EXAMPLE.COM
        Registrar: GoDaddy.com, LLC
        Admin Name: John Doe
        """
        let registrar = service.parseField(from: rawData, field: "Registrar")
        #expect(registrar == "GoDaddy.com, LLC")
    }

    @Test("parseField returns nil for missing field")
    func missingFieldReturnsNil() {
        let service = WHOISService()
        let rawData = "Domain Name: EXAMPLE.COM"
        let value = service.parseField(from: rawData, field: "Registrar")
        #expect(value == nil)
    }

    @Test("parseField is case-insensitive for field name")
    func caseInsensitiveFieldMatch() {
        let service = WHOISService()
        let rawData = "registrar: Example Registrar"
        let value = service.parseField(from: rawData, field: "Registrar")
        #expect(value == "Example Registrar")
    }

    @Test("parseField trims whitespace from value")
    func trimsWhitespace() {
        let service = WHOISService()
        let rawData = "Registrar:    Whitespace Registrar   "
        let value = service.parseField(from: rawData, field: "Registrar")
        #expect(value == "Whitespace Registrar")
    }

    @Test("parseField handles field with colon in value")
    func handlesColonInValue() {
        let service = WHOISService()
        let rawData = "Status: clientHold, clientTransferProhibited"
        let value = service.parseField(from: rawData, field: "Status")
        #expect(value == "clientHold, clientTransferProhibited")
    }
}

// MARK: - WHOISService.parseDate Tests

struct WHOISParseDateTests {

    @Test("parseDate parses ISO 8601 format with T separator")
    func parsesISO8601T() {
        let service = WHOISService()
        let rawData = "Creation Date: 2020-01-15T10:30:00Z"
        let date = service.parseDate(from: rawData, fields: ["Creation Date"])
        #expect(date != nil)
        // Verify approximate date (avoid timezone issues)
        guard let date = date else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2020)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test("parseDate parses simple YYYY-MM-DD format")
    func parsesSimpleDate() {
        let service = WHOISService()
        let rawData = "Registry Expiry Date: 2025-06-30"
        let date = service.parseDate(from: rawData, fields: ["Registry Expiry Date"])
        #expect(date != nil)
        guard let date = date else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2025)
        #expect(components.month == 6)
        #expect(components.day == 30)
    }

    @Test("parseDate parses DD-MMM-YYYY format")
    func parsesDDMMMYYYY() {
        let service = WHOISService()
        let rawData = "Updated Date: 01-FEB-2024"
        let date = service.parseDate(from: rawData, fields: ["Updated Date"])
        #expect(date != nil)
        guard let date = date else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2024)
        #expect(components.month == 2)
        #expect(components.day == 1)
    }

    @Test("parseDate returns nil for malformed date string")
    func malformedDateReturnsNil() {
        let service = WHOISService()
        let rawData = "Creation Date: not-a-valid-date"
        let date = service.parseDate(from: rawData, fields: ["Creation Date"])
        #expect(date == nil)
    }

    @Test("parseDate tries multiple field names")
    func triesMultipleFields() {
        let service = WHOISService()
        let rawData = "Created: 2020-05-10"
        let date = service.parseDate(from: rawData, fields: ["Creation Date", "Created"])
        #expect(date != nil)
        guard let date = date else { return }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        #expect(components.year == 2020)
        #expect(components.month == 5)
    }

    @Test("parseDate returns nil when no matching field found")
    func noMatchingFieldReturnsNil() {
        let service = WHOISService()
        let rawData = "Registrar: Example"
        let date = service.parseDate(from: rawData, fields: ["Creation Date", "Created"])
        #expect(date == nil)
    }
}

// MARK: - WHOISService.parseNameservers Tests

struct WHOISParseNameserversTests {

    @Test("parseNameservers extracts multiple nameservers")
    func extractsMultipleNameservers() {
        let service = WHOISService()
        let rawData = """
        Name Server: ns1.example.com
        Name Server: ns2.example.com
        Name Server: ns3.example.com
        """
        let nameservers = service.parseNameservers(from: rawData)
        #expect(nameservers.count == 3)
        #expect(nameservers.contains("ns1.example.com"))
        #expect(nameservers.contains("ns2.example.com"))
        #expect(nameservers.contains("ns3.example.com"))
    }

    @Test("parseNameservers converts to lowercase")
    func convertsToLowercase() {
        let service = WHOISService()
        let rawData = "Name Server: NS1.EXAMPLE.COM"
        let nameservers = service.parseNameservers(from: rawData)
        #expect(nameservers.count == 1)
        #expect(nameservers[0] == "ns1.example.com")
    }

    @Test("parseNameservers returns empty array when no nameservers found")
    func emptyArrayWhenNoneFound() {
        let service = WHOISService()
        let rawData = "Registrar: Example"
        let nameservers = service.parseNameservers(from: rawData)
        #expect(nameservers.isEmpty)
    }

    @Test("parseNameservers handles IP addresses as nameservers")
    func handlesIPAddresses() {
        let service = WHOISService()
        let rawData = """
        Name Server: 192.0.2.1
        Name Server: 192.0.2.2
        """
        let nameservers = service.parseNameservers(from: rawData)
        #expect(nameservers.count == 2)
        #expect(nameservers.contains("192.0.2.1"))
    }
}

// MARK: - WHOISService.parseStatus Tests

struct WHOISParseStatusTests {

    @Test("parseStatus extracts multiple domain statuses")
    func extractsMultipleStatuses() {
        let service = WHOISService()
        let rawData = """
        Domain Status: clientTransferProhibited
        Domain Status: clientHold
        Status: active
        """
        let statuses = service.parseStatus(from: rawData)
        #expect(statuses.count >= 2)
        #expect(statuses.contains("clientTransferProhibited"))
        #expect(statuses.contains("clientHold"))
    }

    @Test("parseStatus handles both 'Domain Status' and 'Status'")
    func handlesVariousStatusFields() {
        let service = WHOISService()
        let rawData = """
        Status: clientTransferProhibited
        """
        let statuses = service.parseStatus(from: rawData)
        #expect(statuses.count >= 1)
        #expect(statuses.contains("clientTransferProhibited"))
    }

    @Test("parseStatus returns empty array when no statuses found")
    func emptyArrayWhenNoneFound() {
        let service = WHOISService()
        let rawData = "Registrar: Example"
        let statuses = service.parseStatus(from: rawData)
        #expect(statuses.isEmpty)
    }
}

// MARK: - WHOISService.lookup Integration Tests (Network-Free)

struct WHOISLookupParsingTests {

    @Test("lookup parses canonical WHOIS response correctly")
    func parsesCanonicalResponse() throws {
        // This test validates the entire parsing pipeline without network.
        // We use parseField, parseDate, parseNameservers, parseStatus directly
        // to simulate what lookup() would construct.

        let service = WHOISService()

        let canonicalResponse = """
        Domain Name: EXAMPLE.COM
        Registry Domain ID: 2336799_DOMAIN_COM-VRSN
        Registrar WHOIS Server: whois.verisign-grs.com
        Registrar URL: http://www.verisign-grs.com
        Updated Date: 2024-01-20T08:15:00Z
        Creation Date: 2010-03-01T00:00:00Z
        Registry Expiry Date: 2025-03-01T00:00:00Z
        Registrar: VeriSign Global Registry Services
        Name Server: A.IANA-SERVERS.NET
        Name Server: B.IANA-SERVERS.NET
        Domain Status: clientDeleteProhibited
        Domain Status: clientTransferProhibited
        """

        // Verify parsing chain works correctly
        let registrar = service.parseField(from: canonicalResponse, field: "Registrar")
        #expect(registrar == "VeriSign Global Registry Services")

        let creationDate = service.parseDate(from: canonicalResponse, fields: ["Creation Date"])
        #expect(creationDate != nil)

        let nameservers = service.parseNameservers(from: canonicalResponse)
        #expect(nameservers.count == 2)

        let statuses = service.parseStatus(from: canonicalResponse)
        #expect(statuses.count >= 2)
    }

    @Test("lookup handles response with missing optional fields")
    func handlesPartialResponse() {
        let service = WHOISService()

        let minimalResponse = """
        Domain Name: EXAMPLE.NET
        Registrar: NetRegistry
        """

        let registrar = service.parseField(from: minimalResponse, field: "Registrar")
        #expect(registrar == "NetRegistry")

        let nameservers = service.parseNameservers(from: minimalResponse)
        #expect(nameservers.isEmpty)

        let statuses = service.parseStatus(from: minimalResponse)
        #expect(statuses.isEmpty)
    }

    @Test("lookup handles empty response gracefully")
    func handlesEmptyResponse() {
        let service = WHOISService()
        let emptyResponse = ""

        let registrar = service.parseField(from: emptyResponse, field: "Registrar")
        #expect(registrar == nil)

        let nameservers = service.parseNameservers(from: emptyResponse)
        #expect(nameservers.isEmpty)
    }
}

// MARK: - WHOISResult timestamp tests
// (WHOISResult is Sendable-only, not Codable — Codable round-trips removed.)

struct WHOISResultTimestampTests {

    @Test("WHOISResult queriedAt timestamp is set on init")
    func queriedAtTimestampIsSet() throws {
        let beforeInit = Date()
        let result = WHOISResult(
            query: "test.com",
            registrar: nil,
            creationDate: nil,
            expirationDate: nil,
            updatedDate: nil,
            nameServers: [],
            status: [],
            rawData: ""
        )
        let afterInit = Date()

        #expect(result.queriedAt >= beforeInit)
        #expect(result.queriedAt <= afterInit)
    }
}
