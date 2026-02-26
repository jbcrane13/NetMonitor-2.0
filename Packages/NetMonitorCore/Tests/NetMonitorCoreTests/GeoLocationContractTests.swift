import Foundation
import Testing
@testable import NetMonitorCore

/// Extended contract tests for GeoLocationService.
///
/// Core contract tests (success, failure, HTTP errors, caching, malformed JSON) already
/// exist in ContractTests.swift → GeoLocationServiceContractTests. These tests cover
/// additional edge cases: missing optional fields, whitespace handling, and error
/// discrimination.
@Suite("GeoLocationService Extended Contract Tests", .serialized)
struct GeoLocationExtendedContractTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - Missing Optional Fields

    @Test("Response with missing ISP field: GeoLocation.isp is nil")
    func missingISPFieldHandledGracefully() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {
            "status": "success",
            "country": "Germany",
            "countryCode": "DE",
            "region": "BE",
            "city": "Berlin",
            "lat": 52.5200,
            "lon": 13.4050
        }
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let location = try await service.lookup(ip: "203.0.113.1")

        #expect(location.country == "Germany")
        #expect(location.countryCode == "DE")
        #expect(location.city == "Berlin")
        #expect(location.isp == nil)
    }

    @Test("Response with missing coordinate fields: defaults to 0.0")
    func missingCoordinateFieldsDefaultToZero() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {
            "status": "success",
            "country": "Japan",
            "countryCode": "JP",
            "region": "13",
            "city": "Tokyo"
        }
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let location = try await service.lookup(ip: "198.51.100.1")

        #expect(location.latitude == 0.0)
        #expect(location.longitude == 0.0)
    }

    @Test("Response with missing city field: defaults to empty string")
    func missingCityFieldDefaultsToEmpty() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {
            "status": "success",
            "country": "Australia",
            "countryCode": "AU",
            "region": "NSW",
            "lat": -33.8688,
            "lon": 151.2093,
            "isp": "Telstra"
        }
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let location = try await service.lookup(ip: "192.0.2.1")

        #expect(location.city == "")
        #expect(location.country == "Australia")
    }

    // MARK: - Whitespace Handling

    @Test("IP address with leading/trailing whitespace is trimmed before lookup")
    func ipWhitespaceIsTrimmed() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = try MockURLProtocol.loadFixture(named: "ip-api-success.json")
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let location = try await service.lookup(ip: "  8.8.8.8  ")

        // Should not crash; should use trimmed IP
        #expect(location.ip == "8.8.8.8")
    }

    // MARK: - Cache Behavior

    @Test("Different IPs are cached independently")
    func differentIPsCachedIndependently() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = request.url!
            let ip = url.pathComponents.last ?? ""
            let json: String
            if ip == "8.8.8.8" {
                json = """
                {"status":"success","country":"United States","countryCode":"US","region":"CA","city":"Mountain View","lat":37.386,"lon":-122.0838,"isp":"Google LLC"}
                """
            } else {
                json = """
                {"status":"success","country":"Germany","countryCode":"DE","region":"BE","city":"Berlin","lat":52.52,"lon":13.405,"isp":"Provider"}
                """
            }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let loc1 = try await service.lookup(ip: "8.8.8.8")
        let loc2 = try await service.lookup(ip: "1.2.3.4")

        #expect(loc1.city == "Mountain View")
        #expect(loc2.city == "Berlin")
        #expect(requestCount == 2, "Each unique IP should trigger its own HTTP request")
    }

    // MARK: - Error Discrimination

    @Test("GeoLocationError.lookupFailed carries the API message")
    func lookupFailedCarriesMessage() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {"status":"fail","message":"private range"}
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        do {
            _ = try await service.lookup(ip: "10.0.0.1")
            Issue.record("Expected GeoLocationError.lookupFailed to be thrown")
        } catch let error as GeoLocationError {
            if case .lookupFailed(let message) = error {
                #expect(message == "private range")
            } else {
                Issue.record("Expected lookupFailed, got: \(error)")
            }
        }
    }

    @Test("HTTP 403 throws GeoLocationError.httpError")
    func http403ThrowsHTTPError() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.stub(json: "{}", statusCode: 403)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        do {
            _ = try await service.lookup(ip: "1.2.3.4")
            Issue.record("Expected error to be thrown for HTTP 403")
        } catch let error as GeoLocationError {
            if case .httpError = error { } else {
                Issue.record("Expected httpError, got: \(error)")
            }
        }
    }

    @Test("Empty JSON object with success status: produces GeoLocation with empty strings")
    func emptySuccessResponseProducesDefaults() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {"status":"success"}
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        let location = try await service.lookup(ip: "203.0.113.50")

        // All non-optional fields default to empty string / 0
        #expect(location.country == "")
        #expect(location.countryCode == "")
        #expect(location.city == "")
        #expect(location.region == "")
        #expect(location.latitude == 0.0)
        #expect(location.longitude == 0.0)
    }

    @Test("Failure response without message field: throws with 'Unknown error'")
    func failureWithoutMessageThrowsUnknownError() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let json = """
        {"status":"fail"}
        """
        MockURLProtocol.stub(json: json)

        let service = GeoLocationService(session: MockURLProtocol.makeSession())
        do {
            _ = try await service.lookup(ip: "10.0.0.1")
            Issue.record("Expected error to be thrown")
        } catch let error as GeoLocationError {
            if case .lookupFailed(let message) = error {
                #expect(message == "Unknown error")
            } else {
                Issue.record("Expected lookupFailed, got: \(error)")
            }
        }
    }
}
