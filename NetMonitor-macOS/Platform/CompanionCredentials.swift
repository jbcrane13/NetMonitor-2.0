import Foundation
import NetMonitorCore

/// What the Mac's companion link trusts (#590): its own TLS identity, its ID, the paired phones,
/// and the live trust gate built from them.
struct CompanionCredentials: Sendable {
    static let keychainService = "com.netmonitor.companion"
    static let macIDKey = "netmonitor.companion.macID"
    /// Pins still refused after a Keychain delete failed; retried at every launch.
    static let deniedPinsKey = "netmonitor.companion.deniedPins"

    let identity: CompanionIdentity
    let macID: UUID
    let macName: String
    let phones: PairedPhoneStore
    let gate: CompanionTrustGate
    private let denied: DeniedPins

    /// The Keychain-backed credentials. Throws when the Keychain refuses, in which case the
    /// companion service stays off: there is no unauthenticated fallback.
    static func live(defaults: UserDefaults = .standard) throws -> CompanionCredentials {
        let keychain = CompanionKeychain(service: keychainService, accessibility: .afterFirstUnlock)
        return try make(backing: keychain, defaults: defaults)
    }

    /// Credentials that never touch the Keychain, for tests and `--uitesting` launches.
    static func inMemory(
        seedPhones: [PairedPhone] = [],
        defaults: UserDefaults,
        backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore()
    ) -> CompanionCredentials {
        let phones = PairedPhoneStore(backing: backing)
        for phone in seedPhones {
            try? phones.add(phone)
        }
        // An in-memory store never throws on these paths.
        // swiftlint:disable:next force_try
        return try! make(backing: backing, defaults: defaults)
    }

    private static func make(backing: any CompanionSecretStore, defaults: UserDefaults) throws -> CompanionCredentials {
        let identity = try CompanionIdentityStore(backing: backing).loadOrCreate()
        let phones = PairedPhoneStore(backing: backing)
        let denied = DeniedPins(defaults: defaults)
        for hex in denied.all() {
            if let pin = Data(hexString: hex), (try? phones.remove(pin: pin)) != nil {
                denied.remove(hex)
            }
        }
        let stillDenied = denied.all()
        let trusted = try phones.all().map(\.pin).filter { !stillDenied.contains($0.hexString) }
        return CompanionCredentials(
            identity: identity,
            macID: macID(defaults: defaults),
            macName: Host.current().localizedName ?? "Mac",
            phones: phones,
            gate: CompanionTrustGate(paired: trusted),
            denied: denied
        )
    }

    private static func macID(defaults: UserDefaults) -> UUID {
        if let stored = defaults.string(forKey: macIDKey).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let created = UUID()
        defaults.set(created.uuidString, forKey: macIDKey)
        return created
    }

    /// The paired phones, without any still denied after a failed delete.
    func pairedPhones() -> [PairedPhone] {
        let blocked = denied.all()
        return ((try? phones.all()) ?? [])
            .filter { !blocked.contains($0.pin.hexString) }
            .sorted { $0.pairedAt < $1.pairedAt }
    }

    /// Denies `pin` now and deletes its Keychain item. When the delete fails, the pin stays
    /// denied across launches and this returns false so Settings can say so.
    func revoke(_ pin: Data) -> Bool {
        gate.revoke(pin)
        do {
            try phones.remove(pin: pin)
            return true
        } catch {
            denied.insert(pin.hexString)
            return false
        }
    }
}

/// Pins still refused after their Keychain delete failed, kept in defaults (pins aren't secret).
/// `UserDefaults` is documented as thread-safe, which is what the unchecked conformance rests on.
private final class DeniedPins: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func all() -> Set<String> {
        Set(defaults.stringArray(forKey: CompanionCredentials.deniedPinsKey) ?? [])
    }

    func insert(_ hex: String) {
        defaults.set(Array(all().union([hex])), forKey: CompanionCredentials.deniedPinsKey)
    }

    func remove(_ hex: String) {
        defaults.set(Array(all().subtracting([hex])), forKey: CompanionCredentials.deniedPinsKey)
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
