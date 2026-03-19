import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// Contract tests for PublicIPService — the iOS service that fetches the device's
/// public IP from ipify.org (Step 1) and then enriches it with ISP details from
/// ipapi.co (Step 2).
///
/// ## What is tested
/// 1. Success path: ipify returns a plain-text IP; ipapi.co returns JSON with all
///    known fields; the resulting `ISPInfo` maps every field correctly.
/// 2. ipapi.co rate-limit (HTTP 429): `lastError` is set and `ispInfo` is nil.
/// 3. ipify failure (network error): `lastError` is set and `ispInfo` is nil.
/// 4. ipify returns invalid body: `lastError` is set.
/// 5. ipapi.co returns malformed JSON: `lastError` is set.
/// 6. Second call within cache window does NOT hit the network.
/// 7. forceRefresh: true bypasses the cache and re-fetches.
///
/// All tests use the `init(session:)` injector added for testability, wired to
/// a per-test `MockURLProtocol` session so no real network calls are made.
@MainActor
struct PublicIPServiceContractTests {

    // MARK: - Fixture helpers

    /// Canonical ipify response (plain text, no trailing newline needed).
    private let ipifyIP = "203.0.113.1"

    /// Canonical ipapi.co success JSON matching ipapi-co-success.json fixture.
    private let ipapiSuccessJSON = """
    {
      "ip": "203.0.113.1",
      "city": "Ashburn",
      "region": "Virginia",
      "country_name": "United States",
      "country_code": "US",
      "org": "AS14618 Amazon.com, Inc.",
      "asn": "AS14618",
      "timezone": "America/New_York",
      "latitude": 39.0481,
      "longitude": -77.4728
    }
    """

    /// Creates a session that serves ipify with a plain-text IP and ipapi.co
    /// with the given JSON body and HTTP status code.
    private func makeSession(
        ipifyBody: String,
        ipifyStatus: Int = 200,
        ipapiJSON: String,
        ipapiStatus: Int = 200
    ) -> URLSession {
        MockURLProtocol.makeSession { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("ipify.org") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: ipifyStatus,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"]
                )!
                return (response, Data(ipifyBody.utf8))
            } else {
                // ipapi.co request
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: ipapiStatus,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(ipapiJSON.utf8))
            }
        }
    }

    // MARK: - Success path

    @Test("Success: all ISPInfo fields mapped correctly from ipapi.co response")
    func successResponseMapsAllFields() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: ipifyIP,
            ipapiJSON: ipapiSuccessJSON
        ))

        await service.fetchPublicIP()

        #expect(service.ispInfo != nil)
        #expect(service.lastError == nil)

        let info = service.ispInfo!
        #expect(info.publicIP == "203.0.113.1")
        #expect(info.city == "Ashburn")
        #expect(info.region == "Virginia")
        #expect(info.country == "United States")
        #expect(info.countryCode == "US")
        #expect(info.organization == "AS14618 Amazon.com, Inc.")
        #expect(info.timezone == "America/New_York")
    }

    @Test("Success: isLoading returns to false after fetch completes")
    func isLoadingFalseAfterFetch() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: ipifyIP,
            ipapiJSON: ipapiSuccessJSON
        ))
        await service.fetchPublicIP()
        #expect(service.isLoading == false)
    }

    // MARK: - ipify failure

    @Test("ipify network error: lastError is set, ispInfo remains nil")
    func ipifyNetworkErrorSetsLastError() async {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = PublicIPService(session: session)
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.lastError?.isEmpty == false)
        #expect(service.isLoading == false)
    }

    @Test("ipify returns HTTP 500: lastError is set, ispInfo remains nil")
    func ipifyHTTP500SetsLastError() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: "",
            ipifyStatus: 500,
            ipapiJSON: "{}"
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }

    @Test("ipify returns empty body: lastError is set, ispInfo remains nil")
    func ipifyEmptyBodySetsLastError() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: "",   // empty — trimmed result is empty, guard fails
            ipapiJSON: "{}"
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }

    // MARK: - ipapi.co failure

    @Test("ipapi.co HTTP 429 rate-limit: lastError is set, ispInfo remains nil")
    func ipapiRateLimitSetsLastError() async {
        let rateLimitJSON = """
        {"message": "You have exceeded the rate limit.", "error": true}
        """
        let service = PublicIPService(session: makeSession(
            ipifyBody: ipifyIP,
            ipapiJSON: rateLimitJSON,
            ipapiStatus: 429
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }

    @Test("ipapi.co malformed JSON: lastError is set, ispInfo remains nil")
    func ipapiMalformedJSONSetsLastError() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: ipifyIP,
            ipapiJSON: "not valid json at all"
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }

    @Test("ipapi.co HTTP 500 server error: lastError is set, ispInfo remains nil")
    func ipapiHTTP500SetsLastError() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: ipifyIP,
            ipapiJSON: "{}",
            ipapiStatus: 500
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }

    // MARK: - Caching

    @Test("Second fetchPublicIP within cache window does not hit network again")
    func secondFetchWithinCacheWindowSkipsNetwork() async {
        var requestCount = 0
        let session = MockURLProtocol.makeSession { request in
            requestCount += 1
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("ipify.org") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"]
                )!
                return (response, Data("203.0.113.1".utf8))
            } else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(self.ipapiSuccessJSON.utf8))
            }
        }

        let service = PublicIPService(session: session)
        await service.fetchPublicIP()
        let countAfterFirst = requestCount

        await service.fetchPublicIP() // second call — should use cache
        #expect(requestCount == countAfterFirst,
                "Second call within cache window should not trigger new network requests; got \(requestCount) total requests")
    }

    @Test("forceRefresh: true bypasses cache and re-fetches")
    func forceRefreshBypassesCache() async {
        var requestCount = 0
        let session = MockURLProtocol.makeSession { request in
            requestCount += 1
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("ipify.org") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"]
                )!
                return (response, Data("203.0.113.1".utf8))
            } else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(self.ipapiSuccessJSON.utf8))
            }
        }

        let service = PublicIPService(session: session)
        await service.fetchPublicIP()
        let countAfterFirst = requestCount

        await service.fetchPublicIP(forceRefresh: true)
        #expect(requestCount > countAfterFirst,
                "forceRefresh should trigger new network requests; countAfterFirst=\(countAfterFirst), total=\(requestCount)")
    }

    // MARK: - IP address handling

    @Test("ipify response with surrounding whitespace is trimmed correctly")
    func ipifyWhitespaceIsTrimmed() async {
        let service = PublicIPService(session: makeSession(
            ipifyBody: "  203.0.113.1  \n",
            ipapiJSON: ipapiSuccessJSON
        ))
        await service.fetchPublicIP()

        #expect(service.ispInfo?.publicIP == "203.0.113.1")
    }
}
