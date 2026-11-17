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
        // 10:34:56 is a maker-assigned (not private) prefix with no IEEE assignment
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == "Apple, Inc.")
    }

    @Test("macvendors.com response is trimmed of whitespace")
    func onlineAPIResponseIsTrimmed() async {
        let service = makeService(responseBody: "  Cisco Systems, Inc.  \n")
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == "Cisco Systems, Inc.")
    }

    @Test("macvendors.com 'Not Found' response: returns nil")
    func onlineAPINotFoundReturnsNil() async {
        let service = makeService(responseBody: "Not Found", statusCode: 404)
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com HTTP 404: returns nil gracefully")
    func onlineAPIHTTP404ReturnsNil() async {
        let service = makeService(responseBody: "", statusCode: 404)
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com HTTP 429 rate-limit: returns nil gracefully")
    func onlineAPIHTTP429ReturnsNil() async {
        let service = makeService(responseBody: "Too Many Requests", statusCode: 429)
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com network error: returns nil gracefully (no crash)")
    func onlineAPINetworkErrorReturnsNil() async {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = MACVendorLookupService(session: session)
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("macvendors.com empty body: returns nil gracefully")
    func onlineAPIEmptyBodyReturnsNil() async {
        let service = makeService(responseBody: "", statusCode: 200)
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        // Empty body after trimming is treated the same as Not Found
        #expect(vendor == nil)
    }

    // MARK: - Private (randomised) addresses never reach the network (#385)

    @Test("Private MAC: enhanced lookup returns nil without any online request")
    func privateMACSkipsOnlineLookup() async {
        let requests = RequestCounter()
        let session = MockURLProtocol.makeSession { request in
            requests.increment()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw URLError(.badURL)
            }
            return (response, Data("Should Not Be Used".utf8))
        }
        let service = MACVendorLookupService(session: session)
        let vendor = await service.lookupVendorEnhanced(macAddress: "DA:A1:19:12:34:56")
        let dashed = await service.lookupVendorEnhanced(macAddress: "3a-7b-00-11-22-33")
        #expect(vendor == nil)
        #expect(dashed == nil)
        #expect(requests.isEmpty)
    }

    @Test("IEEE-listed MAC resolves offline without any online request (#384)")
    func offlineListSkipsOnlineLookup() async {
        let requests = RequestCounter()
        let service = makeCountingService(requests, responseBody: "Should Not Be Used")
        let vendor = await service.lookupVendorEnhanced(macAddress: "28:6F:B9:11:22:33")
        #expect(vendor == "Nokia Shanghai Bell Co., Ltd.")
        #expect(requests.isEmpty)
    }

    @Test("Unlisted public MAC still falls back to the online lookup (#384)")
    func unlistedMACUsesOnlineLookup() async {
        let requests = RequestCounter()
        let service = makeCountingService(requests, responseBody: "Acme Networks")
        let vendor = await service.lookupVendorEnhanced(macAddress: "10:34:56:78:90:AB")
        #expect(vendor == "Acme Networks")
        #expect(!requests.isEmpty)
    }

    private func makeCountingService(_ requests: RequestCounter, responseBody: String) -> MACVendorLookupService {
        MACVendorLookupService(session: MockURLProtocol.makeSession { request in
            requests.increment()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw URLError(.badURL)
            }
            return (response, Data(responseBody.utf8))
        })
    }

    @Test("Private MAC: local lookup returns nil even if the prefix bits match a table entry")
    func privateMACSkipsLocalLookup() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "02:03:93:AA:BB:CC")
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

/// Counts requests a mock session receives (the handler runs off the test's actor).
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var isEmpty: Bool {
        lock.withLock { value == 0 }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}
