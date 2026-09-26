import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

/// Tests that the WHOIS tool view model passes the new full-detail `WHOISResult`
/// fields (registrar detail, registrant detail, DNSSEC, and IP network fields)
/// through to `result` unchanged, for both domain and IP lookups — covering the
/// iOS side of issue #323 (RDAP full-detail results).
@MainActor
struct WHOISToolViewModelDetailFieldsTests {

    @Test func domainLookupPassesThroughRegistrarAndRegistrantDetail() async throws {
        let mock = MockWHOISService()
        mock.mockResult = WHOISResult(
            query: "google.com",
            registrar: "MarkMonitor Inc.",
            creationDate: Date(timeIntervalSince1970: 874_224_000),
            expirationDate: Date(timeIntervalSince1970: 1_852_876_800),
            nameServers: ["ns1.google.com", "ns2.google.com"],
            status: ["client delete prohibited"],
            rawData: "raw rdap json",
            registrarURL: "http://www.markmonitor.com",
            registrarIANAID: "292",
            abuseEmail: "abusecomplaints@markmonitor.com",
            abusePhone: "+1.2086851750",
            registrantOrganization: "Google LLC",
            registrantCountry: "US",
            dnssec: "unsigned"
        )

        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = "google.com"
        await vm.lookup()

        let result = try #require(vm.result)
        #expect(result.registrarURL == "http://www.markmonitor.com")
        #expect(result.registrarIANAID == "292")
        #expect(result.abuseEmail == "abusecomplaints@markmonitor.com")
        #expect(result.abusePhone == "+1.2086851750")
        #expect(result.registrantOrganization == "Google LLC")
        #expect(result.registrantCountry == "US")
        #expect(result.dnssec == "unsigned")
        #expect(result.isIPNetworkResult == false)
    }

    @Test func ipLookupPassesThroughNetworkFields() async throws {
        let mock = MockWHOISService()
        mock.mockResult = WHOISResult(
            query: "8.8.8.8",
            rawData: "raw rdap json",
            abuseEmail: "network-abuse@google.com",
            abusePhone: "+1-650-253-0000",
            registrantOrganization: "Google LLC",
            registrantCountry: "US",
            networkRange: "8.8.8.0 - 8.8.8.255",
            networkName: "GOGL",
            networkOrganization: "Google LLC",
            networkCountry: "US",
            asn: "AS15169"
        )

        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = "8.8.8.8"
        await vm.lookup()

        let result = try #require(vm.result)
        #expect(result.isIPNetworkResult == true)
        #expect(result.networkRange == "8.8.8.0 - 8.8.8.255")
        #expect(result.networkName == "GOGL")
        #expect(result.networkOrganization == "Google LLC")
        #expect(result.networkCountry == "US")
        #expect(result.asn == "AS15169")
    }

    @Test func resultWithNoDetailFieldsLeavesThemNil() async throws {
        let mock = MockWHOISService()
        mock.mockResult = WHOISResult(query: "example.com", rawData: "thin response")

        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = "example.com"
        await vm.lookup()

        let result = try #require(vm.result)
        #expect(result.registrarURL == nil)
        #expect(result.registrantOrganization == nil)
        #expect(result.dnssec == nil)
        #expect(result.isIPNetworkResult == false)
    }

    // MARK: - EPP status hints (reachable from the iOS target via NetMonitorCore)

    @Test func eppHintIsAvailableForCommonStatusCodes() {
        #expect(EPPStatusHints.hint(for: "client delete prohibited") != nil)
        #expect(EPPStatusHints.hint(for: "clientTransferProhibited https://icann.org/epp#clientTransferProhibited") != nil)
        #expect(EPPStatusHints.hint(for: "not-a-real-status") == nil)
    }
}
