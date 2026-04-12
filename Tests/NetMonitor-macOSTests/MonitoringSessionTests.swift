import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite(.serialized)
@MainActor
struct MonitoringSessionTests {

    @Test func startMonitoringWithNoEnabledTargetsSetsErrorAndDoesNotStart() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Disabled Target",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            isEnabled: false
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()

        #expect(session.isMonitoring == false)
        #expect(session.errorMessage?.contains("No enabled targets found") == true)
        #expect(session.startTime == nil)
    }

    @Test func stopMonitoringWhenAlreadyStoppedKeepsStateStable() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let session = MonitoringSession(modelContext: context)
        session.stopMonitoring()

        #expect(session.isMonitoring == false)
        #expect(session.startTime == nil)
        #expect(session.latestResults.isEmpty)
        #expect(session.averageLatencyString == "—")
        #expect(session.onlineTargetCount == 0)
        #expect(session.offlineTargetCount == 0)
    }

    @Test func pruneOldMeasurementsRemovesEntriesOutsideRetentionWindow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("7 days", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let oldMeasurement = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-9 * 24 * 60 * 60),
            latency: 10,
            isReachable: true
        )
        let recentMeasurement = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-2 * 24 * 60 * 60),
            latency: 20,
            isReachable: true
        )

        context.insert(oldMeasurement)
        context.insert(recentMeasurement)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == recentMeasurement.id)
    }

    @Test func pruneOldMeasurementsKeepsAllDataWhenRetentionIsForever() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("Forever", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            latency: 30,
            isReachable: true
        ))
        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-1 * 24 * 60 * 60),
            latency: 15,
            isReachable: false
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 2)
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            SessionRecord.self
        ])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}
