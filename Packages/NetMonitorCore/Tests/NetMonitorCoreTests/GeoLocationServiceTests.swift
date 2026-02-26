import Foundation
import Testing
@testable import NetMonitorCore

@Suite("GeoLocationService", .serialized)
struct GeoLocationServiceTests {

    // MARK: - GeoLocation model

    @Test("GeoLocation stores all fields correctly")
    func geoLocationStoresFields() {
        let location = GeoLocation(
            ip: "8.8.8.8",
            country: "United States",
            countryCode: "US",
            region: "California",
            city: "Mountain View",
            latitude: 37.386,
            longitude: -122.0838,
            isp: "Google LLC"
        )
        #expect(location.ip == "8.8.8.8")
        #expect(location.country == "United States")
        #expect(location.countryCode == "US")
        #expect(location.region == "California")
        #expect(location.city == "Mountain View")
        #expect(location.latitude == 37.386)
        #expect(location.longitude == -122.0838)
        #expect(location.isp == "Google LLC")
    }

    @Test("GeoLocation isp is optional and can be nil")
    func geoLocationISPOptional() {
        let location = GeoLocation(
            ip: "1.1.1.1",
            country: "Australia",
            countryCode: "AU",
            region: "NSW",
            city: "Sydney",
            latitude: -33.8688,
            longitude: 151.2093
        )
        #expect(location.isp == nil)
    }

    // MARK: - GeoLocationError

    @Test("GeoLocationError.httpError has non-nil localizedDescription")
    func httpErrorDescription() {
        let err = GeoLocationError.httpError
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test("GeoLocationError.lookupFailed includes message in description")
    func lookupFailedDescription() {
        let err = GeoLocationError.lookupFailed("reserved range")
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.contains("reserved range") == true)
    }

    // MARK: - Caching (observable via injected URLSession)

    @Test("GeoLocationService returns error for malformed IP via URLError")
    func lookupBadURLThrows() async {
        let service = GeoLocationService()
        // Spaces in IP will produce a bad URL
        do {
            _ = try await service.lookup(ip: "not a valid ip with spaces and !@#")
            Issue.record("Expected an error to be thrown")
        } catch {
            // Any error is acceptable — the key assertion is that no result is returned
            #expect(true)
        }
    }

    // MARK: - Cache hit: lookup same IP twice, verify no second network call

    @Test("Cache hit: second lookup returns same result without network call")
    func cacheHitReturnsSameResult() async throws {
        let session = MockURLProtocol.makeSession()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let json = """
            {
                "status": "success",
                "country": "United States",
                "countryCode": "US",
                "region": "CA",
                "city": "Mountain View",
                "lat": 37.386,
                "lon": -122.084,
                "isp": "Google LLC"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: session)
        let result1 = try await service.lookup(ip: "8.8.8.8")
        let result2 = try await service.lookup(ip: "8.8.8.8")

        #expect(requestCount == 1, "Second lookup should be served from cache")
        #expect(result1.ip == result2.ip)
        #expect(result1.city == result2.city)
    }

    // MARK: - Cache miss: different IPs cause separate network calls

    @Test("Cache miss: different IPs trigger separate network calls")
    func cacheMissDifferentIPsMakeMultipleCalls() async throws {
        let session = MockURLProtocol.makeSession()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let json = """
            {
                "status": "success",
                "country": "TestCountry",
                "countryCode": "TC",
                "region": "TR",
                "city": "TestCity",
                "lat": 0.0,
                "lon": 0.0,
                "isp": "TestISP"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: session)
        _ = try await service.lookup(ip: "1.1.1.1")
        _ = try await service.lookup(ip: "8.8.8.8")

        #expect(requestCount == 2, "Different IPs should each trigger a network call")
    }

    // MARK: - HTTP error responses

    @Test("HTTP 404 response throws httpError")
    func http404ThrowsHTTPError() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "10.0.0.1")
            Issue.record("Expected GeoLocationError.httpError to be thrown")
        } catch let error as GeoLocationError {
            if case .httpError = error {
                #expect(true)
            } else {
                Issue.record("Expected httpError but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("HTTP 500 response throws httpError")
    func http500ThrowsHTTPError() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "10.0.0.2")
            Issue.record("Expected GeoLocationError.httpError")
        } catch let error as GeoLocationError {
            if case .httpError = error {
                #expect(true)
            } else {
                Issue.record("Expected httpError but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Malformed JSON response

    @Test("Malformed JSON response throws a decoding error")
    func malformedJSONThrowsDecodingError() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{ not valid json".utf8))
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "10.0.0.3")
            Issue.record("Expected a decoding error to be thrown")
        } catch {
            // Any decoding error is acceptable
            #expect(true)
        }
    }

    @Test("JSON with missing required 'status' field throws error")
    func jsonMissingStatusFieldThrows() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
                "country": "US"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "10.0.0.4")
            Issue.record("Expected error for missing status field")
        } catch {
            #expect(true)
        }
    }

    // MARK: - Rate limiting / fail status response

    @Test("API 'fail' status response throws lookupFailed with message")
    func apiFailStatusThrowsLookupFailed() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
                "status": "fail",
                "message": "reserved range"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "192.168.1.1")
            Issue.record("Expected GeoLocationError.lookupFailed")
        } catch let error as GeoLocationError {
            if case .lookupFailed(let message) = error {
                #expect(message == "reserved range")
            } else {
                Issue.record("Expected lookupFailed but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("HTTP 429 rate-limiting response throws httpError")
    func http429RateLimitThrowsHTTPError() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = GeoLocationService(session: session)
        do {
            _ = try await service.lookup(ip: "10.0.0.5")
            Issue.record("Expected GeoLocationError.httpError for 429")
        } catch let error as GeoLocationError {
            if case .httpError = error {
                #expect(true)
            } else {
                Issue.record("Expected httpError but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Whitespace trimming

    @Test("IP with leading/trailing whitespace is trimmed before lookup")
    func ipWhitespaceTrimming() async throws {
        let session = MockURLProtocol.makeSession()
        var capturedURL: String?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url?.absoluteString
            let json = """
            {
                "status": "success",
                "country": "US",
                "countryCode": "US",
                "region": "CA",
                "city": "LA",
                "lat": 34.0,
                "lon": -118.0
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: session)
        _ = try await service.lookup(ip: "  8.8.8.8  ")

        #expect(capturedURL?.contains("8.8.8.8") == true)
        #expect(capturedURL?.contains(" ") == false, "Whitespace should be trimmed from IP")
    }
}
