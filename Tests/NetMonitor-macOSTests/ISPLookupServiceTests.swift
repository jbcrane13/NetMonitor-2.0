import Foundation
import Testing
@testable import NetMonitor_macOS

// MARK: - ISPInfo Codable Tests

struct ISPInfoCodableTests {

    @Test("ISPInfo round-trips through JSON encode/decode")
    func roundTrip() throws {
        let original = ISPLookupService.ISPInfo(
            publicIP: "203.0.113.42",
            isp: "Comcast Cable",
            organization: "AS7922 Comcast Cable",
            asn: "AS7922",
            city: "Philadelphia",
            region: "Pennsylvania",
            country: "United States",
            timezone: "America/New_York"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: data)

        #expect(decoded.publicIP == original.publicIP)
        #expect(decoded.isp == original.isp)
        #expect(decoded.organization == original.organization)
        #expect(decoded.asn == original.asn)
        #expect(decoded.city == original.city)
        #expect(decoded.region == original.region)
        #expect(decoded.country == original.country)
        #expect(decoded.timezone == original.timezone)
    }

    @Test("ISPInfo with nil optional fields round-trips correctly")
    func roundTripWithNils() throws {
        let original = ISPLookupService.ISPInfo(
            publicIP: "10.0.0.1",
            isp: "Unknown",
            organization: nil,
            asn: nil,
            city: nil,
            region: nil,
            country: nil,
            timezone: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: data)

        #expect(decoded.publicIP == "10.0.0.1")
        #expect(decoded.isp == "Unknown")
        #expect(decoded.organization == nil)
        #expect(decoded.asn == nil)
        #expect(decoded.city == nil)
        #expect(decoded.region == nil)
        #expect(decoded.country == nil)
        #expect(decoded.timezone == nil)
    }

    @Test("ISPInfo encodes to valid JSON with expected keys")
    func encodesToValidJSON() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "1.2.3.4",
            isp: "TestISP",
            organization: "AS1234 TestISP",
            asn: "AS1234",
            city: "TestCity",
            region: "TestRegion",
            country: "TestCountry",
            timezone: "UTC"
        )

        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["publicIP"] as? String == "1.2.3.4")
        #expect(json?["isp"] as? String == "TestISP")
        #expect(json?["asn"] as? String == "AS1234")
    }

    @Test("ISPInfo decoding fails gracefully for malformed JSON")
    func decodingFailsForMalformedJSON() {
        let badJSON = Data("{ not json }".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: badJSON)
        }
    }

    @Test("ISPInfo decoding fails when required fields are missing")
    func decodingFailsWhenMissingRequiredFields() {
        // Missing publicIP and isp which are required (non-optional)
        let json = Data(#"{"organization": "test"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: json)
        }
    }
}

// MARK: - ISPLookupError Tests

struct ISPLookupErrorTests {

    @Test("rateLimited error has descriptive message")
    func rateLimitedDescription() {
        let error = ISPLookupError.rateLimited
        #expect(error.errorDescription?.contains("Rate limit") == true)
    }

    @Test("invalidResponse error has descriptive message")
    func invalidResponseDescription() {
        let error = ISPLookupError.invalidResponse
        #expect(error.errorDescription?.contains("parse") == true)
    }

    @Test("rateLimited and invalidResponse are distinct errors")
    func errorsAreDistinct() {
        let a = ISPLookupError.rateLimited
        let b = ISPLookupError.invalidResponse
        #expect(a.errorDescription != b.errorDescription)
    }
}

// MARK: - ISPLookupService Cache Logic Tests

struct ISPLookupCacheTests {

    /// Simulates caching by writing and reading the same UserDefaults key
    /// that ISPLookupService uses internally. This validates the CachedResult
    /// Codable contract without hitting the network.

    private let cacheKey = "netmonitor.isp.cache"

    /// CachedResult mirror — must match the private struct in ISPLookupService
    private struct CachedResult: Codable {
        let info: ISPLookupService.ISPInfo
        let timestamp: Date
    }

    @Test("cached ISPInfo can be written to and read from UserDefaults")
    func cacheWriteAndRead() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "93.184.216.34",
            isp: "Edgecast",
            organization: "AS15133 Edgecast",
            asn: "AS15133",
            city: "Los Angeles",
            region: "California",
            country: "United States",
            timezone: "America/Los_Angeles"
        )

        let cached = CachedResult(info: info, timestamp: Date())
        let data = try JSONEncoder().encode(cached)

        // Write to a test-specific UserDefaults key to avoid polluting production cache
        let testKey = "netmonitor.isp.cache.test.\(UUID().uuidString)"
        UserDefaults.standard.set(data, forKey: testKey)
        defer { UserDefaults.standard.removeObject(forKey: testKey) }

        guard let readData = UserDefaults.standard.data(forKey: testKey) else {
            Issue.record("Expected cached data in UserDefaults")
            return
        }

        let decoded = try JSONDecoder().decode(CachedResult.self, from: readData)
        #expect(decoded.info.publicIP == "93.184.216.34")
        #expect(decoded.info.isp == "Edgecast")
        #expect(decoded.info.asn == "AS15133")
    }

    @Test("cached result timestamp allows freshness check")
    func cacheTimestampFreshnessCheck() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "1.1.1.1",
            isp: "Cloudflare",
            organization: nil,
            asn: nil,
            city: nil,
            region: nil,
            country: nil,
            timezone: nil
        )

        let recentTimestamp = Date()
        let staleTimestamp = Date().addingTimeInterval(-600) // 10 minutes ago

        let recentCached = CachedResult(info: info, timestamp: recentTimestamp)
        let staleCached = CachedResult(info: info, timestamp: staleTimestamp)

        let cacheValidity: TimeInterval = 5 * 60 // 5 minutes, matching ISPLookupService

        let recentAge = Date().timeIntervalSince(recentCached.timestamp)
        let staleAge = Date().timeIntervalSince(staleCached.timestamp)

        #expect(recentAge < cacheValidity, "Recent cache should be considered fresh")
        #expect(staleAge >= cacheValidity, "Stale cache should be considered expired")
    }

    @Test("nil cache data returns nil when decoded")
    func nilCacheReturnsNil() {
        let testKey = "netmonitor.isp.cache.test.nil.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: testKey) }

        let data = UserDefaults.standard.data(forKey: testKey)
        #expect(data == nil)
    }

    @Test("corrupted cache data fails decode gracefully")
    func corruptedCacheFailsDecode() {
        let badData = Data("corrupted".utf8)
        let result = try? JSONDecoder().decode(CachedResult.self, from: badData)
        #expect(result == nil)
    }
}
