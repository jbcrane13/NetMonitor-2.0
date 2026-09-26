import Foundation
import Testing
@testable import NetMonitorCore

/// End-to-end tests for `WHOISService.lookup(query:)` covering both paths:
///
/// 1. **RDAP primary** — `URLSession` is intercepted via `MockURLProtocol` so no real
///    network call is made. Covers the registry+registrar merge and IP network lookup.
/// 2. **Port-43 fallback with referral-following** — the injected `URLSession` is made
///    to fail every RDAP request (HTTP 500), forcing `WHOISService` down to the
///    `WHOISTransport` fallback, which is a `FakeWHOISTransport` keyed by captured
///    real-world fixtures (Verisign thin → MarkMonitor registrar; IANA `refer:` → the
///    TLD registry; IANA `refer:` → ARIN for an IP).
///
/// All fixtures were captured from live `curl`/`whois` output (see PR description) and
/// are replayed here — no test in this file touches the network.
@Suite(.serialized)
struct WHOISServiceOrchestrationTests {

    // MARK: - Fixture loading

    private func loadFixture(_ name: String) throws -> String {
        try MockURLProtocol.loadFixture(named: name)
    }

    /// A `URLSession` whose RDAP requests are routed by URL substring to fixture files.
    /// `rdap.org/domain/<x>` and `rdap.org/ip/<x>` are the bootstrap entry points;
    /// registrar-referral hops are matched by host.
    private func rdapSession(routes: [String: String]) -> URLSession {
        MockURLProtocol.makeSession { request in
            let path = request.url?.absoluteString ?? ""
            for (substring, fixture) in routes where path.contains(substring) {
                let data = try? Data(MockURLProtocol.loadFixture(named: fixture).utf8)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://rdap.org")!,
                    statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/rdap+json"]
                )!
                return (response, data ?? Data())
            }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://rdap.org")!,
                statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
    }

    /// A `URLSession` that fails every request with HTTP 500, forcing the WHOIS-43 fallback.
    private func failingRDAPSession() -> URLSession {
        MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://rdap.org")!,
                statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
    }

    // MARK: - RDAP: example.com (no referral needed — already full detail)

    @Test("RDAP lookup for example.com returns full detail without a registrar hop")
    func rdapExampleComFullDetail() async throws {
        let session = rdapSession(routes: ["rdap.org/domain/example.com": "rdap-domain-example-com.json"])
        let service = WHOISService(session: session, transport: FakeWHOISTransport(responses: [:]))

        let result = try await service.lookup(query: "example.com")

        #expect(result.registrar == "RESERVED-Internet Assigned Numbers Authority")
        #expect(result.registrarIANAID == "376")
        #expect(result.nameServers.count == 2)
        #expect(result.dnssec == "signed")
        #expect(result.creationDate != nil)
        #expect(result.expirationDate != nil)
        #expect(result.status.contains("client delete prohibited"))
        #expect(!result.rawData.isEmpty)
    }

    // MARK: - RDAP: google.com registry + registrar referral merged

    @Test("RDAP lookup for google.com follows the registrar referral and merges registrant detail")
    func rdapGoogleComMergesRegistrarReferral() async throws {
        let session = rdapSession(routes: [
            "rdap.org/domain/google.com": "rdap-domain-google-com-registry.json",
            "rdap.markmonitor.com": "rdap-domain-google-com-registrar.json"
        ])
        let service = WHOISService(session: session, transport: FakeWHOISTransport(responses: [:]))

        let result = try await service.lookup(query: "google.com")

        // From the registry (thin) response:
        #expect(result.registrar == "MarkMonitor Inc.")
        #expect(result.registrarURL == "http://www.markmonitor.com")
        #expect(result.abuseEmail == "abusecomplaints@markmonitor.com")
        #expect(result.nameServers.count == 4)

        // Only present after following the registrar RDAP referral:
        #expect(result.registrantOrganization == "Google LLC")
        // Country is disclosed via the adr `cc` param even though the street address is redacted.
        #expect(result.registrantCountry == "US")

        #expect(result.rawData.contains("Registrar RDAP referral"))
    }

    // MARK: - RDAP: IP network (8.8.8.8)

    @Test("RDAP lookup for an IP address returns network range, org, and abuse contact")
    func rdapIPNetworkLookup() async throws {
        let session = rdapSession(routes: ["rdap.org/ip/8.8.8.8": "rdap-ip-8-8-8-8.json"])
        let service = WHOISService(session: session, transport: FakeWHOISTransport(responses: [:]))

        let result = try await service.lookup(query: "8.8.8.8")

        #expect(result.isIPNetworkResult == true)
        #expect(result.networkRange == "8.8.8.0 - 8.8.8.255")
        #expect(result.networkName == "GOGL")
        #expect(result.networkOrganization == "Google LLC")
        #expect(result.abuseEmail == "network-abuse@google.com")
    }

    // MARK: - Port-43 fallback: Verisign thin -> registrar referral merged

    @Test("When RDAP is unavailable, WHOIS-43 follows the registrar referral and merges fields")
    func whois43FollowsRegistrarReferral() async throws {
        let thin = try loadFixture("whois-verisign-google-com-thin.txt")
        let registrarLevel = try loadFixture("whois-markmonitor-google-com.txt")

        let transport = FakeWHOISTransport(responses: [
            FakeWHOISTransport.key(server: "whois.verisign-grs.com", query: "google.com"): thin,
            FakeWHOISTransport.key(server: "whois.markmonitor.com", query: "google.com"): registrarLevel
        ])
        let service = WHOISService(session: failingRDAPSession(), transport: transport)

        let result = try await service.lookup(query: "google.com")

        #expect(result.registrar == "MarkMonitor Inc.")
        // Only the registrar-level response has these fields.
        #expect(result.registrantOrganization == "Google LLC")
        #expect(result.registrantCountry == "US")
        // Both responses list the same 4 nameservers in different case/order — must be deduped.
        #expect(result.nameServers.count == 4)
        #expect(result.rawData.contains("Referred to whois.markmonitor.com"))
        #expect(transport.queriedServers == ["whois.verisign-grs.com", "whois.markmonitor.com"])
    }

    // MARK: - Port-43 fallback: IANA refer: followed for an unmapped TLD

    @Test("When RDAP is unavailable, an IANA refer: line is followed to the TLD registry")
    func whois43FollowsIANAReferForUnknownTLD() async throws {
        let ianaRefer = try loadFixture("whois-iana-refer-xyz.txt")
        let registryResponse = try loadFixture("whois-nic-xyz-nicxyz.txt")

        let transport = FakeWHOISTransport(responses: [
            FakeWHOISTransport.key(server: "whois.iana.org", query: "nic.xyz"): ianaRefer,
            FakeWHOISTransport.key(server: "whois.nic.xyz", query: "nic.xyz"): registryResponse
        ])
        let service = WHOISService(session: failingRDAPSession(), transport: transport)

        let result = try await service.lookup(query: "nic.xyz")

        #expect(result.registrar == "XYZ.com, LLC")
        #expect(result.registrarIANAID == "9999")
        #expect(result.registrarURL == "https://gen.xyz/")
        #expect(result.abuseEmail == "xyz_abuse@gen.xyz")
        #expect(result.dnssec == "unsigned")
        #expect(result.nameServers.count == 4)
        #expect(transport.queriedServers == ["whois.iana.org", "whois.nic.xyz"])
    }

    // MARK: - Port-43 fallback: IANA refer: followed for an IP, ARIN response parsed

    @Test("When RDAP is unavailable, an IP's IANA referral to ARIN is followed and parsed")
    func whois43FollowsIANAReferralToARINForIP() async throws {
        let ianaRefer = try loadFixture("whois-iana-refer-ip.txt")
        let arinResponse = try loadFixture("whois-arin-8-8-8-8.txt")

        let transport = FakeWHOISTransport(responses: [
            FakeWHOISTransport.key(server: "whois.iana.org", query: "8.8.8.8"): ianaRefer,
            FakeWHOISTransport.key(server: "whois.arin.net", query: "8.8.8.8"): arinResponse
        ])
        let service = WHOISService(session: failingRDAPSession(), transport: transport)

        let result = try await service.lookup(query: "8.8.8.8")

        #expect(result.networkRange == "8.8.8.0/24")
        #expect(result.networkOrganization == "Google LLC")
        #expect(result.abuseEmail == "network-abuse@google.com")
        #expect(result.abusePhone == "+1-650-253-0000")
        #expect(transport.queriedServers == ["whois.iana.org", "whois.arin.net"])
    }

    // MARK: - Referral hygiene

    @Test("referralServer ignores an empty or self-referential value")
    func referralServerSkipsSelfReference() {
        let service = WHOISService(session: failingRDAPSession(), transport: FakeWHOISTransport(responses: [:]))
        let selfReferential = "Registrar WHOIS Server: whois.verisign-grs.com"
        let referral = service.referralServer(from: selfReferential, currentServer: "whois.verisign-grs.com")
        #expect(referral == nil)
    }

    @Test("referralServer strips a scheme prefix from the referred host")
    func referralServerStripsScheme() {
        let service = WHOISService(session: failingRDAPSession(), transport: FakeWHOISTransport(responses: [:]))
        let raw = "refer:        https://whois.example-registry.net"
        let referral = service.referralServer(from: raw, currentServer: "whois.iana.org")
        #expect(referral == "whois.example-registry.net")
    }

    // MARK: - DNSSEC normalization (port-43 wording differs from RDAP's "signed"/"unsigned")

    @Test("whois43 normalizes 'signedDelegation' wording to 'signed'")
    func whois43NormalizesSignedDelegation() async throws {
        let transport = FakeWHOISTransport(responses: [
            FakeWHOISTransport.key(server: "whois.iana.org", query: "example.test"): """
            Domain Name: EXAMPLE.TEST
            DNSSEC: signedDelegation
            """
        ])
        let service = WHOISService(session: failingRDAPSession(), transport: transport)

        let result = try await service.lookup(query: "example.test")
        #expect(result.dnssec == "signed")
    }
}
