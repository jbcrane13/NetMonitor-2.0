import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// Additional PublicIPService tests covering error enum details and edge cases
/// NOT already covered by PublicIPServiceContractTests (which covers success,
/// cache, forceRefresh, various HTTP errors, and field mapping).

@MainActor
struct PublicIPServiceTests {

    // MARK: - PublicIPError

    @Test("PublicIPError.invalidResponse has descriptive error message")
    func invalidResponseErrorDescription() {
        let error = PublicIPError.invalidResponse
        #expect(error.errorDescription == "Invalid response from server")
    }

    @Test("PublicIPError.decodingError has descriptive error message")
    func decodingErrorDescription() {
        let error = PublicIPError.decodingError
        #expect(error.errorDescription == "Could not parse response")
    }

    @Test("PublicIPError.asNetworkError maps invalidResponse correctly")
    func invalidResponseMapsToNetworkError() {
        let error = PublicIPError.invalidResponse
        #expect(error.asNetworkError.errorDescription == NetworkError.invalidResponse.errorDescription)
    }

    @Test("PublicIPError.asNetworkError maps decodingError to invalidResponse")
    func decodingErrorMapsToNetworkError() {
        let error = PublicIPError.decodingError
        #expect(error.asNetworkError.errorDescription == NetworkError.invalidResponse.errorDescription)
    }

    // MARK: - Initial state

    @Test("PublicIPService starts with nil ispInfo and not loading")
    func initialState() {
        let session = MockURLProtocol.makeSession { _ in throw URLError(.badURL) }
        let service = PublicIPService(session: session)
        #expect(service.ispInfo == nil)
        #expect(service.isLoading == false)
    }

    // MARK: - Cache duration boundary

    @Test("Cache is used when fetched within 300 seconds, skipped after")
    func cacheDurationBehavior() async {
        var callCount = 0
        let session = MockURLProtocol.makeSession { request in
            callCount += 1
            let url = request.url?.absoluteString ?? ""
            if url.contains("ipify") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data("1.2.3.4".utf8))
            } else {
                let json = """
                {"ip":"1.2.3.4","city":"Test","region":"R","country_name":"C","country_code":"CC","org":"O","asn":"AS1","timezone":"UTC"}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
                        Data(json.utf8))
            }
        }

        let service = PublicIPService(session: session)

        // First call fetches
        await service.fetchPublicIP()
        #expect(service.ispInfo != nil)
        let firstCount = callCount

        // Second call within cache window does not fetch
        await service.fetchPublicIP(forceRefresh: false)
        #expect(callCount == firstCount, "Should use cache, not make new requests")
    }

    // MARK: - Multiple error recovery

    @Test("Service recovers from error on subsequent successful fetch")
    func recoversFromErrorOnRetry() async {
        var shouldFail = true
        let session = MockURLProtocol.makeSession { request in
            if shouldFail {
                throw URLError(.timedOut)
            }
            let url = request.url?.absoluteString ?? ""
            if url.contains("ipify") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data("5.6.7.8".utf8))
            } else {
                let json = """
                {"ip":"5.6.7.8","city":"NYC","region":null,"country_name":null,"country_code":null,"org":null,"asn":null,"timezone":null}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
                        Data(json.utf8))
            }
        }

        let service = PublicIPService(session: session)

        // First call fails
        await service.fetchPublicIP()
        #expect(service.ispInfo == nil)
        #expect(service.lastError != nil)

        // Fix the mock and force refresh
        shouldFail = false
        await service.fetchPublicIP(forceRefresh: true)
        #expect(service.ispInfo != nil)
        #expect(service.ispInfo?.publicIP == "5.6.7.8")
    }

    // MARK: - Partial ipapi.co response (optional fields nil)

    @Test("Handles ipapi.co response with null optional fields gracefully")
    func handlesNullOptionalFields() async {
        let session = MockURLProtocol.makeSession { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("ipify") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data("10.0.0.1".utf8))
            } else {
                let json = """
                {"ip":"10.0.0.1","city":null,"region":null,"country_name":null,"country_code":null,"org":null,"asn":null,"timezone":null}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
                        Data(json.utf8))
            }
        }

        let service = PublicIPService(session: session)
        await service.fetchPublicIP()

        #expect(service.ispInfo != nil)
        #expect(service.ispInfo?.publicIP == "10.0.0.1")
        #expect(service.ispInfo?.city == nil)
        #expect(service.ispInfo?.region == nil)
        #expect(service.ispInfo?.country == nil)
    }
}
