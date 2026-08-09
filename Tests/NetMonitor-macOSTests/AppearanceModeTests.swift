import Foundation
import NetMonitorCore
import SwiftData
import Testing
@testable import NetMonitor_macOS

struct AppearanceModeTests {

    /// Regression guard for GH-142: `@AppStorage("netmonitor.appearance.theme")`
    /// reads the raw string from UserDefaults. If the enum raw values, display
    /// names, or icon names are refactored without care, the picker will silently
    /// fall back to `.system` for existing users.
    @Test func rawValuesAreStable() {
        #expect(AppearanceMode.system.rawValue == "system")
        #expect(AppearanceMode.dark.rawValue == "dark")
        #expect(AppearanceMode.light.rawValue == "light")
    }

    @Test func rawValueRoundTripSucceedsForAllCases() {
        for mode in AppearanceMode.allCases {
            let reconstructed = AppearanceMode(rawValue: mode.rawValue)
            #expect(reconstructed == mode, "AppearanceMode.\(mode) did not round-trip")
        }
    }

    @Test func rawValueInitReturnsNilForGarbageInput() {
        #expect(AppearanceMode(rawValue: "") == nil)
        #expect(AppearanceMode(rawValue: "Light") == nil) // case-sensitive
        #expect(AppearanceMode(rawValue: "auto") == nil)
    }

    @Test func displayNamesAreDistinct() {
        let names = Set(AppearanceMode.allCases.map(\.displayName))
        #expect(names.count == AppearanceMode.allCases.count)
    }

    @Test func iconNamesAreDistinct() {
        let icons = Set(AppearanceMode.allCases.map(\.iconName))
        #expect(icons.count == AppearanceMode.allCases.count)
    }

    @Test("v2.2.0 macOS SchemaV1 store reopens through the migration plan")
    @MainActor
    func lastShippedStoreReopens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "netmonitor-mac-v220-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "v2.2.0.store")
        let schema = Schema(versionedSchema: SchemaV1.self)
        let fixtureID = UUID()

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NetMonitorMigrationPlan.self,
                configurations: [configuration]
            )
            container.mainContext.insert(NetworkTarget(
                id: fixtureID,
                name: "v2.2.0 fixture",
                host: "fixture.invalid",
                targetProtocol: .icmp
            ))
            try container.mainContext.save()
        }

        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: NetMonitorMigrationPlan.self,
            configurations: [configuration]
        )
        let targets = try reopened.mainContext.fetch(FetchDescriptor<NetworkTarget>())

        #expect(targets.map(\.id).contains(fixtureID))
    }
}
