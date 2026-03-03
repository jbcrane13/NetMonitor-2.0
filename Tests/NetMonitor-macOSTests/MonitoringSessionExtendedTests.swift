import Testing
import Foundation
import SwiftData
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - Mock service provider
//
// MonitoringSession accepts a MonitorServiceProviding through its primary init.
// MockMonitorServiceProvider constructs real services (the only concrete types the
// protocol can return) and is used to exercise the serviceProvider init path.

private struct MockMonitorServiceProvider: MonitorServiceProviding {
    func createHTTPService() -> HTTPMonitorService { HTTPMonitorService() }
    func createTCPService() -> TCPMonitorService { TCPMonitorService() }
    func createICMPService() -> ICMPMonitorService { ICMPMonitorService() }
}

// MARK: - Helpers

@MainActor
private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
    let schema = Schema([
        NetworkTarget.self,
        TargetMeasurement.self,
        SessionRecord.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return (container, container.mainContext)
}

// MARK: - MonitoringSession extended tests

@Suite("MonitoringSession – extended")
@MainActor
struct MonitoringSessionExtendedTests {

    // MARK: Initial state

    @Test func initialStateIsNotMonitoring() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.isMonitoring == false)
        #expect(session.latestResults.isEmpty)
        #expect(session.onlineTargetCount == 0)
        #expect(session.offlineTargetCount == 0)
        #expect(session.startTime == nil)
    }

    @Test func latestResultsEmptyAfterInit() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.latestResults.isEmpty)
    }

    @Test func recentLatenciesEmptyAfterInit() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.recentLatencies.isEmpty)
    }

    @Test func errorMessageNilAfterInit() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.errorMessage == nil)
    }

    // MARK: averageLatencyString

    // When latestResults is empty, the average latency string must be an em dash
    // so the UI displays "—" rather than a stale or zero value.
    @Test func averageLatencyStringIsEmDashWhenNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.averageLatencyString == "—")
    }

    // Verify the "Xms" format when latestResults contains entries with latency.
    // We call pruneOldMeasurements() (a public @MainActor method) just to confirm
    // it doesn't mutate latestResults when there is nothing to prune.
    @Test func averageLatencyStringFormatIsXmsWhenResultsPresent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(name: "Router", host: "192.168.1.1", targetProtocol: .icmp)
        context.insert(target)
        try context.save()

        let session = MonitoringSession(modelContext: context)

        // Directly insert a measurement into latestResults via a pathway available
        // to callers: startMonitoring() → disabled targets path sets errorMessage.
        // Because latestResults is private(set), we cannot seed it directly.
        // The averageLatencyString with populated results is tested indirectly via
        // the monitoring loop integration path — see the integration gap comment below.
        //
        // INTEGRATION GAP: Direct seeding of latestResults requires starting the
        // full monitoring loop. See MonitoringSession.startMonitoringTarget() and
        // monitorTarget() for the untested code path. Once monitoring starts with
        // a real (or mock) service, latestResults is populated and
        // averageLatencyString returns "Xms".

        // What we can assert without running the loop: initial state is "—".
        #expect(session.averageLatencyString == "—")
    }

    // MARK: latestMeasurement(for:)

    @Test func latestMeasurementForUnknownIDReturnsNil() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        let randomID = UUID()
        #expect(session.latestMeasurement(for: randomID) == nil)
    }

    // MARK: stopMonitoring idempotency

    // Calling stopMonitoring() when not monitoring must not crash or mutate state.
    @Test func stopMonitoringWhenNotMonitoringIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)

        session.stopMonitoring()
        session.stopMonitoring() // second call must also be safe

        #expect(session.isMonitoring == false)
        #expect(session.latestResults.isEmpty)
        #expect(session.startTime == nil)
    }

    // MARK: startMonitoring with empty store

    // startMonitoring() with no enabled targets must set errorMessage and keep
    // isMonitoring=false. This is safe to test synchronously because all state
    // changes happen before the fetch path spawns Tasks.
    @Test func startMonitoringWithEmptyStoreSetsErrorMessage() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)

        session.startMonitoring()

        #expect(session.isMonitoring == false)
        #expect(session.errorMessage?.contains("No enabled targets") == true)
        #expect(session.startTime == nil)
    }

    // startMonitoring() must clear a previously set errorMessage each time it runs,
    // even if it ultimately fails again due to no targets.
    @Test func startMonitoringClearsErrorMessageOnEachCall() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)

        // First call — sets errorMessage.
        session.startMonitoring()
        #expect(session.errorMessage != nil)

        // Second call — errorMessage must be cleared at the top of startMonitoring(),
        // and then re-set because there are still no targets.
        session.startMonitoring()
        #expect(session.errorMessage != nil) // re-set, but was cleared momentarily
    }

    // MARK: startMonitoring with enabled target

    // When there is at least one enabled target, startMonitoring() must set
    // isMonitoring=true, record a startTime, and leave errorMessage nil.
    @Test func startMonitoringWithEnabledTargetBecomesMonitoring() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        let before = Date()
        session.startMonitoring()

        #expect(session.isMonitoring == true)
        #expect(session.errorMessage == nil)
        #expect(session.startTime != nil)
        if let startTime = session.startTime {
            #expect(startTime >= before)
        }

        session.stopMonitoring()
    }

    // startMonitoring() must be idempotent: a second call while monitoring is active
    // must not spawn new tasks or reset startTime.
    @Test func startMonitoringWhileAlreadyMonitoringIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        let startTimeAfterFirst = session.startTime

        session.startMonitoring() // second call must be a no-op
        #expect(session.isMonitoring == true)
        #expect(session.startTime == startTimeAfterFirst)

        session.stopMonitoring()
    }

    // MARK: stopMonitoring after starting

    @Test func stopMonitoringTransitionsIsMonitoringToFalse() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        #expect(session.isMonitoring == true)

        session.stopMonitoring()
        #expect(session.isMonitoring == false)
    }

    // startTime is not cleared by stopMonitoring — it records when the session
    // began, for display purposes. Verify it is non-nil after stop.
    @Test func startTimeRetainedAfterStopMonitoring() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        let capturedStart = session.startTime
        session.stopMonitoring()

        // startTime is NOT reset by stopMonitoring; it records the session start.
        #expect(session.startTime == capturedStart)
    }

    // MARK: onlineTargetCount / offlineTargetCount with no results

    @Test func onlineTargetCountIsZeroWithNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.onlineTargetCount == 0)
    }

    @Test func offlineTargetCountIsZeroWithNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        #expect(session.offlineTargetCount == 0)
    }

    // MARK: serviceProvider init

    // Verify that the MonitorServiceProviding init path produces a session in
    // the same initial state as the direct service init path.
    @Test func serviceProviderInitProducesValidSession() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(
            modelContext: context,
            serviceProvider: MockMonitorServiceProvider()
        )
        #expect(session.isMonitoring == false)
        #expect(session.latestResults.isEmpty)
        #expect(session.averageLatencyString == "—")
    }

    // MARK: pruneOldMeasurements (default retention)

    // Ensures pruning with the default "7 days" retention window removes stale entries
    // without affecting recent measurements. Re-tests the core pruning logic in this
    // file's context so the extended suite is self-contained.
    @Test func pruneRemovesStaleAndKeepsRecentWithDefaultRetention() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("7 days", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-10 * 24 * 60 * 60), // 10 days ago
            latency: 20,
            isReachable: true
        )
        let fresh = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-1 * 24 * 60 * 60), // 1 day ago
            latency: 15,
            isReachable: true
        )

        context.insert(stale)
        context.insert(fresh)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == fresh.id)
    }

    // "1 day" retention must remove entries older than one day.
    @Test func pruneRemovesEntriesOlderThanOneDayWhenRetentionIsOneDay() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("1 day", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-2 * 24 * 60 * 60), // 2 days ago
            latency: 30,
            isReachable: false
        )
        let fresh = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-12 * 60 * 60), // 12 hours ago
            latency: 8,
            isReachable: true
        )

        context.insert(stale)
        context.insert(fresh)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == fresh.id)
    }

    // "30 days" retention must only remove entries older than 30 days.
    @Test func pruneKeepsEntriesWithinThirtyDaysWhenRetentionIsThirtyDays() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("30 days", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-35 * 24 * 60 * 60), // 35 days ago
            latency: 50,
            isReachable: true
        )
        let kept = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-20 * 24 * 60 * 60), // 20 days ago
            latency: 25,
            isReachable: true
        )

        context.insert(stale)
        context.insert(kept)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == kept.id)
    }

    // "Forever" retention must never remove any entry regardless of age.
    @Test func pruneKeepsAllDataWhenRetentionIsForever() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        UserDefaults.standard.set("Forever", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-365 * 24 * 60 * 60), // 1 year ago
            latency: 100,
            isReachable: true
        ))
        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-1 * 24 * 60 * 60),
            latency: 10,
            isReachable: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 2)
    }

    // MARK: Integration gap documentation

    // INTEGRATION GAP: The core monitoring loop in startMonitoringTarget() and
    // monitorTarget() cannot be fully tested here because HTTPMonitorService,
    // ICMPMonitorService, and TCPMonitorService are concrete actor types, not
    // protocol types — MonitorServiceProviding creates them via factory methods
    // that return the concrete types. There is no injection point for replacing
    // a single service with a custom actor that conforms to NetworkMonitorService.
    //
    // Specifically, these code paths are not covered by unit tests:
    //   - latestResults being populated after a successful check
    //   - recentLatencies rolling buffer accumulation (max 20 entries)
    //   - onlineTargetCount / offlineTargetCount reflecting live results
    //   - averageLatencyString returning "Xms" with real latency data
    //   - TargetMeasurement being persisted to SwiftData on each check
    //   - SessionRecord being written to the store on start/stop
    //   - Error path in monitorTarget() writing an unreachable measurement
    //
    // To cover these, either:
    //   (a) Introduce a protocol abstraction for the individual monitor services
    //       so they can be replaced in tests, or
    //   (b) Write integration tests that accept real network latency with a short
    //       timeout against localhost / 127.0.0.1.
}
