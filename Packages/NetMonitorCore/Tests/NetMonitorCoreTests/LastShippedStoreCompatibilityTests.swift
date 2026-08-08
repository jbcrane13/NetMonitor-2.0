import Foundation
import SwiftData
import Testing
@testable import NetMonitorCore

@MainActor
struct LastShippedStoreCompatibilityTests {
    @Test("v2.2.0 iOS schema store reopens without data loss")
    func iOSStoreReopens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "netmonitor-v220-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "v2.2.0.store")
        let schema = Schema([
            PairedMac.self,
            LocalDevice.self,
            MonitoringTarget.self,
            ToolResult.self,
            SpeedTestResult.self
        ])
        let fixtureID = UUID()

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(ToolResult(
                id: fixtureID,
                toolType: .ping,
                target: "fixture.invalid",
                success: true,
                summary: "v2.2.0 fixture"
            ))
            try container.mainContext.save()
        }

        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let results = try reopened.mainContext.fetch(FetchDescriptor<ToolResult>())

        #expect(results.map(\.id).contains(fixtureID))
    }
}
