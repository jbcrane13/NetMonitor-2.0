//
//  ISPLookupService.swift
//  NetMonitor
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import Network

actor ISPLookupService {

    // MARK: - Types

    struct ISPInfo: Codable {
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

    // MARK: - Properties

    private let cacheKey = "netmonitor.isp.cache"
    private let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes

    /// IPv4-only service. ipapi.co is dual-stack, so asking it for "my IP" returns the
    /// IPv6 address on IPv6-capable networks; we resolve the IPv4 address first instead.
    private let ipv4URL = URL(string: "https://api.ipify.org")!
    private let fallbackURL = URL(string: "https://ipinfo.io/json")!

    // MARK: - Public API

    func lookup() async throws -> ISPInfo {
        // Check cache first
        if let cached = loadCachedResult(), Self.isIPv4(cached.info.publicIP) {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheValidityDuration {
                // Return cached data immediately, refresh in background
                Task { try? await refreshInBackground() }
                return cached.info
            }
        }

        // Cache miss or stale - fetch fresh data
        return try await fetchISPInfo()
    }

    // MARK: - Private Methods

    private func fetchISPInfo() async throws -> ISPInfo {
        // Try primary API
        do {
            let info = try await fetchFromPrimary()
            cacheResult(info)
            return info
        } catch {
            // Primary failed, try fallback
            do {
                let info = try await fetchFromFallback()
                cacheResult(info)
                return info
            } catch {
                throw error
            }
        }
    }

    /// True for a dotted-quad IPv4 address. The dashboard shows the public IPv4 address only.
    static func isIPv4(_ address: String) -> Bool {
        IPv4Address(address) != nil && address.contains(".")
    }

    private func fetchPublicIPv4() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: ipv4URL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.isIPv4(ip)
        else {
            throw ISPLookupError.invalidResponse
        }
        return ip
    }

    private func fetchFromPrimary() async throws -> ISPInfo {
        let ipv4 = try await fetchPublicIPv4()
        guard let url = URL(string: "https://ipapi.co/\(ipv4)/json/") else {
            throw ISPLookupError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 429 {
            throw ISPLookupError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard json?["ip"] is String else {
            throw ISPLookupError.invalidResponse
        }
        let ip = ipv4

        let org = json?["org"] as? String
        let city = json?["city"] as? String
        let region = json?["region"] as? String
        let country = json?["country_name"] as? String
        let timezone = json?["timezone"] as? String

        // Parse ISP name and ASN from org field (format: "AS12345 ISP Name")
        var isp = org ?? "Unknown"
        var asn: String?

        if let org = org {
            let components = org.components(separatedBy: " ")
            if let first = components.first, first.hasPrefix("AS") {
                asn = first
                isp = components.dropFirst().joined(separator: " ")
            }
        }

        return ISPInfo(
            publicIP: ip,
            isp: isp,
            organization: org,
            asn: asn,
            city: city,
            region: region,
            country: country,
            timezone: timezone
        )
    }

    private func fetchFromFallback() async throws -> ISPInfo {
        let (data, response) = try await URLSession.shared.data(from: fallbackURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 429 {
            throw ISPLookupError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // ipinfo.io uses "ip" key (IPv4-only host; reject anything else)
        guard let ip = json?["ip"] as? String, Self.isIPv4(ip) else {
            throw ISPLookupError.invalidResponse
        }

        let org = json?["org"] as? String
        let city = json?["city"] as? String
        let region = json?["region"] as? String
        let country = json?["country"] as? String
        let timezone = json?["timezone"] as? String

        // Parse ISP name and ASN from org field (format: "AS12345 ISP Name")
        var isp = org ?? "Unknown"
        var asn: String?

        if let org = org, org.hasPrefix("AS") {
            let parts = org.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                asn = String(parts[0])
                isp = String(parts[1])
            }
        }

        return ISPInfo(
            publicIP: ip,
            isp: isp,
            organization: org,
            asn: asn,
            city: city,
            region: region,
            country: country,
            timezone: timezone
        )
    }

    private func refreshInBackground() async throws {
        let info = try await fetchISPInfo()
        cacheResult(info)
    }

    // MARK: - Cache Management

    private func loadCachedResult() -> CachedResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedResult.self, from: data)
    }

    private func cacheResult(_ info: ISPInfo) {
        let cached = CachedResult(info: info, timestamp: Date())
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

// MARK: - Protocol

protocol ISPLookupServiceProtocol: Sendable {
    func lookup() async throws -> ISPLookupService.ISPInfo
}

extension ISPLookupService: ISPLookupServiceProtocol {}

// MARK: - Errors

enum ISPLookupError: LocalizedError {
    case rateLimited
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .invalidResponse:
            return "Unable to parse ISP information."
        }
    }
}
