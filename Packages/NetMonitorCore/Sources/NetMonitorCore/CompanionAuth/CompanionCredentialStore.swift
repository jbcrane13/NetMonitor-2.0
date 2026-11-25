import Foundation
import os
import Security
import Synchronization

public enum CompanionCredentialError: Error, Equatable, Sendable {
    /// A Keychain call returned this status.
    case keychain(OSStatus)
    case alreadyPaired
    case corrupt
}

/// Raw secret storage for the companion link (#590), one item per account.
public protocol CompanionSecretStore: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
    func accounts() throws -> [String]
}

/// The Keychain, on this device only: the data protection keychain (also on macOS), never
/// synchronised, every status checked.
public struct CompanionKeychain: CompanionSecretStore {
    public enum Accessibility: Sendable {
        /// The Mac's menu bar app runs from login, before anyone unlocks it interactively.
        case afterFirstUnlock
        /// The iPhone uses the link only in the foreground.
        case whenUnlocked

        var value: CFString {
            switch self {
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenUnlocked: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }

    private let service: String
    private let accessibility: Accessibility

    public init(service: String, accessibility: Accessibility) {
        self.service = service
        self.accessibility = accessibility
    }

    public func read(account: String) throws -> Data? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw CompanionCredentialError.keychain(status) }
        guard let data = result as? Data else { throw CompanionCredentialError.corrupt }
        return data
    }

    /// Replaces the item in place, or adds it: a failed write never loses the existing record.
    public func write(_ data: Data, account: String) throws {
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: accessibility.value]
        let updated = SecItemUpdate(base(account: account) as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess {
            return
        }
        guard updated == errSecItemNotFound else { throw CompanionCredentialError.keychain(updated) }
        var item = base(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessibility.value
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw CompanionCredentialError.keychain(status) }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(base(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CompanionCredentialError.keychain(status) }
    }

    public func accounts() throws -> [String] {
        var query = base(account: nil)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else { throw CompanionCredentialError.keychain(status) }
        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func base(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }
}

/// Storage in memory, for tests and UI-test launches; it can be told to fail.
public final class InMemoryCompanionSecretStore: CompanionSecretStore {
    private struct State {
        var items: [String: Data] = [:]
        var failWrites = false
        var failDeletes = false
    }

    private let state = Mutex(State())

    public init() {}

    public var failWrites: Bool {
        get { state.withLock { $0.failWrites } }
        set { state.withLock { $0.failWrites = newValue } }
    }

    public var failDeletes: Bool {
        get { state.withLock { $0.failDeletes } }
        set { state.withLock { $0.failDeletes = newValue } }
    }

    public func read(account: String) throws -> Data? {
        state.withLock { $0.items[account] }
    }

    public func write(_ data: Data, account: String) throws {
        try state.withLock { state in
            if state.failWrites {
                throw CompanionCredentialError.keychain(errSecIO)
            }
            state.items[account] = data
        }
    }

    public func delete(account: String) throws {
        try state.withLock { state in
            if state.failDeletes {
                throw CompanionCredentialError.keychain(errSecIO)
            }
            state.items[account] = nil
        }
    }

    public func accounts() throws -> [String] {
        state.withLock { Array($0.items.keys) }
    }
}

/// Both record stores skip a record that doesn't decode and log it, so one damaged item never
/// blocks the rest: a corrupt phone is left out of the list, a corrupt Mac reads as not paired.
enum CompanionRecordLog {
    static let logger = Logger(subsystem: "com.netmonitor", category: "CompanionCredentials")

    static func corrupt(_ kind: String) {
        logger.error("Skipped a corrupt \(kind, privacy: .public) record in the Keychain")
    }
}

// MARK: - Records

/// A phone the Mac trusts, known only by its pin. The name is the phone's own, display only.
public struct PairedPhone: Codable, Sendable, Equatable, Identifiable {
    public let pin: Data
    public let name: String
    public let pairedAt: Date

    public var id: Data { pin }

    public init(pin: Data, name: String, pairedAt: Date) {
        self.pin = pin
        self.name = name
        self.pairedAt = pairedAt
    }
}

/// The Mac's paired phones, one Keychain item each under `phone.<pin hex>`.
public struct PairedPhoneStore: Sendable {
    private let backing: any CompanionSecretStore
    private static let prefix = "phone."

    public init(backing: any CompanionSecretStore) {
        self.backing = backing
    }

    public func all() throws -> [PairedPhone] {
        try backing.accounts().filter { $0.hasPrefix(Self.prefix) }.compactMap { account in
            guard let data = try backing.read(account: account) else { return nil }
            guard let phone = try? JSONDecoder().decode(PairedPhone.self, from: data) else {
                CompanionRecordLog.corrupt("paired phone")
                return nil
            }
            return phone
        }
    }

    public func add(_ phone: PairedPhone) throws {
        let account = Self.account(for: phone.pin)
        guard try backing.read(account: account) == nil else { throw CompanionCredentialError.alreadyPaired }
        try backing.write(JSONEncoder().encode(phone), account: account)
    }

    public func remove(pin: Data) throws {
        try backing.delete(account: Self.account(for: pin))
    }

    private static func account(for pin: Data) -> String {
        prefix + pin.hexString
    }
}

/// This device's own TLS identity, created on first use.
public struct CompanionIdentityStore: Sendable {
    private let backing: any CompanionSecretStore
    private let account: String

    public init(backing: any CompanionSecretStore, account: String = "identity") {
        self.backing = backing
        self.account = account
    }

    public func loadOrCreate() throws -> CompanionIdentity {
        if let raw = try backing.read(account: account) {
            return try CompanionIdentity(rawRepresentation: raw)
        }
        let identity = CompanionIdentity()
        try backing.write(identity.rawRepresentation, account: account)
        return identity
    }
}

/// The Mac an iPhone is paired with, and the identity the phone made for that pairing.
public struct PairedMacRecord: Codable, Sendable, Equatable {
    public let macID: UUID
    public let macName: String
    public let macPin: Data
    public let host: String?
    public let port: UInt16
    /// The phone's private key for this pairing only; a new one on every re-pair.
    public let phoneIdentity: Data

    public init(macID: UUID, macName: String, macPin: Data, host: String?, port: UInt16, phoneIdentity: Data) {
        self.macID = macID
        self.macName = macName
        self.macPin = macPin
        self.host = host
        self.port = port
        self.phoneIdentity = phoneIdentity
    }
}

/// The iPhone's single paired Mac.
public struct PairedMacStore: Sendable {
    private let backing: any CompanionSecretStore
    private static let account = "paired-mac"

    public init(backing: any CompanionSecretStore) {
        self.backing = backing
    }

    public func load() throws -> PairedMacRecord? {
        guard let data = try backing.read(account: Self.account) else { return nil }
        guard let record = try? JSONDecoder().decode(PairedMacRecord.self, from: data) else {
            CompanionRecordLog.corrupt("paired Mac")
            return nil
        }
        return record
    }

    public func save(_ record: PairedMacRecord) throws {
        try backing.write(JSONEncoder().encode(record), account: Self.account)
    }

    public func forget() throws {
        try backing.delete(account: Self.account)
    }
}
