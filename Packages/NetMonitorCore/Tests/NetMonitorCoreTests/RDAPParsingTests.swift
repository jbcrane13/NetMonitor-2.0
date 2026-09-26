import Foundation
import Testing
@testable import NetMonitorCore

/// Unit tests for the pure RDAP JSON parsing helpers (`RDAPJSONValue`, `parseRDAPVCard`,
/// `parseRDAPDate`, entity-tree role search) using captured fixtures — no network involved.
struct RDAPParsingTests {

    // MARK: - Fixture loading

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            throw NSError(domain: "RDAPParsingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        return try Data(contentsOf: url)
    }

    // MARK: - RDAP domain (example.com — IANA-reserved, full detail, no referral needed)

    @Test("RDAP example.com decodes registrar, dates, nameservers, status, secureDNS")
    func decodesExampleComDomainResponse() throws {
        let data = try loadFixture("rdap-domain-example-com.json")
        let response = try JSONDecoder().decode(RDAPDomainResponse.self, from: data)

        #expect(response.ldhName == "EXAMPLE.COM")
        #expect(response.status?.contains("client delete prohibited") == true)
        #expect(response.nameservers?.compactMap(\.ldhName).count == 2)
        #expect(response.secureDNS?.delegationSigned == true)
        #expect(response.events?.contains { $0.eventAction == "registration" } == true)

        let registrar = (response.entities ?? []).findFirst(role: "registrar")
        #expect(registrar != nil)
        let vcard = parseRDAPVCard(registrar?.vcardArray)
        #expect(vcard.fullName == "RESERVED-Internet Assigned Numbers Authority")
        #expect(registrar?.publicIds?.first { $0.type == "IANA Registrar ID" }?.identifier == "376")

        // The nested abuse entity's vcard fields are all empty strings in this fixture —
        // they must be treated as redacted/absent, not surfaced as empty text.
        let abuse = (response.entities ?? []).findFirst(role: "abuse")
        let abuseVCard = parseRDAPVCard(abuse?.vcardArray)
        #expect(abuseVCard.email == nil)
        #expect(abuseVCard.phone == nil)

        // example.com has no "related" registrar RDAP link — registrar data is already complete.
        #expect(response.links?.contains { $0.rel == "related" } != true)
    }

    // MARK: - RDAP domain (google.com registry-level — thin, no registrant entity)

    @Test("RDAP google.com registry response has a related registrar RDAP link and no registrant")
    func decodesGoogleComRegistryResponse() throws {
        let data = try loadFixture("rdap-domain-google-com-registry.json")
        let response = try JSONDecoder().decode(RDAPDomainResponse.self, from: data)

        let relatedLink = response.links?.first { $0.rel == "related" }
        #expect(relatedLink?.href == "https://rdap.markmonitor.com/rdap/domain/GOOGLE.COM")

        #expect((response.entities ?? []).findFirst(role: "registrant") == nil)

        let registrar = (response.entities ?? []).findFirst(role: "registrar")
        let vcard = parseRDAPVCard(registrar?.vcardArray)
        #expect(vcard.fullName == "MarkMonitor Inc.")

        let abuse = (response.entities ?? []).findFirst(role: "abuse")
        let abuseVCard = parseRDAPVCard(abuse?.vcardArray)
        #expect(abuseVCard.email == "abusecomplaints@markmonitor.com")
        #expect(abuseVCard.phone == "+1.2086851750")
    }

    // MARK: - RDAP domain (google.com registrar-level — has registrant, but redacted)

    @Test("RDAP registrar-level response exposes registrant org while redacting PII")
    func decodesGoogleComRegistrarResponseWithRedaction() throws {
        let data = try loadFixture("rdap-domain-google-com-registrar.json")
        let response = try JSONDecoder().decode(RDAPDomainResponse.self, from: data)

        let registrant = (response.entities ?? []).findFirst(role: "registrant")
        #expect(registrant != nil)

        let vcard = parseRDAPVCard(registrant?.vcardArray)
        // "org" is real data, not a redaction placeholder.
        #expect(vcard.organization == "Google LLC")
        // "fn", "tel", and "email" are literally "REDACTED..." / "REDACTED FOR PRIVACY" — must be nil.
        #expect(vcard.fullName == nil)
        #expect(vcard.phone == nil)
        #expect(vcard.email == nil)
        // adr's array elements are all "REDACTED FOR PRIVACY" placeholders, but the
        // registry still discloses the country via the adr `cc` param — not itself PII.
        #expect(vcard.country == "US")
    }

    // MARK: - RDAP IP network (8.8.8.8 — ARIN)

    @Test("RDAP 8.8.8.8 decodes network range, org, abuse contact")
    func decodesIPNetworkResponse() throws {
        let data = try loadFixture("rdap-ip-8-8-8-8.json")
        let response = try JSONDecoder().decode(RDAPIPNetworkResponse.self, from: data)

        #expect(response.startAddress == "8.8.8.0")
        #expect(response.endAddress == "8.8.8.255")
        #expect(response.name == "GOGL")

        let entities = response.entities ?? []
        let registrant = entities.findFirst(role: "registrant") ?? entities.first
        let vcard = parseRDAPVCard(registrant?.vcardArray)
        // This entity's vcard has "fn" (not "org") set to the organization name.
        #expect(vcard.fullName == "Google LLC")

        let abuse = entities.findFirst(role: "abuse")
        let abuseVCard = parseRDAPVCard(abuse?.vcardArray)
        #expect(abuseVCard.email == "network-abuse@google.com")
        #expect(abuseVCard.phone == "+1-650-253-0000")
    }

    // MARK: - RDAP date parsing

    @Test("parseRDAPDate handles a bare Z-suffixed timestamp")
    func parsesZSuffixedDate() {
        let date = parseRDAPDate("2028-08-13T04:00:00Z")
        #expect(date != nil)
        let year = Calendar.current.component(.year, from: date!)
        #expect(year == 2028)
    }

    @Test("parseRDAPDate handles fractional seconds with a numeric offset")
    func parsesFractionalSecondsWithOffset() {
        let date = parseRDAPDate("2024-08-02T02:17:33.123-04:00")
        #expect(date != nil)
    }

    @Test("parseRDAPDate returns nil for garbage input")
    func returnsNilForGarbage() {
        #expect(parseRDAPDate("not-a-date") == nil)
        #expect(parseRDAPDate(nil) == nil)
    }

    // MARK: - RDAPJSONValue

    @Test("RDAPJSONValue decodes mixed vcard property shapes")
    func decodesMixedShapes() throws {
        let json = """
        ["vcard", [
            ["version", {}, "text", "4.0"],
            ["fn", {}, "text", "Example"],
            ["adr", {"cc": "US"}, "text", ["", "", "", "", "CA", "", "US"]]
        ]]
        """
        let value = try JSONDecoder().decode(RDAPJSONValue.self, from: Data(json.utf8))
        let fields = parseRDAPVCard(value)
        #expect(fields.fullName == "Example")
        #expect(fields.region == "CA")
        #expect(fields.country == "US")
    }
}
