import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #561 (design v3.1 §10): serials that label capture kept as `Serial:` notes lines move into the
/// serial field. The pass is idempotent and never destructive: a line is removed only after the
/// field is saved, and only from the row's current notes.
@Suite("Serial notes migration")
@MainActor
struct SerialNotesMigrationTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func row(_ notes: String?) throws -> LocalDevice {
        let row = LocalDevice(ipAddress: "192.168.4.\(Int.random(in: 2...250))", macAddress: "", notes: notes)
        context.insert(row)
        try context.save()
        return row
    }

    @Test("The first serial line becomes the field; identical duplicates go, a different serial stays", arguments: [
        ("Serial: C02XYZ", "C02XYZ", String?.none),
        ("Desk machine\nSerial: C02XYZ\nSerial: C02XYZ", "C02XYZ", "Desk machine"),
        ("Serial: A1\nSerial: B2", "A1", "Serial: B2"),
        ("Serial: \nSerial: Z9", "Z9", "Serial: "),
        ("Serial:  P7  \nnote", "P7", "note")
    ])
    func movesSerial(notes: String, serial: String, remaining: String?) throws {
        let row = try row(notes)
        try SerialNotesMigration.run(in: context)
        #expect(row.serialNumber == serial)
        #expect(row.serialSource == IdentitySource.userConfirmed.rawValue)
        #expect(row.notes == remaining)
    }

    @Test("Notes without a serial value are left alone", arguments: [String?.none, "Serial: ", "Seriall: X", "My serial: X"])
    func leavesOtherNotes(notes: String?) throws {
        let row = try row(notes)
        try SerialNotesMigration.run(in: context)
        #expect(row.serialNumber == nil)
        #expect(row.notes == notes)
    }

    @Test("A row that already has a serial keeps it; only a line equal to it is removed")
    func keepsExistingSerial() throws {
        let row = try row("Serial: OLD\nSerial: NEW")
        row.identity = DeviceIdentity(serial: IdentityValue("NEW", source: .userConfirmed))
        try context.save()
        try SerialNotesMigration.run(in: context)
        #expect(row.serialNumber == "NEW")
        #expect(row.notes == "Serial: OLD")
    }

    @Test("Running twice changes nothing more")
    func idempotent() throws {
        let row = try row("a\nSerial: S1\nSerial: S2")
        try SerialNotesMigration.run(in: context)
        try SerialNotesMigration.run(in: context)
        #expect(row.serialNumber == "S1")
        #expect(row.notes == "a\nSerial: S2")
    }

    @Test("An edit between the two saves is kept: cleanup reads the current notes")
    func editBetweenSaves() throws {
        let row = try row("Serial: S1")
        try SerialNotesMigration.adoptSerials(in: context)
        #expect(row.serialNumber == "S1")
        #expect(row.notes == "Serial: S1")
        row.notes = "Serial: S1\nadded later"
        try context.save()
        try SerialNotesMigration.removeAdoptedLines(in: context)
        #expect(row.notes == "added later")
    }

    @Test("A failed save rolls back and throws, so nothing half-applied is saved later")
    func failedSaveRollsBack() throws {
        let row = try row("Serial: S1")
        struct SaveFailed: Error {}
        #expect(throws: SaveFailed.self) {
            try SerialNotesMigration.run(in: context, save: { _ in throw SaveFailed() })
        }
        #expect(row.serialNumber == nil)
        #expect(row.notes == "Serial: S1")
        #expect(!context.hasChanges)
    }
}
