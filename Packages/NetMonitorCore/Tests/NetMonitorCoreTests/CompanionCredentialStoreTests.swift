import Foundation
import Testing
@testable import NetMonitorCore

@Suite("PairedPhoneStore")
struct PairedPhoneStoreTests {
    private func phone(_ byte: UInt8, name: String = "iPhone") -> PairedPhone {
        PairedPhone(pin: Data(repeating: byte, count: 32), name: name, pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("Phones added survive a new store over the same backing, and removal deletes them")
    func roundTrip() throws {
        let backing = InMemoryCompanionSecretStore()
        let store = PairedPhoneStore(backing: backing)
        try store.add(phone(1, name: "Work iPhone"))
        try store.add(phone(2))
        #expect(try PairedPhoneStore(backing: backing).all().map(\.name).sorted() == ["Work iPhone", "iPhone"])
        try store.remove(pin: phone(1).pin)
        #expect(try store.all() == [phone(2)])
    }

    @Test("A pin already paired is refused rather than replaced")
    func refusesCollision() throws {
        let store = PairedPhoneStore(backing: InMemoryCompanionSecretStore())
        try store.add(phone(1, name: "First"))
        #expect(throws: CompanionCredentialError.alreadyPaired) { try store.add(phone(1, name: "Second")) }
        #expect(try store.all().map(\.name) == ["First"])
    }

    @Test("Storage failures surface as errors, on write and on delete")
    func surfacesFailures() throws {
        let backing = InMemoryCompanionSecretStore()
        let store = PairedPhoneStore(backing: backing)
        backing.failWrites = true
        #expect(throws: CompanionCredentialError.self) { try store.add(phone(1)) }
        #expect(try store.all().isEmpty)
        backing.failWrites = false
        try store.add(phone(1))
        backing.failDeletes = true
        #expect(throws: CompanionCredentialError.self) { try store.remove(pin: phone(1).pin) }
    }
}

@Suite("Companion identity and paired Mac stores")
struct CompanionIdentityStoreTests {
    @Test("The Mac's identity is created once and then reloaded with the same pin")
    func loadOrCreate() throws {
        let backing = InMemoryCompanionSecretStore()
        let first = try CompanionIdentityStore(backing: backing).loadOrCreate()
        let again = try CompanionIdentityStore(backing: backing).loadOrCreate()
        #expect(first.pin == again.pin)
    }

    @Test("The phone keeps one paired Mac with its own identity; forgetting deletes both")
    func pairedMacRoundTrip() throws {
        let backing = InMemoryCompanionSecretStore()
        let store = PairedMacStore(backing: backing)
        #expect(try store.load() == nil)
        let phoneIdentity = CompanionIdentity()
        let record = PairedMacRecord(
            macID: UUID(), macName: "Studio Mac", macPin: Data(repeating: 3, count: 32),
            host: "studio.local", port: 8849, phoneIdentity: phoneIdentity.rawRepresentation
        )
        try store.save(record)
        let loaded = try #require(try PairedMacStore(backing: backing).load())
        #expect(loaded == record)
        #expect(try CompanionIdentity(rawRepresentation: loaded.phoneIdentity).pin == phoneIdentity.pin)
        try store.forget()
        #expect(try store.load() == nil)
    }
}
