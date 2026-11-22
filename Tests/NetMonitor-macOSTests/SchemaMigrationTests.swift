import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #409: SchemaV1 (frozen 2.2.x) → SchemaV2 (stored `LocalDevice.modelName`).
/// #462: SchemaV2 (frozen 2.2.2–2.2.3) → SchemaV3 (identity sources, `friendlyName`, `vendor`
/// rebuilt from the MAC prefix).
@Suite("Schema migration V1 → V2 → V3", .serialized)
@MainActor
struct SchemaMigrationTests {

    private func makeStoreURL() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "netmonitor-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appending(path: "default.store"))
    }

    private struct V1Fixture {
        let deviceID = UUID()
        let targetID = UUID()
        let sessionID = UUID()
        let recordID = UUID()
        let profileID = UUID()
    }

    /// Writes one row of every V1 model the way 2.2.x did: frozen models, no plan.
    private func writeV1Store(at url: URL, _ fixture: V1Fixture) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let context = container.mainContext

        let device = SchemaV1.LocalDevice(
            id: fixture.deviceID, ipAddress: "192.168.1.20", macAddress: "00:11:22:33:44:55",
            hostname: "studio.local", vendor: "Apple"
        )
        device.customName = "Studio"
        device.deviceType = .computer
        device.openPorts = [22, 445]
        device.discoveredServices = ["_ssh._tcp"]
        device.networkProfileID = fixture.profileID
        context.insert(device)

        let target = SchemaV1.NetworkTarget(id: fixture.targetID, name: "Gateway", host: "192.168.1.1", targetProtocol: .icmp)
        context.insert(target)
        let measurement = SchemaV1.TargetMeasurement(latency: 4.5, isReachable: true)
        measurement.target = target
        context.insert(measurement)

        context.insert(SchemaV1.SessionRecord(id: fixture.sessionID))
        let record = SchemaV1.ConnectivityRecord(id: fixture.recordID, profileID: fixture.profileID, isOnline: true)
        record.latencyMs = 12
        context.insert(record)
        try context.save()
    }

    @Test("(a) A V1 store reopened with the plan keeps every row and its data")
    func v1StoreMigratesIntact() throws {
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = V1Fixture()
        try writeV1Store(at: url, fixture)

        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NetMonitorMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let context = container.mainContext

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        let device = try #require(devices.first)
        #expect(device.id == fixture.deviceID)
        #expect(device.ipAddress == "192.168.1.20")
        #expect(device.macAddress == "00:11:22:33:44:55")
        #expect(device.hostname == "studio.local")
        // V2 → V3: `vendor` is the MAC prefix's maker (00:11:22 is CIMSYS); the maker it held
        // moves to `manufacturer` without a source.
        #expect(device.vendor == MACVendorLookupService.offlineVendor(macAddress: "00:11:22:33:44:55"))
        #expect(device.manufacturer == "Apple")
        #expect(device.makerSource == nil)
        #expect(device.customName == "Studio")
        #expect(device.deviceType == .computer)
        #expect(device.openPorts == [22, 445])
        #expect(device.discoveredServices == ["_ssh._tcp"])
        #expect(device.networkProfileID == fixture.profileID)
        #expect(device.modelName == nil)

        let targets = try context.fetch(FetchDescriptor<NetworkTarget>())
        #expect(targets.map(\.id) == [fixture.targetID])
        #expect(targets.first?.measurements.map(\.latency) == [4.5])
        #expect(try context.fetch(FetchDescriptor<SessionRecord>()).map(\.id) == [fixture.sessionID])
        let records = try context.fetch(FetchDescriptor<ConnectivityRecord>())
        #expect(records.map(\.id) == [fixture.recordID])
        #expect(records.first?.latencyMs == 12)

        // The migrated store takes the new attribute.
        device.modelName = "Mac16,10"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).first?.modelName == "Mac16,10")
    }

    @Test("(b) A fresh V3 store saves and reloads the identity and its sources")
    func v3StorePersistsIdentity() throws {
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: SchemaV3.self)
        let identity = DeviceIdentity(
            maker: IdentityValue("Apple", source: .bonjour),
            model: IdentityValue("MacBookPro18,1", source: .bonjour),
            friendlyName: IdentityValue("Studio", source: .unifi)
        )
        let deviceID = UUID()

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NetMonitorMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            let device = LocalDevice(id: deviceID, ipAddress: "192.168.1.30", macAddress: "")
            device.identity = identity
            container.mainContext.insert(device)
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: NetMonitorMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let device = try #require(try reopened.mainContext.fetch(FetchDescriptor<LocalDevice>()).first)
        #expect(device.id == deviceID)
        #expect(device.identity == identity)
    }

    @Test("(c) The app's bootstrap opens an existing V1 store durably, not in memory")
    func bootstrapDoesNotFallBackForV1Store() throws {
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = V1Fixture()
        try writeV1Store(at: url, fixture)

        let outcome = try MacPersistence.makeOutcome(storeURL: url, inMemory: false)
        #expect(!outcome.isDegraded, "fell back: \(outcome.recovery?.diagnosticText ?? "")")
        #expect(outcome.store.configurations.first?.isStoredInMemoryOnly == false)
        let devices = try outcome.store.mainContext.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.map(\.id) == [fixture.deviceID])
    }

    /// `Fixtures/v2.2-default.store` was written by the 2.2.x model code itself (main at
    /// 4e990b5: the live models as SchemaV1, through the single-schema plan), not by the
    /// frozen copies, so it proves the frozen SchemaV1 matches what shipped.
    @Test("A store written by the 2.2.x models migrates through the plan and the bootstrap")
    func shippedFixtureStoreMigrates() throws {
        let fixture = try #require(
            Bundle(for: FixtureBundleToken.self).url(forResource: "v2.2-default", withExtension: "store"),
            "fixture missing from the test bundle"
        )
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: fixture, to: url)

        let outcome = try MacPersistence.makeOutcome(storeURL: url, inMemory: false)
        #expect(!outcome.isDegraded, "fell back: \(outcome.recovery?.diagnosticText ?? "")")
        let context = outcome.store.mainContext

        let device = try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
        #expect(device.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(device.hostname == "studio.local")
        #expect(device.customName == "Studio")
        #expect(device.deviceType == .computer)
        #expect(device.openPorts == [22, 445])
        #expect(device.modelName == nil)
        let target = try #require(try context.fetch(FetchDescriptor<NetworkTarget>()).first)
        #expect(target.measurements.map(\.latency) == [4.5])
        #expect(try context.fetch(FetchDescriptor<SessionRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ConnectivityRecord>()).first?.latencyMs == 12)

        device.modelName = "Mac16,10"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).first?.modelName == "Mac16,10")
    }

    /// iOS opens an unversioned `Schema` of the live models with no plan, so it relies on
    /// SwiftData inferring the lightweight migration for the added optional attribute.
    @Test("An unversioned container of the live models also opens a V1 store")
    func unversionedContainerOpensV1Store() throws {
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = V1Fixture()
        try writeV1Store(at: url, fixture)

        let schema = Schema([
            NetworkTarget.self, TargetMeasurement.self, LocalDevice.self, SessionRecord.self, ConnectivityRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let devices = try container.mainContext.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.map(\.id) == [fixture.deviceID])
        #expect(devices.first?.hostname == "studio.local")
    }

    @Test("The schemas differ, so the plan has no duplicate version checksums")
    func schemasAreDistinct() throws {
        #expect(SchemaV1.versionIdentifier != SchemaV2.versionIdentifier)
        #expect(SchemaV2.versionIdentifier != SchemaV3.versionIdentifier)
        // Building a container with every schema in the plan throws on duplicate checksums.
        let schema = Schema(versionedSchema: SchemaV3.self)
        _ = try ModelContainer(
            for: schema,
            migrationPlan: NetMonitorMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let v1Device = Schema(versionedSchema: SchemaV1.self).entities.first { $0.name == "LocalDevice" }
        let v2Device = Schema(versionedSchema: SchemaV2.self).entities.first { $0.name == "LocalDevice" }
        let v3Device = Schema(versionedSchema: SchemaV3.self).entities.first { $0.name == "LocalDevice" }
        #expect(v1Device?.storedPropertiesByName["modelName"] == nil)
        #expect(v2Device?.storedPropertiesByName["modelName"] != nil)
        #expect(v2Device?.storedPropertiesByName["modelSource"] == nil)
        for name in ["modelSource", "makerSource", "friendlyName", "friendlyNameSource"] {
            #expect(v3Device?.storedPropertiesByName[name] != nil, "\(name)")
        }
    }

    /// `Fixtures/v2.2.3-default.store` was written by the live models at d54748e (2.2.3,
    /// SchemaV2) with synthetic rows, so it proves the frozen SchemaV2 matches what shipped.
    @Test("A 2.2.3 store migrates to V3: vendor holds only the MAC prefix's maker, and no maker is lost")
    func shippedV2FixtureStoreMigrates() throws {
        let fixture = try #require(
            Bundle(for: FixtureBundleToken.self).url(forResource: "v2.2.3-default", withExtension: "store"),
            "fixture missing from the test bundle"
        )
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: fixture, to: url)

        let outcome = try MacPersistence.makeOutcome(storeURL: url, inMemory: false)
        #expect(!outcome.isDegraded, "fell back: \(outcome.recovery?.diagnosticText ?? "")")
        let rows = try outcome.store.mainContext.fetch(FetchDescriptor<LocalDevice>())
        let byIP = Dictionary(uniqueKeysWithValues: rows.map { ($0.ipAddress, $0) })
        #expect(rows.count == 4)

        // A vendor naming the MAC prefix's company stays as it was.
        let studio = try #require(byIP["192.168.1.20"])
        #expect(studio.vendor == "Apple")
        #expect(studio.manufacturer == nil)
        #expect(studio.modelName == "Mac16,10")
        #expect(studio.modelSource == nil)
        #expect(studio.displayName == "Studio")

        // No MAC: a hostname guess sat in `vendor`; it moves to `manufacturer`, unranked.
        let plug = try #require(byIP["192.168.1.21"])
        #expect(plug.vendor == nil)
        #expect(plug.manufacturer == "Meross")
        #expect(plug.maker == "Meross")

        // No MAC: the UPnP maker was in both; `vendor` is cleared. The friendly name that
        // sat in `hostname` can't be told apart, so it stays there.
        let tv = try #require(byIP["192.168.1.22"])
        #expect(tv.vendor == nil)
        #expect(tv.manufacturer == "Samsung Electronics")
        #expect(tv.hostname == "Living Room TV")
        #expect(tv.friendlyName == nil)

        // The chip's maker stays in `vendor`; the announced maker stays in `manufacturer`.
        let bulb = try #require(byIP["192.168.1.23"])
        #expect(bulb.vendor == "Espressif")
        #expect(bulb.manufacturer == "Wiz")
        // Unranked until a scan reports it again, so the MAC prefix shows meanwhile.
        #expect(bulb.maker == "Espressif")
    }

    @Test("Maker names match by their first word", arguments: [
        ("Apple", "Apple, Inc.", true),
        ("Samsung Electronics Co.,Ltd", "SAMSUNG ELECTRO-MECHANICS", true),
        ("Meross", "Espressif Inc.", false),
        ("", "Apple", false)
    ])
    func sameCompany(lhs: String, rhs: String, same: Bool) {
        #expect(NetMonitorMigrationPlan.sameCompany(lhs, rhs) == same)
    }
}

/// Locates the test bundle's resources.
private final class FixtureBundleToken {}
