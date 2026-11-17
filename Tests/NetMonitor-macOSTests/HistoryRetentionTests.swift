import Foundation
import NetMonitorCore
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// History retention on Mac covers measurements, stopped sessions and timeline events (#395).
/// Each test is synchronous on the main actor, so the shared retention key can't change mid-test.
@Suite("History retention (macOS)", .serialized)
@MainActor
struct HistoryRetentionTests {
    private let retentionKey = "netmonitor.data.historyRetention"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86400)
    }

    @Test func pruneRemovesOldStoppedSessionsAndKeepsRecentAndActiveOnes() throws {
        let (container, context) = try makeContext()
        _ = container
        let saved = UserDefaults.standard.object(forKey: retentionKey)
        UserDefaults.standard.set("7 days", forKey: retentionKey)
        defer { UserDefaults.standard.set(saved, forKey: retentionKey) }

        let oldStopped = SessionRecord(startedAt: daysAgo(10), stoppedAt: daysAgo(10), isActive: false)
        let oldActive = SessionRecord(startedAt: daysAgo(10), isActive: true)
        let recentStopped = SessionRecord(startedAt: daysAgo(1), stoppedAt: daysAgo(1), isActive: false)
        [oldStopped, oldActive, recentStopped].forEach { context.insert($0) }
        try context.save()

        MonitoringSession(modelContext: context).pruneOldMeasurements(eventService: NetworkEventService(), now: now)

        let remaining = try Set(context.fetch(FetchDescriptor<SessionRecord>()).map(\.id))
        #expect(remaining == [oldActive.id, recentStopped.id])
    }

    @Test func pruneRemovesOldTimelineEvents() throws {
        let (container, context) = try makeContext()
        _ = container
        let saved = UserDefaults.standard.object(forKey: retentionKey)
        UserDefaults.standard.set("1 day", forKey: retentionKey)
        defer { UserDefaults.standard.set(saved, forKey: retentionKey) }

        let events = NetworkEventService()
        let old = NetworkEvent(type: .deviceJoined, timestamp: daysAgo(2), title: "old")
        let recent = NetworkEvent(type: .deviceJoined, timestamp: daysAgo(0.5), title: "recent")
        events.log(old)
        events.log(recent)

        MonitoringSession(modelContext: context).pruneOldMeasurements(eventService: events, now: now)

        #expect(events.events.map(\.id) == [recent.id])
    }

    @Test func foreverKeepsSessionsAndEvents() throws {
        let (container, context) = try makeContext()
        _ = container
        let saved = UserDefaults.standard.object(forKey: retentionKey)
        UserDefaults.standard.set("Forever", forKey: retentionKey)
        defer { UserDefaults.standard.set(saved, forKey: retentionKey) }

        context.insert(SessionRecord(startedAt: daysAgo(400), stoppedAt: daysAgo(400), isActive: false))
        try context.save()
        let events = NetworkEventService()
        events.log(NetworkEvent(type: .deviceJoined, timestamp: daysAgo(400), title: "ancient"))

        MonitoringSession(modelContext: context).pruneOldMeasurements(eventService: events, now: now)

        #expect(try context.fetch(FetchDescriptor<SessionRecord>()).count == 1)
        #expect(events.events.count == 1)
    }
}
