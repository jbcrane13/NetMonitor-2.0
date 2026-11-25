import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #561, #594 (design v3.1): SchemaV3 (frozen, 2.3) → SchemaV4 adds optional serial and
/// device-group fields, a lightweight migration. Every shipped fixture must reach V4 with every
/// stored value unchanged.
@Suite("Schema migration V3 → V4", .serialized)
@MainActor
struct SchemaV4MigrationTests {

    private func copyFixture(_ name: String) throws -> (directory: URL, store: URL) {
        let fixture = try #require(
            Bundle(for: V4FixtureToken.self).url(forResource: name, withExtension: "store"), "fixture \(name) missing from the test bundle"
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "netmonitor-v4-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: store)
        return (directory, store)
    }

    @Test("The frozen SchemaV3 is exactly what 2.3 wrote: the fixture opens as V3 with no migration")
    func frozenV3MatchesShippedStore() throws {
        let (directory, url) = try copyFixture("v2.3-default")
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(
            for: schema, migrationPlan: OnlyV3Plan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SchemaV3.LocalDevice>()) == 3)
    }

    @Test("A 2.3 store migrates to V4 through the bootstrap with every stored value unchanged")
    func v23StoreKeepsEveryValue() throws {
        let (directory, url) = try copyFixture("v2.3-default")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try StoreDump(url)
        #expect(before.rowCount == 7)

        let outcome = try MacPersistence.makeOutcome(storeURL: url, inMemory: false)
        #expect(!outcome.isDegraded, "fell back: \(outcome.recovery?.diagnosticText ?? "")")
        let rows = try outcome.store.mainContext.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 3)
        for row in rows {
            #expect(row.serialNumber == nil && row.serialSource == nil)
            #expect(row.deviceGroupID == nil && row.groupPrimaryID == nil && row.groupSource == nil)
            #expect(row.notSameAsIDs == nil && row.bonjourHost == nil && row.bonjourHostSeenAt == nil)
        }
        let studio = try #require(rows.first { $0.ipAddress == "192.168.1.20" })
        #expect(studio.identity.model == IdentityValue("Mac16,10", source: .bonjour))
        #expect(studio.identity.maker == IdentityValue("Apple", source: .userConfirmed))
        #expect(studio.identity.friendlyName == IdentityValue("Studio Display Mac", source: .upnp))
        #expect(studio.notes == "Desk machine\nSerial: C02XYZ123\nSerial: C02XYZ123")
        withExtendedLifetime(outcome.store) {}

        let after = try StoreDump(url, onlyColumns: before.columns)
        #expect(after == before)
    }

    @Test("Every shipped fixture reaches V4 and takes the new fields", arguments: ["v2.2-default", "v2.2.3-default", "v2.3-default"])
    func shippedFixturesReachV4(name: String) throws {
        let (directory, url) = try copyFixture(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcome = try MacPersistence.makeOutcome(storeURL: url, inMemory: false)
        #expect(!outcome.isDegraded, "fell back: \(outcome.recovery?.diagnosticText ?? "")")
        let context = outcome.store.mainContext
        let row = try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
        let group = UUID()
        row.identity = row.identity.merging(DeviceIdentity(serial: IdentityValue("S1", source: .userConfirmed)))
        row.deviceGroupID = group
        row.groupPrimaryID = row.id
        row.notSameAsIDs = [UUID()]
        row.bonjourHost = "studio.local"
        try context.save()
        let reread = try #require(try ModelContext(outcome.store).fetch(FetchDescriptor<LocalDevice>()).first { $0.id == row.id })
        #expect(reread.serialNumber == "S1")
        #expect(reread.deviceGroupID == group)
        #expect(reread.notSameAsIDs?.count == 1)
        #expect(reread.bonjourHost == "studio.local")
    }

    @Test("The V4 schema adds only optional LocalDevice fields to V3")
    func v4AddsOnlyOptionalFields() throws {
        let v3 = try #require(Schema(versionedSchema: SchemaV3.self).entities.first { $0.name == "LocalDevice" })
        let v4 = try #require(Schema(versionedSchema: SchemaV4.self).entities.first { $0.name == "LocalDevice" })
        let added = Set(v4.storedPropertiesByName.keys).subtracting(v3.storedPropertiesByName.keys)
        #expect(added == [
            "serialNumber", "serialSource", "deviceGroupID", "groupPrimaryID", "groupSource", "notSameAsIDs", "bonjourHost", "bonjourHostSeenAt"
        ])
        for name in added {
            let property = try #require(v4.storedPropertiesByName[name])
            #expect(property.isOptional, "\(name)")
        }
        #expect(Set(v3.storedPropertiesByName.keys).isSubset(of: v4.storedPropertiesByName.keys))
        #expect(SchemaV3.versionIdentifier != SchemaV4.versionIdentifier)
    }
}

/// Opens a store only if it already is V3 (no stages), so the hash comparison is exact.
private enum OnlyV3Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV3.self] }
    static var stages: [MigrationStage] { [] }
}

private final class V4FixtureToken {}
