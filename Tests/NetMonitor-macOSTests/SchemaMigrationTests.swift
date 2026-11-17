import Foundation
import NetMonitorCore
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #409: SchemaV1 (frozen 2.2.x) → SchemaV2 (stored `LocalDevice.modelName`).
@Suite("Schema migration V1 → V2", .serialized)
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

        let schema = Schema(versionedSchema: SchemaV2.self)
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
        #expect(device.vendor == "Apple")
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

    @Test("(b) A fresh V2 store saves and reloads modelName")
    func v2StorePersistsModelName() throws {
        let (directory, url) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: SchemaV2.self)
        let deviceID = UUID()

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NetMonitorMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            let device = LocalDevice(id: deviceID, ipAddress: "192.168.1.30", macAddress: "")
            device.modelName = "MacBookPro18,1"
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
        #expect(device.modelName == "MacBookPro18,1")
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
        // Building a container with both schemas in the plan throws on duplicate checksums.
        let schema = Schema(versionedSchema: SchemaV2.self)
        _ = try ModelContainer(
            for: schema,
            migrationPlan: NetMonitorMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let v1Device = Schema(versionedSchema: SchemaV1.self).entities.first { $0.name == "LocalDevice" }
        let v2Device = Schema(versionedSchema: SchemaV2.self).entities.first { $0.name == "LocalDevice" }
        #expect(v1Device?.storedPropertiesByName["modelName"] == nil)
        #expect(v2Device?.storedPropertiesByName["modelName"] != nil)
    }
}

/// Locates the test bundle's resources.
private final class FixtureBundleToken {}
