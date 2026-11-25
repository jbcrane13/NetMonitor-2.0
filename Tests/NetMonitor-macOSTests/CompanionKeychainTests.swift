import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// The Mac's companion credentials in the real data protection keychain (#590). It needs an
/// entitled (signed) test host; the unsigned gate run skips it instead of failing.
@Suite("Companion credentials in the Mac Keychain", .serialized)
struct CompanionKeychainTests {
    static let keychainIsEntitled: Bool = {
        let probe = CompanionKeychain(service: "com.netmonitor.tests.companion.probe", accessibility: .afterFirstUnlock)
        do {
            try probe.write(Data([1]), account: "probe")
            try probe.delete(account: "probe")
            return true
        } catch {
            return false
        }
    }()

    @Test(
        "The Mac's identity and a paired phone round-trip through the real Keychain, and Remove deletes the phone",
        .enabled(if: keychainIsEntitled, "Needs an entitled (signed) test host: errSecMissingEntitlement otherwise")
    )
    func roundTrip() throws {
        let keychain = CompanionKeychain(service: "com.netmonitor.tests.companion.\(UUID().uuidString)", accessibility: .afterFirstUnlock)
        defer {
            for account in (try? keychain.accounts()) ?? [] {
                try? keychain.delete(account: account)
            }
        }
        let identity = try CompanionIdentityStore(backing: keychain).loadOrCreate()
        #expect(try CompanionIdentityStore(backing: keychain).loadOrCreate().pin == identity.pin)

        let phones = PairedPhoneStore(backing: keychain)
        let phone = PairedPhone(pin: Data(repeating: 9, count: 32), name: "iPhone", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try phones.add(phone)
        #expect(try PairedPhoneStore(backing: keychain).all() == [phone])
        try phones.remove(pin: phone.pin)
        #expect(try phones.all().isEmpty)
    }
}
