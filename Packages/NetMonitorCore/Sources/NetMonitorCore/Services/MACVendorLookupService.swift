import Foundation

/// Service for looking up MAC address vendors from OUI database
public actor MACVendorLookupService: MACVendorLookupServiceProtocol {

    // MARK: - Initialization

    /// Creates a MACVendorLookupService using the shared URLSession for online lookups.
    public init() {
        self.session = .shared
    }

    /// Creates a MACVendorLookupService with an injected URLSession.
    /// Use this initialiser in tests to intercept online API calls with MockURLProtocol.
    public init(session: URLSession) {
        self.session = session
    }

    // MARK: - Protocol conformance
    /// MACVendorLookupServiceProtocol: async lookup (delegates to enhanced lookup)
    // Implemented as lookupVendorEnhanced below

    // MARK: - Properties

    /// URLSession used for online OUI API lookups.
    private let session: URLSession

    /// In-memory cache for API lookups
    private var vendorCache: [String: String] = [:]

    /// Rate limiting
    private var lastAPICall = Date.distantPast
    private let rateLimitInterval: TimeInterval = 1.0

    /// Common vendor prefixes (OUI - first 3 bytes of MAC address)
    private let vendorDatabase: [String: String] = [
        // Apple
        "00:03:93": "Apple",
        "00:05:02": "Apple",
        "00:0A:27": "Apple",
        "00:0A:95": "Apple",
        "00:0D:93": "Apple",
        "00:10:FA": "Apple",
        "00:11:24": "Apple",
        "00:14:51": "Apple",
        "00:16:CB": "Apple",
        "00:17:F2": "Apple",
        "00:19:E3": "Apple",
        "00:1B:63": "Apple",
        "00:1C:B3": "Apple",
        "00:1D:4F": "Apple",
        "00:1E:52": "Apple",
        "00:1E:C2": "Apple",
        "00:1F:5B": "Apple",
        "00:1F:F3": "Apple",
        "00:21:E9": "Apple",
        "00:22:41": "Apple",
        "00:23:12": "Apple",
        "00:23:32": "Apple",
        "00:23:6C": "Apple",
        "00:23:DF": "Apple",
        "00:24:36": "Apple",
        "00:25:00": "Apple",
        "00:25:4B": "Apple",
        "00:25:BC": "Apple",
        "00:26:08": "Apple",
        "00:26:4A": "Apple",
        "00:26:B0": "Apple",
        "00:26:BB": "Apple",
        "00:30:65": "Apple",
        "00:3E:E1": "Apple",
        "00:50:E4": "Apple",
        "00:56:CD": "Apple",
        "00:61:71": "Apple",
        "00:6D:52": "Apple",
        "00:88:65": "Apple",
        "00:B3:62": "Apple",
        "00:C6:10": "Apple",
        "00:CD:FE": "Apple",
        "00:DB:70": "Apple",
        "00:F4:B9": "Apple",
        "00:F7:6F": "Apple",

        // Samsung
        "00:00:F0": "Samsung",
        "00:02:78": "Samsung",
        "00:07:AB": "Samsung",
        "00:09:18": "Samsung",
        "00:0D:AE": "Samsung",
        "00:12:47": "Samsung",
        "00:12:FB": "Samsung",
        "00:13:77": "Samsung",
        "00:15:99": "Samsung",
        "00:15:B9": "Samsung",
        "00:16:32": "Samsung",
        "00:16:6B": "Samsung",
        "00:16:6C": "Samsung",
        "00:16:DB": "Samsung",
        "00:17:C9": "Samsung",
        "00:17:D5": "Samsung",
        "00:18:AF": "Samsung",

        // Google
        "00:1A:11": "Google",
        "3C:5A:B4": "Google",
        "54:60:09": "Google",
        "94:EB:2C": "Google",
        "F4:F5:D8": "Google",
        "F4:F5:E8": "Google",

        // Amazon
        "00:FC:8B": "Amazon",
        "0C:47:C9": "Amazon",
        "10:CE:A9": "Amazon",
        "14:91:82": "Amazon",
        "18:74:2E": "Amazon",
        "34:D2:70": "Amazon",
        "38:F7:3D": "Amazon",
        "40:B4:CD": "Amazon",
        "44:65:0D": "Amazon",
        "4C:EF:C0": "Amazon",
        "50:DC:E7": "Amazon",
        "50:F5:DA": "Amazon",
        "68:37:E9": "Amazon",
        "68:54:FD": "Amazon",

        // Microsoft
        "00:03:FF": "Microsoft",
        "00:0D:3A": "Microsoft",
        "00:12:5A": "Microsoft",
        "00:15:5D": "Microsoft",
        "00:17:FA": "Microsoft",
        "00:1D:D8": "Microsoft",
        "00:22:48": "Microsoft",
        "00:25:AE": "Microsoft",
        "00:50:F2": "Microsoft",
        "28:18:78": "Microsoft",
        "30:59:B7": "Microsoft",

        // Intel
        "00:02:B3": "Intel",
        "00:03:47": "Intel",
        "00:04:23": "Intel",
        "00:07:E9": "Intel",
        "00:0C:F1": "Intel",
        "00:0E:0C": "Intel",
        "00:0E:35": "Intel",
        "00:11:11": "Intel",
        "00:12:F0": "Intel",
        "00:13:02": "Intel",
        "00:13:20": "Intel",
        "00:13:CE": "Intel",
        "00:13:E8": "Intel",

        // TP-Link
        "00:27:19": "TP-Link",
        "10:FE:ED": "TP-Link",
        "14:CC:20": "TP-Link",
        "14:CF:92": "TP-Link",
        "18:A6:F7": "TP-Link",
        "1C:3B:F3": "TP-Link",
        "30:B5:C2": "TP-Link",
        "50:C7:BF": "TP-Link",
        "54:C8:0F": "TP-Link",

        // Netgear
        "00:09:5B": "Netgear",
        "00:0F:B5": "Netgear",
        "00:14:6C": "Netgear",
        "00:18:4D": "Netgear",
        "00:1B:2F": "Netgear",
        "00:1E:2A": "Netgear",
        "00:1F:33": "Netgear",
        "00:22:3F": "Netgear",
        "00:24:B2": "Netgear",
        "00:26:F2": "Netgear",

        // Cisco
        "00:00:0C": "Cisco",
        "00:01:42": "Cisco",
        "00:01:43": "Cisco",
        "00:01:63": "Cisco",
        "00:01:64": "Cisco",
        "00:01:96": "Cisco",
        "00:01:97": "Cisco",
        "00:01:C7": "Cisco",
        "00:01:C9": "Cisco",
        "00:02:16": "Cisco",
        "00:02:17": "Cisco",
        "00:02:3D": "Cisco",

        // Raspberry Pi
        "28:CD:C1": "Raspberry Pi",
        "B8:27:EB": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi",

        // Sonos
        "00:0E:58": "Sonos",
        "34:7E:5C": "Sonos",
        "48:A6:B8": "Sonos",
        "54:2A:1B": "Sonos",
        "5C:AA:FD": "Sonos",
        "78:28:CA": "Sonos",
        "94:9F:3E": "Sonos",
        "B8:E9:37": "Sonos"
    ]

    // MARK: - Public Methods

    /// Look up vendor using online API first, then local database as fallback
    /// - Parameter macAddress: MAC address in any format (colons, dashes, or none)
    /// - Returns: Vendor name if found
    public func lookupVendorEnhanced(macAddress: String) async -> String? {
        // Try online API first
        if let vendor = await lookupVendorOnline(macAddress: macAddress) {
            // Cache the result
            cacheResult(macAddress: macAddress, vendor: vendor)
            return vendor
        }

        // Fall back to local OUI database
        return lookup(macAddress: macAddress)
    }

    /// Look up the vendor for a MAC address (local database only)
    /// - Parameter macAddress: MAC address in any format (colons, dashes, or none)
    /// - Returns: Vendor name if found
    public func lookup(macAddress: String) -> String? {
        let normalized = normalizeMAC(macAddress)
        guard normalized.count >= 8 else { return nil }
        let prefix = String(normalized.prefix(8)) // First 3 bytes = OUI
        return vendorDatabase[prefix]
    }

    // MARK: - Private Methods

    /// Look up vendor using online API (macvendors.com)
    private func lookupVendorOnline(macAddress: String) async -> String? {
        let cleanMAC = macAddress.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard cleanMAC.count >= 6 else { return nil }
        let prefix = String(cleanMAC.prefix(6)).uppercased()

        // Check cache first
        if let cached = vendorCache[prefix] {
            return cached
        }

        guard let url = URL(string: "https://api.macvendors.com/\(prefix)") else { return nil }

        // Rate limit API calls
        await rateLimitedAPICall()

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let vendor = String(data: data, encoding: .utf8) else {
                return nil
            }

            let trimmed = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("Not Found") {
                return trimmed
            }
        } catch {
            // API unavailable, fall through to local database
        }

        return nil
    }

    /// Cache API lookup result
    private func cacheResult(macAddress: String, vendor: String) {
        let prefix = macAddress.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .prefix(6)
            .uppercased()
        vendorCache[String(prefix)] = vendor
    }

    /// Rate limit API calls to avoid hitting the API too fast
    private func rateLimitedAPICall() async {
        let elapsed = Date().timeIntervalSince(lastAPICall)
        if elapsed < rateLimitInterval {
            try? await Task.sleep(for: .seconds(rateLimitInterval - elapsed))
        }
        lastAPICall = Date()
    }

    /// Normalize MAC address to XX:XX:XX:XX:XX:XX format
    private func normalizeMAC(_ mac: String) -> String {
        // Remove separators and convert to uppercase
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard cleaned.count >= 6 else { return "" }

        // Insert colons every 2 characters
        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 2 == 0 && index < 12 {
                result += ":"
            }
            result.append(char)
        }

        return result
    }
}
