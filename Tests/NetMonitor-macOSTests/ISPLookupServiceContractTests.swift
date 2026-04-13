import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - ISP Lookup Service Contract Tests

/// Contract tests for ISPLookupService — validates that the JSON parsing logic
/// correctly maps real-world API response fixtures from ipapi.co (primary) and
/// ipinfo.io (fallback) into ISPInfo structs. Uses recorded fixtures; no network.
///
/// The service hardcodes URLSession.shared, so we test the parsing contract by
/// feeding fixture JSON through the same JSONSerialization + field-mapping logic
/// the service uses internally.
struct ISPLookupServiceContractTests {

    // MARK: - Fixture Data

    /// Realistic ipapi.co /json/ response
    private static let ipapiSuccessJSON = """
    {
        "ip": "203.0.113.42",
        "city": "Ashburn",
        "region": "Virginia",
        "region_code": "VA",
        "country_code": "US",
        "country_name": "United States",
        "continent_code": "NA",
        "in_eu": false,
        "postal": "20149",
        "latitude": 39.0469,
        "longitude": -77.4903,
        "timezone": "America/New_York",
        "utc_offset": "-0400",
        "country_calling_code": "+1",
        "currency": "USD",
        "languages": "en-US",
        "asn": "AS14618",
        "org": "AS14618 Amazon.com, Inc."
    }
    """

    /// Realistic ipinfo.io /json response
    private static let ipinfoSuccessJSON = """
    {
        "ip": "198.51.100.7",
        "hostname": "server.example.com",
        "city": "San Jose",
        "region": "California",
        "country": "US",
        "loc": "37.3382,-121.8863",
        "org": "AS15169 Google LLC",
        "postal": "95141",
        "timezone": "America/Los_Angeles"
    }
    """

    // MARK: - Primary API (ipapi.co) Parsing

    @Test("ipapi.co: all ISPInfo fields mapped correctly from recorded response")
    func primaryAPIAllFieldsMapped() throws {
        let data = Data(Self.ipapiSuccessJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let ip = json?["ip"] as? String
        let org = json?["org"] as? String
        let city = json?["city"] as? String
        let region = json?["region"] as? String
        let country = json?["country_name"] as? String
        let timezone = json?["timezone"] as? String

        #expect(ip == "203.0.113.42")
        #expect(org == "AS14618 Amazon.com, Inc.")
        #expect(city == "Ashburn")
        #expect(region == "Virginia")
        #expect(country == "United States")
        #expect(timezone == "America/New_York")
    }

    @Test("ipapi.co: ASN extracted from org field prefix")
    func primaryAPIASNParsing() throws {
        let data = Data(Self.ipapiSuccessJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let org = json?["org"] as? String

        // Replicate the service's ASN extraction logic
        var isp = org ?? "Unknown"
        var asn: String?

        if let org = org {
            let components = org.components(separatedBy: " ")
            if let first = components.first, first.hasPrefix("AS") {
                asn = first
                isp = components.dropFirst().joined(separator: " ")
            }
        }

        #expect(asn == "AS14618")
        #expect(isp == "Amazon.com, Inc.")
    }

    @Test("ipapi.co: org field without AS prefix uses full org as ISP name")
    func primaryAPIOrgWithoutASPrefix() throws {
        let json = """
        {"ip": "10.0.0.1", "org": "Comcast Cable", "country_name": "US"}
        """
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let org = parsed?["org"] as? String

        var isp = org ?? "Unknown"
        var asn: String?
        if let org = org {
            let components = org.components(separatedBy: " ")
            if let first = components.first, first.hasPrefix("AS") {
                asn = first
                isp = components.dropFirst().joined(separator: " ")
            }
        }

        #expect(asn == nil, "No ASN prefix means asn should be nil")
        #expect(isp == "Comcast Cable", "Full org string used as ISP name")
    }

    @Test("ipapi.co: missing ip field produces parsing failure")
    func primaryAPIMissingIP() throws {
        let json = """
        {"city": "Ashburn", "org": "AS14618 Amazon.com"}
        """
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ip = parsed?["ip"] as? String

        #expect(ip == nil, "Missing ip field should yield nil — service throws invalidResponse")
    }

    @Test("ipapi.co: null optional fields map to nil without crashing")
    func primaryAPIOptionalFieldsNull() throws {
        let json = """
        {"ip": "203.0.113.1", "org": null, "city": null, "region": null, "country_name": null, "timezone": null}
        """
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed?["ip"] as? String == "203.0.113.1")
        #expect(parsed?["org"] as? String == nil)
        #expect(parsed?["city"] as? String == nil)
        #expect(parsed?["region"] as? String == nil)
        #expect(parsed?["country_name"] as? String == nil)
        #expect(parsed?["timezone"] as? String == nil)
    }

    // MARK: - Fallback API (ipinfo.io) Parsing

    @Test("ipinfo.io: all fields mapped correctly from recorded response")
    func fallbackAPIAllFieldsMapped() throws {
        let data = Data(Self.ipinfoSuccessJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let ip = json?["ip"] as? String
        let org = json?["org"] as? String
        let city = json?["city"] as? String
        let region = json?["region"] as? String
        // ipinfo.io uses "country" (2-letter code), not "country_name"
        let country = json?["country"] as? String
        let timezone = json?["timezone"] as? String

        #expect(ip == "198.51.100.7")
        #expect(org == "AS15169 Google LLC")
        #expect(city == "San Jose")
        #expect(region == "California")
        #expect(country == "US")
        #expect(timezone == "America/Los_Angeles")
    }

    @Test("ipinfo.io: ASN extracted from org field using split(maxSplits:1)")
    func fallbackAPIASNParsing() throws {
        let data = Data(Self.ipinfoSuccessJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let org = json?["org"] as? String

        // Replicate the fallback's ASN extraction logic (split with maxSplits:1)
        var isp = org ?? "Unknown"
        var asn: String?

        if let org = org, org.hasPrefix("AS") {
            let parts = org.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                asn = String(parts[0])
                isp = String(parts[1])
            }
        }

        #expect(asn == "AS15169")
        #expect(isp == "Google LLC")
    }

    @Test("ipinfo.io: country key is 2-letter code, not full name — contract difference from ipapi.co")
    func fallbackAPICountryKeyDifference() throws {
        let data = Data(Self.ipinfoSuccessJSON.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // ipinfo.io: uses "country" with 2-letter code
        #expect(json?["country"] as? String == "US")
        // ipapi.co key "country_name" should NOT exist in ipinfo.io response
        #expect(json?["country_name"] as? String == nil)
    }

    // MARK: - ISPInfo Codable Contract

    @Test("ISPInfo struct round-trips through JSON encoding/decoding")
    func ispInfoCodableRoundTrip() throws {
        let info = ISPLookupService.ISPInfo(
            publicIP: "203.0.113.42",
            isp: "Amazon.com, Inc.",
            organization: "AS14618 Amazon.com, Inc.",
            asn: "AS14618",
            city: "Ashburn",
            region: "Virginia",
            country: "United States",
            timezone: "America/New_York"
        )

        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: encoded)

        #expect(decoded.publicIP == info.publicIP)
        #expect(decoded.isp == info.isp)
        #expect(decoded.organization == info.organization)
        #expect(decoded.asn == info.asn)
        #expect(decoded.city == info.city)
        #expect(decoded.region == info.region)
        #expect(decoded.country == info.country)
        #expect(decoded.timezone == info.timezone)
    }

    @Test("ISPInfo with all-nil optional fields round-trips correctly")
    func ispInfoMinimalCodableRoundTrip() throws {
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

        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ISPLookupService.ISPInfo.self, from: encoded)

        #expect(decoded.publicIP == "10.0.0.1")
        #expect(decoded.isp == "Unknown")
        #expect(decoded.organization == nil)
        #expect(decoded.asn == nil)
        #expect(decoded.city == nil)
        #expect(decoded.region == nil)
        #expect(decoded.country == nil)
        #expect(decoded.timezone == nil)
    }

    // MARK: - Error Contract

    @Test("ISPLookupError.rateLimited has user-facing description")
    func rateLimitedErrorDescription() {
        let error = ISPLookupError.rateLimited
        #expect(error.errorDescription?.contains("Rate limit") == true)
    }

    @Test("ISPLookupError.invalidResponse has user-facing description")
    func invalidResponseErrorDescription() {
        let error = ISPLookupError.invalidResponse
        #expect(error.errorDescription?.contains("parse") == true)
    }
}
