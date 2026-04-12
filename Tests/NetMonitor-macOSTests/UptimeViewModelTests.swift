import Testing
import Foundation
import SwiftData
import NetMonitorCore
@testable import NetMonitor_macOS

// UptimeViewModel is part of the NetMonitor-macOS app target.
// Tests access it via @testable import NetMonitor_macOS.

@Suite(.serialized)
@MainActor
struct UptimeViewModelTests {

    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: ConnectivityRecord.self, configurations: config)
    }

    /// Insert a ConnectivityRecord into the given context relative to the current time.
    func insertRecord(
        in context: ModelContext,
        profileID: UUID,
        hoursAgo: Double,
        isOnline: Bool,
        isSample: Bool = false,
        latencyMs: Double? = nil
    ) {
        let record = ConnectivityRecord(
            profileID: profileID,
            timestamp: Date().addingTimeInterval(-hoursAgo * 3600),
            isOnline: isOnline,
            latencyMs: latencyMs,
            isSample: isSample
        )
        context.insert(record)
    }

    @Test("No records → uptimePct is nil")
    func noRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.uptimePct == nil)
        #expect(vm.outageCount == 0)
        #expect(vm.uptimeBar.isEmpty)
    }

    @Test("Always online (only samples, no transitions) → uptimePct is 100%")
    func alwaysOnline() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        insertRecord(in: context, profileID: profileID, hoursAgo: 12, isOnline: true, isSample: true, latencyMs: 5.0)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        // Only sample records exist — no transitions means no outages, so 100% uptime.
        #expect(vm.uptimePct == 100.0)
        #expect(vm.outageCount == 0)
    }

    @Test("One outage in the middle → uptime ~50%")
    func oneOutageMiddle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // Went offline 18h ago, came back online 6h ago → offline for ~12h of 24h window
        insertRecord(in: context, profileID: profileID, hoursAgo: 18, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        let pct = try #require(vm.uptimePct)
        #expect(pct > 45 && pct < 55, "Expected ~50%, got \(pct)")
        #expect(vm.outageCount == 1)
    }

    @Test("Multiple outages → correct count")
    func multipleOutages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // Three distinct offline→online cycles
        insertRecord(in: context, profileID: profileID, hoursAgo: 22, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 21, isOnline: true)
        insertRecord(in: context, profileID: profileID, hoursAgo: 14, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 13, isOnline: true)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 5, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 24)
        vm.load()

        #expect(vm.outageCount == 3)
    }

    @Test("Bar segments reflect online/offline periods")
    func barSegments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // Went offline 18h ago (6h into window), came back 6h ago (18h into window)
        // Window = 24h, 4 segments → each segment = 6h
        // Segment 0 (24–18h ago): online
        // Segment 1 (18–12h ago): offline
        // Segment 2 (12–6h ago): offline
        // Segment 3 (6–0h ago): online
        insertRecord(in: context, profileID: profileID, hoursAgo: 18, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.uptimeBar.count == 4)
        #expect(vm.uptimeBar[0] == true, "Segment 0 (24–18h ago) should be online")
        #expect(vm.uptimeBar[1] == false, "Segment 1 (18–12h ago) should be offline")
        #expect(vm.uptimeBar[2] == false, "Segment 2 (12–6h ago) should be offline")
        #expect(vm.uptimeBar[3] == true, "Segment 3 (6–0h ago) should be online")
    }

    @Test("Latest latency from most recent sample")
    func latestLatency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        insertRecord(in: context, profileID: profileID, hoursAgo: 10, isOnline: true, isSample: true, latencyMs: 20)
        insertRecord(in: context, profileID: profileID, hoursAgo: 5, isOnline: true, isSample: true, latencyMs: 8)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.latestLatencyMs == 8)
    }
}
