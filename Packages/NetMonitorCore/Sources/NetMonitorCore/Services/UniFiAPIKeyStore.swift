import Foundation
import Security

/// The UniFi controller the user enrolled, with the API key bound to it. The key is only ever
/// sent to `host`, over a connection verified as this controller (see `UniFiControllerTrust`).
public struct UniFiControllerEnrollment: Codable, Equatable, Sendable {
    /// Host name or IPv4 address, lowercase, without scheme, port or path.
    public let host: String
    /// SHA-256 of the controller's certificate (lowercase hex) for a self-signed controller,
    /// checked independently by the user. Nil means the certificate must pass standard HTTPS
    /// validation for `host`.
    public let certificateSHA256: String?
    public let apiKey: String

    public init(host: String, certificateSHA256: String?, apiKey: String) {
        self.host = host
        self.certificateSHA256 = certificateSHA256
        self.apiKey = apiKey
    }

    /// "https://UniFi.local/" → "unifi.local". Nil unless it is a plain host name or IPv4 address.
    public static func normalizedHost(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("https://") {
            host.removeFirst("https://".count)
        }
        while host.hasSuffix("/") {
            host.removeLast()
        }
        guard !host.isEmpty, host.count <= 253,
              host.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$"#, options: .regularExpression) != nil
        else { return nil }
        return host
    }

    /// "AB:CD:…" or "ab cd …" → 64 lowercase hex digits. Nil unless it is a SHA-256 fingerprint.
    public static func normalizedFingerprint(_ text: String) -> String? {
        let hex = text.lowercased().filter { !": \n\t".contains($0) }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }
}

/// Keeps the UniFi enrollment in the Keychain, on this device only.
///
/// A key saved by an earlier version without an enrolled controller is never returned for use:
/// `hasUnboundKey` reports it so Settings can ask the user to enroll or remove it.
public struct UniFiAPIKeyStore: Sendable {
    private let service: String
    private let enrollmentAccount = "controller-enrollment"
    private let legacyAccount = "network-api-key"

    public init(service: String = "com.netmonitor.unifi") {
        self.service = service
    }

    /// The enrolled controller and its key, or nil when none is enrolled.
    public func enrollment() -> UniFiControllerEnrollment? {
        guard let data = read(account: enrollmentAccount),
              let enrollment = try? JSONDecoder().decode(UniFiControllerEnrollment.self, from: data),
              UniFiControllerEnrollment.normalizedHost(enrollment.host) == enrollment.host,
              !enrollment.apiKey.isEmpty else { return nil }
        return enrollment
    }

    /// A key from an earlier version, not bound to any controller, is still saved.
    public var hasUnboundKey: Bool {
        read(account: legacyAccount) != nil
    }

    /// Saves `enrollment` and drops any unbound key. Returns false on failure.
    @discardableResult
    public func save(_ enrollment: UniFiControllerEnrollment) -> Bool {
        guard let data = try? JSONEncoder().encode(enrollment) else { return false }
        delete(account: legacyAccount)
        delete(account: enrollmentAccount)
        var item = query(account: enrollmentAccount)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the enrollment and any unbound key.
    public func removeAll() {
        delete(account: enrollmentAccount)
        delete(account: legacyAccount)
    }

    private func read(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, !data.isEmpty else { return nil }
        return data
    }

    private func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
