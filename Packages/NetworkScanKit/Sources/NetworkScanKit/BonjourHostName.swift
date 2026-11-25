import Foundation

/// One Bonjour host an address answered for in a scan (#594, design v3.1): the SRV host target
/// a service resolved to, the service's instance name, and the address the host resolved to.
/// Evidence only; Core decides what it means (`DeviceGroups`).
public struct HostClaim: Codable, Sendable, Hashable {
    /// ``BonjourHostName/normalized(_:)``: the full lowercased `.local` name, conflict suffix kept.
    public let host: String
    public let service: String
    public let address: String

    public init(host: String, service: String, address: String) {
        self.host = host
        self.service = service
        self.address = address
    }
}

/// mDNS host names as identity evidence (#594, design v3.1 §3).
public enum BonjourHostName {
    /// The lowercased host without a trailing dot or `%scope`, when it is an mDNS (`.local`) name;
    /// nil for an address, a unicast DNS name or an empty label. The full name is kept, so
    /// `blakes-mac.local` and `blakes-mac-2.local` stay different hosts.
    public static func normalized(_ hostTarget: String) -> String? {
        var host = hostTarget.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        host = host.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard host.hasSuffix(".local") else { return nil }
        let label = host.dropLast(".local".count)
        // A single label: an address or a dotted name before `.local` isn't one host's name.
        guard !label.isEmpty, !label.contains(".") else { return nil }
        return host
    }

    /// Whether `host` (a ``normalized(_:)`` name) is a factory default or otherwise names no one
    /// device ("iPhone", "android-1a2b", "MacBook-Pro-2", the maker's own name), so it never
    /// identifies one. A conflict suffix (`-2`, ` (2)`) is stripped only for this test.
    public static func isGeneric(_ host: String, maker: String?, model: String?) -> Bool {
        let label = slug(withoutParenthesisedSuffix(withoutDomain(host)))
        let base = withoutNumberSuffix(label)
        guard !base.isEmpty else { return true }
        if genericNames.contains(base) || genericPrefixes.contains(where: { base.hasPrefix($0 + "-") })
            || gluedPrefixes.contains(where: base.hasPrefix) {
            return true
        }
        // The maker's or model's own name, with or without a suffix ("macmini9-1" is `Macmini9,1`).
        let names = Set([maker, model].compactMap { $0 }.map(slug))
        return names.contains(base) || names.contains(label)
    }

    private static func withoutDomain(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasSuffix(".local") ? String(host.dropLast(".local".count)) : host
    }

    private static func withoutParenthesisedSuffix(_ label: String) -> String {
        label.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    }

    private static func withoutNumberSuffix(_ label: String) -> String {
        label.replacingOccurrences(of: #"-\d+$"#, with: "", options: .regularExpression)
    }

    /// Lowercased, every run of other characters a single hyphen, trimmed.
    static func slug(_ text: String) -> String {
        let pieces = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return pieces.joined(separator: "-")
    }

    /// Default names devices announce before anyone names them.
    static let genericNames: Set<String> = [
        "iphone", "ipad", "ipod", "ipod-touch", "macbook", "macbook-air", "macbook-pro", "imac", "imac-pro", "mac-mini", "macmini",
        "mac-studio", "mac-pro", "mac", "apple-tv", "appletv", "homepod", "homepod-mini", "apple-watch", "watch", "vision-pro",
        "android", "localhost", "raspberrypi", "raspberry-pi", "ubuntu", "debian", "linux", "fedora", "printer", "camera",
        "chromecast", "google-home", "google-nest-mini", "nest-hub", "echo", "echo-dot", "roku", "tv", "smart-tv", "espressif",
        "esp", "unknown", "device", "host", "computer", "desktop", "laptop", "pc", "windows", "nas", "router"
    ]

    /// Defaults that add a serial or MAC fragment ("android-1a2b3c", "esp32-a1b2c3", "DESKTOP-7Q2…").
    static let genericPrefixes = ["android", "esp32", "esp8266", "esp", "desktop", "laptop", "iphone", "ipad"]

    /// Model families announced with the model glued on ("galaxy-s23", "pixel8", "esp32cam").
    static let gluedPrefixes = ["galaxy", "pixel", "esp32", "esp8266"]
}
