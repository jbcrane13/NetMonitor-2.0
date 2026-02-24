import Foundation

/// IP geolocation service using ip-api.com free tier.
/// NOTE: ip-api.com free tier is HTTP only. Add an NSExceptionDomains entry for
/// "ip-api.com" with NSExceptionAllowsInsecureHTTPLoads = true in your Info.plist.
/// Rate limit: 45 requests/minute on the free tier.
public actor GeoLocationService: GeoLocationServiceProtocol {

    private var cache: [String: GeoLocation] = [:]
    private let baseURL = "http://ip-api.com/json"

    public init() {}

    public func lookup(ip: String) async throws -> GeoLocation {
        let cleanIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cached = cache[cleanIP] {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/\(cleanIP)?fields=status,message,country,countryCode,region,city,lat,lon,isp") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeoLocationError.httpError
        }

        let decoded = try JSONDecoder().decode(IPAPIResponse.self, from: data)

        guard decoded.status == "success" else {
            throw GeoLocationError.lookupFailed(decoded.message ?? "Unknown error")
        }

        let location = GeoLocation(
            ip: cleanIP,
            country: decoded.country,
            countryCode: decoded.countryCode,
            region: decoded.region,
            city: decoded.city,
            latitude: decoded.lat,
            longitude: decoded.lon,
            isp: decoded.isp
        )

        cache[cleanIP] = location
        return location
    }
}

// MARK: - Private Response Type

private struct IPAPIResponse: Decodable {
    let status: String
    let message: String?
    let country: String
    let countryCode: String
    let region: String
    let city: String
    let lat: Double
    let lon: Double
    let isp: String?

    private enum CodingKeys: String, CodingKey {
        case status, message, country, countryCode, region, city, lat, lon, isp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        country = (try? container.decode(String.self, forKey: .country)) ?? ""
        countryCode = (try? container.decode(String.self, forKey: .countryCode)) ?? ""
        region = (try? container.decode(String.self, forKey: .region)) ?? ""
        city = (try? container.decode(String.self, forKey: .city)) ?? ""
        lat = (try? container.decode(Double.self, forKey: .lat)) ?? 0
        lon = (try? container.decode(Double.self, forKey: .lon)) ?? 0
        isp = try? container.decode(String.self, forKey: .isp)
    }
}

// MARK: - Errors

public enum GeoLocationError: Error, LocalizedError {
    case lookupFailed(String)
    case httpError

    public var errorDescription: String? {
        switch self {
        case .lookupFailed(let msg): return "Geolocation lookup failed: \(msg)"
        case .httpError: return "HTTP error from geolocation service"
        }
    }
}
