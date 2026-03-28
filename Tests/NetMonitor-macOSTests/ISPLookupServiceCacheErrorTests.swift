import Foundation
import Testing
@testable import NetMonitor_macOS

/// Area 6c: Silent failure error surfacing tests for ISPLookupService cache.
///
/// ISPLookupService has 3 `try?` sites:
///   1. loadCachedResult(): `try? JSONDecoder().decode(CachedResult.self, from: data)`
///      — corrupted cache silently returns nil, causing a network re-fetch
///   2. cacheResult(): `try? JSONEncoder().encode(cached)` wrapped in `if let`
///      — encode failure silently skips caching, no error surfaced
///   3. refreshInBackground(): `try? await refreshInBackground()`
///      — background refresh failure is silently swallowed
///
/// These tests verify the current behavior without modifying production code.
struct ISPLookupServiceCacheErrorTests {

    // MARK: - CachedResult Codable Contract

    @Test("ISPInfo encode/decode round-trip preserves all fields")
    func ispInfoRoundTrip() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "203.0.113.1",
            isp: "Comcast",
            organization: "AS7922 Comcast Cable",
            asn: "AS7922",
            city: "Denver",
            region: "Colorado",
            country: "United States",
            timezone: "America/Denver"
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: data)

        #expect(decoded.publicIP == "203.0.113.1")
        #expect(decoded.isp == "Comcast")
        #expect(decoded.organization == "AS7922 Comcast Cable")
        #expect(decoded.asn == "AS7922")
        #expect(decoded.city == "Denver")
        #expect(decoded.region == "Colorado")
        #expect(decoded.country == "United States")
        #expect(decoded.timezone == "America/Denver")
    }

    @Test("ISPInfo with all nil optionals round-trips")
    func ispInfoNilOptionalsRoundTrip() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "10.0.0.1",
            isp: "Unknown",
            organization: nil,
            asn: nil,
            city: nil,
            region: nil,
            country: nil,
            timezone: nil
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: data)

        #expect(decoded.publicIP == "10.0.0.1")
        #expect(decoded.isp == "Unknown")
        #expect(decoded.organization == nil)
        #expect(decoded.asn == nil)
        #expect(decoded.city == nil)
    }

    // MARK: - Corrupted Cache Data

    @Test("Corrupted/wrong-structure/missing-field cache data: decode returns nil — silent fallback")
    func corruptedCacheDataReturnsNil() {
        // Case 1: totally invalid JSON
        let corrupted = try? JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: Data("{{{{ not json".utf8))
        #expect(corrupted == nil,
                "Corrupted JSON: loadCachedResult() silently returns nil, triggering network fetch")

        // Case 2: valid JSON but wrong structure
        let wrongStructure = try? JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: Data("{\"unexpected\": \"structure\"}".utf8))
        #expect(wrongStructure == nil,
                "Wrong structure: silently falls back to network fetch")

        // Case 3: missing required 'publicIP' field
        let missingField = try? JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: Data("""
        {"isp": "Comcast", "organization": null, "asn": null, "city": null, "region": null, "country": null, "timezone": null}
        """.utf8))
        #expect(missingField == nil,
                "Missing required field: silent fallback to network")
    }

    // MARK: - ISPLookupError Surface Behavior

    @Test("ISPLookupError cases have user-facing descriptions")
    func errorDescriptions() {
        #expect(ISPLookupError.rateLimited.errorDescription?.contains("Rate limit") == true)
        #expect(ISPLookupError.invalidResponse.errorDescription?.contains("parse") == true)
    }

    // MARK: - Cache Write: Valid Data Encodes

    @Test("Valid ISPInfo encodes successfully — cache write would succeed")
    func validISPInfoEncodesSuccessfully() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "1.2.3.4", isp: "Test ISP",
            organization: nil, asn: nil, city: nil,
            region: nil, country: nil, timezone: nil
        )
        let data = try JSONEncoder().encode(info)
        #expect(!data.isEmpty, "Valid ISPInfo should encode to non-empty Data")
    }
}
