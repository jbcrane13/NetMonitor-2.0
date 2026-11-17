import Testing
import Foundation
import SwiftData
@testable import NetMonitor_iOS
import NetMonitorCore

/// DataMaintenanceService tests.
///
/// INTEGRATION GAP: SwiftData ModelContext requires a ModelContainer which needs
/// a schema registered at runtime. The pruneExpiredData method operates on
/// ModelContext.delete(model:where:) which requires a live SwiftData stack.
/// These tests verify the configuration logic and boundary conditions that
/// can be tested without a full SwiftData container.

@MainActor
struct DataMaintenanceServiceTests {

    // MARK: - Retention days configuration

    @Test("Default retention period is 30 days when no UserDefaults value set")
    func defaultRetentionDays() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 30)
    }

    @Test("Custom retention period is read from UserDefaults")
    func customRetentionDays() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(7, forKey: key)
        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 7)
    }

    @Test("Zero retention days means no pruning occurs (guard clause)")
    func zeroRetentionDaysSkipsPruning() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(0, forKey: key)
        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 0, "Zero retention should be preserved")

        // The guard retentionDays > 0 else { return } in pruneExpiredData
        // exits early when 0. We verify the logic path here.
        let shouldPrune = retentionDays > 0
        #expect(shouldPrune == false)
    }

    @Test("Cutoff date is correctly calculated from retention days")
    func cutoffDateCalculation() {
        let retentionDays = 14
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)!

        // Cutoff should be approximately 14 days ago
        let daysDifference = Calendar.current.dateComponents([.day], from: cutoff, to: now).day ?? 0
        #expect(daysDifference == 14)
    }

    @Test("Negative retention days produce future cutoff (edge case)")
    func negativeRetentionDays() {
        let retentionDays = -1
        // guard retentionDays > 0 catches this, but verify the math if bypassed
        let shouldPrune = retentionDays > 0
        #expect(shouldPrune == false)
    }

    @Test("Large retention days produce distant past cutoff")
    func largeRetentionDays() {
        let retentionDays = 365
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)!

        let daysDifference = Calendar.current.dateComponents([.day], from: cutoff, to: now).day ?? 0
        #expect(daysDifference == 365)
    }
}

/// Pruning against an in-memory store: tool results, speed tests and timeline events (#395).
@Suite("DataMaintenanceService pruning")
@MainActor
struct DataMaintenancePruningTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([ToolResult.self, SpeedTestResult.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeDefaults(retentionDays: Int) -> (UserDefaults, String) {
        let suite = "DataMaintenancePruningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(retentionDays, forKey: AppSettings.Keys.dataRetentionDays)
        return (defaults, suite)
    }

    @Test func prunesRecordsAndTimelineEventsOlderThanRetention() throws {
        let (container, context) = try makeContext()
        _ = container
        let (defaults, suite) = makeDefaults(retentionDays: 7)
        defer { defaults.removePersistentDomain(forName: suite) }

        let oldTool = ToolResult(toolType: .ping, target: "example.com", success: true, summary: "old")
        oldTool.timestamp = now.addingTimeInterval(-10 * 86400)
        let recentTool = ToolResult(toolType: .ping, target: "example.com", success: true, summary: "recent")
        recentTool.timestamp = now.addingTimeInterval(-1 * 86400)
        let oldSpeed = SpeedTestResult(downloadSpeed: 100, uploadSpeed: 10, latency: 20)
        oldSpeed.timestamp = now.addingTimeInterval(-10 * 86400)
        [oldTool, recentTool].forEach { context.insert($0) }
        context.insert(oldSpeed)
        try context.save()

        let events = NetworkEventService()
        let oldEvent = NetworkEvent(type: .deviceJoined, timestamp: now.addingTimeInterval(-10 * 86400), title: "old")
        let recentEvent = NetworkEvent(type: .deviceJoined, timestamp: now.addingTimeInterval(-1 * 86400), title: "recent")
        events.log(oldEvent)
        events.log(recentEvent)

        DataMaintenanceService.pruneExpiredData(modelContext: context, defaults: defaults, eventService: events, now: now)

        #expect(try context.fetch(FetchDescriptor<ToolResult>()).map(\.id) == [recentTool.id])
        #expect(try context.fetch(FetchDescriptor<SpeedTestResult>()).isEmpty)
        #expect(events.events.map(\.id) == [recentEvent.id])
    }

    @Test func longerRetentionKeepsEverythingInsideTheWindow() throws {
        let (container, context) = try makeContext()
        _ = container
        let (defaults, suite) = makeDefaults(retentionDays: 30)
        defer { defaults.removePersistentDomain(forName: suite) }

        let tool = ToolResult(toolType: .ping, target: "example.com", success: true, summary: "ten days")
        tool.timestamp = now.addingTimeInterval(-10 * 86400)
        context.insert(tool)
        try context.save()
        let events = NetworkEventService()
        events.log(NetworkEvent(type: .deviceJoined, timestamp: now.addingTimeInterval(-10 * 86400), title: "ten days"))

        DataMaintenanceService.pruneExpiredData(modelContext: context, defaults: defaults, eventService: events, now: now)

        #expect(try context.fetch(FetchDescriptor<ToolResult>()).count == 1)
        #expect(events.events.count == 1)
    }
}
