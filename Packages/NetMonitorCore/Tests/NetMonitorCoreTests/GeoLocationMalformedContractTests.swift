import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for GeoLocationService: malformed/partial JSON responses.
///
/// The ip-api.com response decoder (IPAPIResponse.init(from:)) uses
/// `try? decode() ?? defaultValue` for lat, lon, country, city, region, and countryCode.
/// This means missing or wrong-typed fields silently default to 0 (Double) or "" (String)
/// rather than throwing.
///
/// **Null Island bug**: a response missing `lat`/`lon` produces a GeoLocation at (0, 0)
/// — "Null Island" in the Gulf of Guinea. The service does not distinguish "API returned
/// 0,0" from "API omitted the fields entirely." Tests document this current behavior.
@Suite(.serialized)
struct GeoLocationMalformedContractTests {

    // MARK: - Helper

    private func makeService(json: String) -> GeoLocationService {
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
        return GeoLocationService(session: session)
    }

    // MARK: - 5a.1: Valid complete response

    @Test("Valid complete ip-api.com response decodes all fields correctly")
    func validCompleteResponse() async throws {
        let json = """
        {
            "status": "success",
            "country": "United States",
            "countryCode": "US",
            "region": "CA",
            "city": "Mountain View",
            "lat": 37.386,
            "lon": -122.0838,
            "isp": "Google LLC"
        }
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "8.8.8.8")

        #expect(location.country == "United States")
        #expect(location.countryCode == "US")
        #expect(location.region == "CA")
        #expect(location.city == "Mountain View")
        #expect(abs(location.latitude - 37.386) < 0.001)
        #expect(abs(location.longitude - -122.0838) < 0.001)
        #expect(location.isp == "Google LLC")
    }

    // MARK: - 5a.2: Missing lat field -> Null Island bug

    @Test("Response missing lat field: latitude defaults to 0.0 (Null Island bug)")
    func missingLatDefaultsToZero() async throws {
        let json = """
        {
            "status": "success",
            "country": "Germany",
            "countryCode": "DE",
            "region": "BE",
            "city": "Berlin",
            "lon": 13.405,
            "isp": "ISP GmbH"
        }
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "198.51.100.1")

        #expect(location.latitude == 0.0,
                "Missing lat field silently defaults to 0.0 — Null Island bug, error not surfaced to caller")
        #expect(abs(location.longitude - 13.405) < 0.001)
    }

    // MARK: - 5a.3: Missing lon field -> Null Island bug

    @Test("Response missing lon field: longitude defaults to 0.0 (Null Island bug)")
    func missingLonDefaultsToZero() async throws {
        let json = """
        {
            "status": "success",
            "country": "Japan",
            "countryCode": "JP",
            "region": "13",
            "city": "Tokyo",
            "lat": 35.6762,
            "isp": "NTT"
        }
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "192.0.2.1")

        #expect(abs(location.latitude - 35.6762) < 0.001)
        #expect(location.longitude == 0.0,
                "Missing lon field silently defaults to 0.0 — Null Island bug, error not surfaced to caller")
    }

    // MARK: - 5a.4: lat/lon as strings instead of doubles

    @Test("Response with lat/lon as strings: defaults to 0.0 (type mismatch silent fallback)")
    func latLonAsStringsDefaultToZero() async throws {
        let json = """
        {
            "status": "success",
            "country": "France",
            "countryCode": "FR",
            "region": "IDF",
            "city": "Paris",
            "lat": "48.8566",
            "lon": "2.3522",
            "isp": "Orange SA"
        }
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "203.0.113.50")

        #expect(location.latitude == 0.0,
                "lat as String instead of Double: try? decode(Double) fails, defaults to 0 — silent type coercion gap")
        #expect(location.longitude == 0.0,
                "lon as String instead of Double: try? decode(Double) fails, defaults to 0 — silent type coercion gap")
        #expect(location.city == "Paris", "String fields still decode correctly")
    }

    // MARK: - 5a.5: Completely empty JSON object with status success

    @Test("Empty JSON object with status success: all fields default to empty/zero")
    func emptySuccessObjectProducesDefaults() async throws {
        let json = """
        {"status": "success"}
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "203.0.113.99")

        #expect(location.country == "",
                "Missing country defaults to empty string — silent data loss")
        #expect(location.countryCode == "")
        #expect(location.region == "")
        #expect(location.city == "")
        #expect(location.latitude == 0.0,
                "Missing lat defaults to 0.0 — Null Island")
        #expect(location.longitude == 0.0,
                "Missing lon defaults to 0.0 — Null Island")
        #expect(location.isp == nil)
    }

    // MARK: - Additional edge case: lat/lon as null JSON values

    @Test("Response with null lat/lon: defaults to 0.0")
    func nullLatLonDefaultsToZero() async throws {
        let json = """
        {
            "status": "success",
            "country": "Brazil",
            "countryCode": "BR",
            "region": "SP",
            "city": "Sao Paulo",
            "lat": null,
            "lon": null,
            "isp": "Vivo"
        }
        """
        let service = makeService(json: json)
        let location = try await service.lookup(ip: "198.51.100.50")

        #expect(location.latitude == 0.0,
                "null lat: try? decode(Double) fails for null, defaults to 0")
        #expect(location.longitude == 0.0,
                "null lon: try? decode(Double) fails for null, defaults to 0")
        #expect(location.city == "Sao Paulo")
    }
}
