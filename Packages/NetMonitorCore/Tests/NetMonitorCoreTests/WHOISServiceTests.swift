import Testing
@testable import NetMonitorCore

/// Tests for WHOISService pure logic: TLD-based server selection.
/// Network-dependent WHOIS queries (NWConnection) are excluded.
@Suite("WHOISService")
struct WHOISServiceTests {

    // MARK: - TLD → WHOIS server selection

    @Test(".com domain uses Verisign server")
    func comDomainUsesVerisign() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.com")
        #expect(server == "whois.verisign-grs.com")
    }

    @Test(".net domain uses Verisign server")
    func netDomainUsesVerisign() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.net")
        #expect(server == "whois.verisign-grs.com")
    }

    @Test(".org domain uses PIR server")
    func orgDomainUsesPIR() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.org")
        #expect(server == "whois.pir.org")
    }

    @Test(".io domain uses NIC.io server")
    func ioDomainUsesNICio() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.io")
        #expect(server == "whois.nic.io")
    }

    @Test(".dev domain uses Google NIC server")
    func devDomainUsesGoogleNIC() async {
        let service = WHOISService()
        let server = await service.serverForDomain("myapp.dev")
        #expect(server == "whois.nic.google")
    }

    @Test(".app domain uses Google NIC server")
    func appDomainUsesGoogleNIC() async {
        let service = WHOISService()
        let server = await service.serverForDomain("myapp.app")
        #expect(server == "whois.nic.google")
    }

    @Test(".co domain uses NIC.co server")
    func coDomainUsesNICco() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.co")
        #expect(server == "whois.nic.co")
    }

    @Test("unknown TLD falls back to IANA default server")
    func unknownTLDFallsBackToIANA() async {
        let service = WHOISService()
        let server = await service.serverForDomain("example.xyz")
        #expect(server == "whois.iana.org")
    }

    @Test("subdomain uses TLD of the full domain string")
    func subdomainUsesCorrectTLD() async {
        let service = WHOISService()
        // "sub.example.com" — last component is "com"
        let server = await service.serverForDomain("sub.example.com")
        #expect(server == "whois.verisign-grs.com")
    }

    @Test("server lookup is case-insensitive")
    func serverLookupIsCaseInsensitive() async {
        let service = WHOISService()
        let server = await service.serverForDomain("EXAMPLE.COM")
        #expect(server == "whois.verisign-grs.com")
    }

    @Test("empty string falls back to IANA default server")
    func emptyStringFallsBackToIANA() async {
        let service = WHOISService()
        let server = await service.serverForDomain("")
        #expect(server == "whois.iana.org")
    }

    // MARK: - Service configuration

    @Test("default WHOIS port is 43")
    func defaultWhoisPortIs43() async {
        let service = WHOISService()
        let port = await service.whoisPort
        #expect(port == 43)
    }

    @Test("default server is whois.iana.org")
    func defaultServerIsIANA() async {
        let service = WHOISService()
        let server = await service.defaultServer
        #expect(server == "whois.iana.org")
    }
}
