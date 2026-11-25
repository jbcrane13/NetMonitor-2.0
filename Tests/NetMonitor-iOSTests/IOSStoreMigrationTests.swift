import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #561, #594 (design v3.1): the iOS store is unversioned, so SwiftData infers a lightweight
/// migration for the optional serial and device-group fields. A shipped store must open with every
/// stored value unchanged, from 2.3 and from older shapes a user may skip from.
@Suite("iOS store migration", .serialized)
@MainActor
struct IOSStoreMigrationTests {

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "netmonitor-ios-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The app's schema, opened the way `NetmonitorApp` opens it.
    private func openAppStore(at url: URL) throws -> ModelContainer {
        let schema = AppModelStore.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    @Test("A 2.3 store opens with the new fields and every stored value unchanged")
    func v23StoreKeepsEveryValue() throws {
        let fixture = try #require(
            Bundle(for: IOSFixtureToken.self).url(forResource: "ios-v2.3-default", withExtension: "store"), "fixture missing from the test bundle"
        )
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        let before = try StoreDump(url)
        #expect(before.rowCount == 7)

        let container = try openAppStore(at: url)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.serialNumber == nil && $0.deviceGroupID == nil && $0.notSameAsIDs == nil && $0.bonjourHost == nil })
        #expect(try context.fetchCount(FetchDescriptor<PairedMac>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpeedTestResult>()) == 1)
        withExtendedLifetime(container) {}

        let after = try StoreDump(url, onlyColumns: before.columns)
        #expect(after == before)
    }

    @Test("After the launch pass, the 2.3 fixture's serial lines are fields")
    func v23SerialLinesMove() throws {
        let fixture = try #require(Bundle(for: IOSFixtureToken.self).url(forResource: "ios-v2.3-default", withExtension: "store"))
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        let container = try openAppStore(at: url)
        SerialNotesMigration.runAtLaunch(on: container)
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        let byIP = Dictionary(uniqueKeysWithValues: rows.map { ($0.ipAddress, $0) })
        #expect(byIP["192.168.1.20"]?.serialNumber == "C02XYZ123")
        #expect(byIP["192.168.1.20"]?.notes == "Desk machine")
        #expect(byIP["192.168.1.30"]?.serialNumber == nil)
        #expect(byIP["192.168.1.30"]?.notes == "Serial: ")
        #expect(byIP["192.168.1.40"]?.serialNumber == "A1")
        #expect(byIP["192.168.1.40"]?.notes == "Serial: B2")
    }

    /// Reconstructions: `LocalDevice` as 2.2 (before `modelName`) and 2.2.3 (before the identity
    /// sources) declared it, the other entities absent. Written in-test, not by the shipped apps.
    @Test("Reconstructed older stores open with the app's schema", arguments: [false, true])
    func olderShapesOpen(withModelName: Bool) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")
        let id = UUID()
        do {
            let schema = withModelName ? Schema([IOSShape223.LocalDevice.self]) : Schema([IOSShape22.LocalDevice.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            if withModelName {
                let row = IOSShape223.LocalDevice(id: id, ipAddress: "10.0.0.5", macAddress: "")
                row.modelName = "iPhone17,1"
                row.notes = "Serial: F2LX"
                context.insert(row)
            } else {
                let row = IOSShape22.LocalDevice(id: id, ipAddress: "10.0.0.5", macAddress: "")
                row.notes = "Serial: F2LX"
                context.insert(row)
            }
            try context.save()
        }
        let before = try StoreDump(url)
        let container = try openAppStore(at: url)
        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<LocalDevice>()).first)
        #expect(row.id == id)
        #expect(row.modelName == (withModelName ? "iPhone17,1" : nil))
        #expect(row.serialNumber == nil)
        withExtendedLifetime(container) {}
        #expect(try StoreDump(url, onlyColumns: before.columns) == before)
    }
}

private enum IOSShape22 {
    @Model
    final class LocalDevice {
        @Attribute(.unique) var id: UUID
        var ipAddress: String
        var macAddress: String
        var hostname: String?
        var vendor: String?
        var deviceType: DeviceType
        var customName: String?
        var status: DeviceStatus
        var lastLatency: Double?
        var isGateway: Bool = false
        var supportsWakeOnLan: Bool = false
        var firstSeen: Date
        var lastSeen: Date
        var notes: String?
        var resolvedHostname: String?
        var manufacturer: String?
        var openPorts: [Int]?
        var discoveredServices: [String]?
        var networkProfileID: UUID?

        init(id: UUID, ipAddress: String, macAddress: String) {
            self.id = id
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            deviceType = .unknown
            status = .online
            firstSeen = Date()
            lastSeen = Date()
        }
    }
}

private enum IOSShape223 {
    @Model
    final class LocalDevice {
        @Attribute(.unique) var id: UUID
        var ipAddress: String
        var macAddress: String
        var hostname: String?
        var vendor: String?
        var deviceType: DeviceType
        var customName: String?
        var status: DeviceStatus
        var lastLatency: Double?
        var isGateway: Bool = false
        var supportsWakeOnLan: Bool = false
        var firstSeen: Date
        var lastSeen: Date
        var notes: String?
        var resolvedHostname: String?
        var manufacturer: String?
        var openPorts: [Int]?
        var discoveredServices: [String]?
        var networkProfileID: UUID?
        var modelName: String?

        init(id: UUID, ipAddress: String, macAddress: String) {
            self.id = id
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            deviceType = .unknown
            status = .online
            firstSeen = Date()
            lastSeen = Date()
        }
    }
}

private final class IOSFixtureToken {}
