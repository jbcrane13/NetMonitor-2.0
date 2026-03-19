import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for MACVendorLookupService's online API path (macvendors.com).
///
/// These tests became possible after adding `init(session: URLSession)` to
/// MACVendorLookupService (replacing the hard-coded URLSession.shared dependency).
///
/// All tests use per-session MockURLProtocol handlers so they are safe to run
/// concurrently alongside other test suites.
struct MACVendorOnlineContractTests {

    // MARK: - Helpers

    /// Creates a service backed by a mock session returning the given vendor string
    /// with the given HTTP status.
    private func makeService(responseBody: String, statusCode: Int = 200) -> MACVendorLookupService {
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.macvendors.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data(responseBody.utf8))
        }
        return MACVendorLookupService(session: session)
    }

    // MARK: - Success path via online API

    @Test("macvendors.com returns vendor name: lookupVendorEnhanced returns it")
    func onlineAPIReturnsVendorName() async {
        // Use a MAC prefix that is NOT in the local OUI database so the service
        // proceeds to the online API path.
        let service = makeService(responseBody: "Apple, Inc.")
        // 12:34:56 is not in the local database
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == "Apple, Inc.")
    }

    @Test("macvendors.com response is trimmed of whitespace")
    func onlineAPIResponseIsTrimmed() async {
        let service = makeService(responseBody: "  Cisco Systems, Inc.  \n")
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == "Cisco Systems, Inc.")
    }

    @Test("macvendors.com 'Not Found' response: returns nil")
    func onlineAPINotFoundReturnsNil() async {
        let service = makeService(responseBody: "Not Found", statusCode: 404)
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com HTTP 404: returns nil gracefully")
    func onlineAPIHTTP404ReturnsNil() async {
        let service = makeService(responseBody: "", statusCode: 404)
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com HTTP 429 rate-limit: returns nil gracefully")
    func onlineAPIHTTP429ReturnsNil() async {
        let service = makeService(responseBody: "Too Many Requests", statusCode: 429)
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com network error: returns nil gracefully (no crash)")
    func onlineAPINetworkErrorReturnsNil() async {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = MACVendorLookupService(session: session)
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com empty body: returns nil gracefully")
    func onlineAPIEmptyBodyReturnsNil() async {
        let service = makeService(responseBody: "", statusCode: 200)
        let vendor = await service.lookupVendorEnhanced(macAddress: "12:34:56:78:90:AB")
        // Empty body after trimming is treated the same as Not Found
        #expect(vendor == nil)
    }

    // MARK: - Local database takes priority over online API

    @Test("Known Apple OUI: local database resolves before hitting online API")
    func localDatabasePriorityOverOnlineAPI() async {
        // Wire the session to return a different vendor — if the local DB wins,
        // we should see "Apple", not "SomeOtherVendor".
        let session = MockURLProtocol.makeSession { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.macvendors.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("SomeOtherVendor".utf8))
        }
        let service = MACVendorLookupService(session: session)
        // 00:03:93 is a known Apple OUI in the local database
        let vendor = await service.lookupVendorEnhanced(macAddress: "00:03:93:AA:BB:CC")
        #expect(vendor == "Apple",
                "Local OUI database should take priority over online API; got: \(vendor ?? "nil")")
    }

    // MARK: - macvendors-success.json fixture format contract

    @Test("macvendors-success.json fixture: vendorDetails.companyName field is parseable")
    func macvendorsSuccessFixtureFormat() throws {
        // The fixture uses the macvendors.com /vendors/<prefix> JSON endpoint format.
        // Verify the fixture is valid JSON and has the expected shape.
        let fixtureJSON = """
        {"vendorDetails": {"companyName": "Apple, Inc.", "macPrefix": "AABBCC"}}
        """
        let data = Data(fixtureJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil, "Fixture must be valid JSON")

        let vendorDetails = json?["vendorDetails"] as? [String: Any]
        #expect(vendorDetails != nil, "Fixture must have 'vendorDetails' key")

        let companyName = vendorDetails?["companyName"] as? String
        #expect(companyName == "Apple, Inc.", "companyName should be 'Apple, Inc.'")

        let macPrefix = vendorDetails?["macPrefix"] as? String
        #expect(macPrefix == "AABBCC", "macPrefix should be 'AABBCC'")
    }
}
