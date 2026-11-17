import Foundation

/// Helpers for reading facts out of a hardware (MAC) address string.
public enum MACAddress {

    /// The label shown in place of a maker for a private (randomised) address.
    public static let privateAddressLabel = "Private address"

    /// iOS reports this placeholder when it hides the real hardware address. It has the
    /// locally administered bit set, but it means "unknown", not "private".
    private static let hiddenAddressPlaceholder: [UInt8] = [0x02, 0, 0, 0, 0, 0]

    /// Whether `mac` is a private (randomised, "locally administered") address: bit 0x02
    /// of the first octet is set.
    ///
    /// Accepts `:` or `-` separators (or none) in any case. Empty or invalid input, and
    /// the iOS `02:00:00:00:00:00` placeholder, are not private.
    public static func isPrivate(_ mac: String) -> Bool {
        guard let octets = octets(of: mac), octets != hiddenAddressPlaceholder else { return false }
        return octets[0] & 0x02 != 0
    }

    /// What a device list shows where a maker would go: the vendor when known, otherwise
    /// "Private address" for a private hardware address, otherwise nil.
    public static func makerLabel(vendor: String?, macAddress: String?) -> String? {
        if let vendor, !vendor.isEmpty {
            return vendor
        }
        if let macAddress, isPrivate(macAddress) {
            return privateAddressLabel
        }
        return nil
    }

    /// Parses a six-octet address with `:` or `-` separators (one or two hex digits per
    /// octet) or twelve bare hex digits. Returns nil for anything else.
    static func octets(of mac: String) -> [UInt8]? {
        let trimmed = mac.trimmingCharacters(in: .whitespaces)
        let parts: [Substring]
        if trimmed.contains(":") || trimmed.contains("-") {
            parts = trimmed.split(separator: /[:-]/, omittingEmptySubsequences: false)
            guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) }) else { return nil }
        } else {
            guard trimmed.count == 12 else { return nil }
            parts = stride(from: 0, to: 12, by: 2).map { offset in
                let start = trimmed.index(trimmed.startIndex, offsetBy: offset)
                return trimmed[start..<trimmed.index(start, offsetBy: 2)]
            }
        }
        var octets: [UInt8] = []
        for part in parts {
            guard part.allSatisfy(\.isHexDigit), let value = UInt8(part, radix: 16) else { return nil }
            octets.append(value)
        }
        return octets
    }
}
