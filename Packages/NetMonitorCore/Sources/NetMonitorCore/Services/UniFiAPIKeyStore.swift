import Foundation
import Security

/// Keeps the UniFi Network API key in the Keychain, on this device only.
public struct UniFiAPIKeyStore: Sendable {
    private let service: String
    private let account = "network-api-key"

    public init(service: String = "com.netmonitor.unifi") {
        self.service = service
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var hasKey: Bool {
        read()?.isEmpty == false
    }

    /// Saves `key`, or removes the stored key when `key` is empty. Returns false on failure.
    @discardableResult
    public func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var item = baseQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
