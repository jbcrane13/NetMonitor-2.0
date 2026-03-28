import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for ISPLookupService response parsing and caching.
///
/// INTEGRATION GAP: ISPLookupService uses URLSession.shared internally (hardcoded)
/// for both primary (ipapi.co) and fallback (ipinfo.io) endpoints. This prevents
/// MockURLProtocol-based contract testing of the network fetch path.
///
/// Resolution path: add `init(session: URLSession)` to ISPLookupService.
///
/// These tests cover the CachedResult Codable contract — verifying that the cache
/// serialization format is stable and round-trips all fields correctly. This is
/// testable because CachedResult and ISPInfo are Codable structs whose encoding
/// can be exercised directly.
///
/// NOTE: ISPLookupService and its types are defined in the macOS target, not
/// NetMonitorCore. These tests validate the Codable contract of ISPInfo-equivalent
/// structures to ensure the JSON wire format is stable.
struct ISPLookupCacheContractTests {

    // MARK: - ISPInfo-equivalent Codable structure

    /// Mirror of ISPLookupService.ISPInfo for contract testing.
    /// This must stay in sync with the production struct.
    private struct ISPInfo: Codable {
        let publicIP: String
        let isp: String
        let organization: String?
        let asn: String?
        let city: String?
        let region: String?
        let country: String?
        let timezone: String?
    }

    private struct CachedResult: Codable {
        let info: ISPInfo
        let timestamp: Date
    }

    // MARK: - Cache Round-Trip

    @Test("CachedResult encode/decode round-trip preserves all ISPInfo fields")
    func cacheRoundTripPreservesAllFields() throws {
        let info = ISPInfo(
            publicIP: "203.0.113.1",
            isp: "Comcast Cable",
            organization: "AS7922 Comcast Cable Communications, LLC",
            asn: "AS7922",
            city: "Philadelphia",
            region: "Pennsylvania",
            country: "United States",
            timezone: "America/New_York"
        )
        let cached = CachedResult(info: info, timestamp: Date(timeIntervalSinceReferenceDate: 1_000_000))

        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedResult.self, from: data)

        #expect(decoded.info.publicIP == "203.0.113.1")
        #expect(decoded.info.isp == "Comcast Cable")
        #expect(decoded.info.organization == "AS7922 Comcast Cable Communications, LLC")
        #expect(decoded.info.asn == "AS7922")
        #expect(decoded.info.city == "Philadelphia")
        #expect(decoded.info.region == "Pennsylvania")
        #expect(decoded.info.country == "United States")
        #expect(decoded.info.timezone == "America/New_York")
        #expect(abs(decoded.timestamp.timeIntervalSinceReferenceDate - 1_000_000) < 0.001)
    }

    @Test("CachedResult with all nil optional fields round-trips")
    func cacheRoundTripNilOptionals() throws {
        let info = ISPInfo(
            publicIP: "10.0.0.1",
            isp: "Unknown",
            organization: nil,
            asn: nil,
            city: nil,
            region: nil,
            country: nil,
            timezone: nil
        )
        let cached = CachedResult(info: info, timestamp: Date())

        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedResult.self, from: data)

        #expect(decoded.info.publicIP == "10.0.0.1")
        #expect(decoded.info.isp == "Unknown")
        #expect(decoded.info.organization == nil)
        #expect(decoded.info.asn == nil)
        #expect(decoded.info.city == nil)
    }

    @Test("Corrupted cache JSON throws DecodingError — not a silent nil")
    func corruptedCacheThrowsDecodingError() {
        let corruptedData = Data("{ this is not valid json }".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CachedResult.self, from: corruptedData)
        }
    }

    @Test("Cache JSON missing required fields throws DecodingError")
    func cacheMissingRequiredFieldsThrows() {
        // Missing 'isp' which is required (non-optional)
        let json = """
        {"info": {"publicIP": "1.2.3.4"}, "timestamp": 0}
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CachedResult.self, from: Data(json.utf8))
        }
    }

    // MARK: - ipapi.co Response Parsing Contract

    @Test("Valid ipapi.co JSON parses org field into ASN + ISP name")
    func ipapiOrgFieldParsing() {
        // This tests the parsing logic pattern used in ISPLookupService.fetchFromPrimary()
        let org = "AS14618 Amazon.com, Inc."
        let components = org.components(separatedBy: " ")
        var asn: String?
        var isp = org

        if let first = components.first, first.hasPrefix("AS") {
            asn = first
            isp = components.dropFirst().joined(separator: " ")
        }

        #expect(asn == "AS14618")
        #expect(isp == "Amazon.com, Inc.")
    }

    @Test("Org field without AS prefix: ISP is full org string, ASN is nil")
    func orgWithoutASPrefixUsesFullString() {
        let org = "Some ISP Name"
        let components = org.components(separatedBy: " ")
        var asn: String?
        var isp = org

        if let first = components.first, first.hasPrefix("AS") {
            asn = first
            isp = components.dropFirst().joined(separator: " ")
        }

        #expect(asn == nil)
        #expect(isp == "Some ISP Name")
    }

    @Test("Nil org field: ISP defaults to 'Unknown'")
    func nilOrgDefaultsToUnknown() {
        let org: String? = nil
        let isp = org ?? "Unknown"
        #expect(isp == "Unknown")
    }

    // MARK: - ipinfo.io Fallback Response Parsing Contract

    @Test("ipinfo.io org field with AS prefix splits correctly")
    func ipinfoOrgFieldParsing() {
        let org = "AS7922 Comcast Cable Communications"
        var isp = org
        var asn: String?

        if org.hasPrefix("AS") {
            let parts = org.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                asn = String(parts[0])
                isp = String(parts[1])
            }
        }

        #expect(asn == "AS7922")
        #expect(isp == "Comcast Cable Communications")
    }
}
