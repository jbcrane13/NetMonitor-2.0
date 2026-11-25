import Foundation
import NetMonitorCore
import Synchronization

/// What the Mac's companion link trusts (#590): its own TLS identity, its ID, the paired phones,
/// and the live trust gate built from them.
struct CompanionCredentials: Sendable {
    static let keychainService = "com.netmonitor.companion"
    static let macIDKey = "netmonitor.companion.macID"
    /// Pins still refused after a Keychain delete failed; retried at every launch.
    static let deniedPinsKey = "netmonitor.companion.deniedPins"

    let identity: CompanionIdentity
    let macID: UUID
    /// Shown on the phone; display only.
    let macName: String
    /// Where the QR tells the phone to connect when Bonjour can't find the Mac.
    let host: String?
    let phones: PairedPhoneStore
    let gate: CompanionTrustGate
    private let denied: DeniedPins

    /// The Keychain-backed credentials. Throws when the Keychain refuses, in which case the
    /// companion service stays off: there is no unauthenticated fallback.
    /// `defaultsSuite` nil is the standard defaults.
    static func live(defaultsSuite: String? = nil) throws -> CompanionCredentials {
        let keychain = CompanionKeychain(service: keychainService, accessibility: .afterFirstUnlock)
        return try make(
            backing: keychain, defaultsSuite: defaultsSuite,
            macName: Host.current().localizedName ?? "Mac", host: ProcessInfo.processInfo.hostName
        )
    }

    /// Credentials that never touch the Keychain, for tests and `--uitesting` launches.
    static func inMemory(
        seedPhones: [PairedPhone] = [],
        defaultsSuite: String?,
        backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore()
    ) -> CompanionCredentials {
        let phones = PairedPhoneStore(backing: backing)
        for phone in seedPhones {
            try? phones.add(phone)
        }
        // An in-memory store never throws on these paths.
        // A made-up name and no host, so evidence screenshots and QR codes carry nothing real.
        // swiftlint:disable:next force_try
        return try! make(backing: backing, defaultsSuite: defaultsSuite, macName: "Test Mac", host: nil)
    }

    private static func make(
        backing: any CompanionSecretStore,
        defaultsSuite: String?,
        macName: String,
        host: String?
    ) throws -> CompanionCredentials {
        let identity = try CompanionIdentityStore(backing: backing).loadOrCreate()
        let phones = PairedPhoneStore(backing: backing)
        let denied = DeniedPins(suite: defaultsSuite)
        for hex in denied.all() {
            if let pin = Data(hexString: hex), (try? phones.remove(pin: pin)) != nil {
                denied.remove(hex)
            }
        }
        let stillDenied = denied.all()
        let trusted = try phones.all().map(\.pin).filter { !stillDenied.contains($0.hexString) }
        return CompanionCredentials(
            identity: identity,
            macID: macID(defaults: denied.defaults),
            macName: macName,
            host: host,
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
/// It holds the suite's name, not a `UserDefaults` (which isn't `Sendable`), and serialises its
/// read-modify-write behind a `Mutex`.
private final class DeniedPins: Sendable {
    private let suite: String?
    private let lock = Mutex(())

    init(suite: String?) {
        self.suite = suite
    }

    var defaults: UserDefaults {
        suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func all() -> Set<String> {
        lock.withLock { _ in read() }
    }

    func insert(_ hex: String) {
        lock.withLock { _ in defaults.set(Array(read().union([hex])), forKey: CompanionCredentials.deniedPinsKey) }
    }

    func remove(_ hex: String) {
        lock.withLock { _ in defaults.set(Array(read().subtracting([hex])), forKey: CompanionCredentials.deniedPinsKey) }
    }

    private func read() -> Set<String> {
        Set(defaults.stringArray(forKey: CompanionCredentials.deniedPinsKey) ?? [])
    }
}
