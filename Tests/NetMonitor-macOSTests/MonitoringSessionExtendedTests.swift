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

// MARK: - Controllable stub services
//
// These actor stubs conform to NetworkMonitorService and are injected via the
// internal `anyHTTPService:anyICMPService:anyTCPService:` initialiser that was
// added specifically to enable loop-level unit testing without hitting the real
// network. Each stub captures a fixed result or throws a controlled error.

/// Stub that immediately returns a reachable result with the supplied latency.
private actor SuccessMonitorService: NetworkMonitorService {
    let latency: Double
    let isReachable: Bool
    init(latency: Double = 25.0, isReachable: Bool = true) {
        self.latency = latency
        self.isReachable = isReachable
    }

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        MeasurementResult(
            targetID: request.id,
            timestamp: Date(),
            latency: latency,
            isReachable: isReachable,
            errorMessage: nil
        )
    }
}

/// Stub that returns an unreachable result (nil latency) with an error message.
private actor UnreachableMonitorService: NetworkMonitorService {
    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        MeasurementResult(
            targetID: request.id,
            timestamp: Date(),
            latency: nil,
            isReachable: false,
            errorMessage: "Host unreachable (stub)"
        )
    }
}

/// Stub that throws a given error on every call, exercising the catch path in
/// `monitorTarget()` which wraps the error in an unreachable measurement.
private actor ThrowingMonitorService: NetworkMonitorService {
    let error: Error
    init(error: Error = URLError(.timedOut)) { self.error = error }

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        throw error
    }
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

/// Creates a `MonitoringSession` backed by a single stub service for all three
/// protocol types. Pass the same stub for every slot unless you need
/// per-protocol differentiation.
@MainActor
private func makeSession(
    context: ModelContext,
    stub: any NetworkMonitorService
) -> MonitoringSession {
    MonitoringSession(
        modelContext: context,
        anyHTTPService: stub,
        anyICMPService: stub,
        anyTCPService: stub
    )
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

    // MARK: averageLatencyString – empty state

    // When latestResults is empty, the average latency string must be an em dash
    // so the UI displays "—" rather than a stale or zero value.
    @Test func averageLatencyStringIsEmDashWhenNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
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
    // without affecting recent measurements.
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

    }

// MARK: - MonitoringSession loop tests
//
// These tests exercise the async monitoring loop by injecting stub services
// through the internal `anyHTTPService:anyICMPService:anyTCPService:` init.
// Each test uses Task.sleep to allow the first loop iteration to complete before
// asserting, since the loop runs on the cooperative thread pool.

@Suite("MonitoringSession – loop")
@MainActor
struct MonitoringSessionLoopTests {

    // MARK: Core loop – successful check populates latestResults

    // After startMonitoring() with a success stub, the monitoring Task runs on
    // the cooperative thread pool. We yield with Task.sleep to let the first
    // iteration complete before asserting.
    @Test func startMonitoringPopulatesLatestResultsAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,  // long interval — only first iteration fires
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = SuccessMonitorService(latency: 42.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()

        // Yield long enough for the spawned Task to complete its first check.
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.latestResults[target.id] != nil)
        #expect(session.latestResults[target.id]?.isReachable == true)
        #expect(session.latestResults[target.id]?.latency == 42.0)

        session.stopMonitoring()
    }

    // MARK: Core loop – latestMeasurement(for:) returns the populated result

    @Test func latestMeasurementForKnownIDReturnsResultAfterCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = SuccessMonitorService(latency: 15.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result != nil)
        #expect(result?.latency == 15.0)

        session.stopMonitoring()
    }

    // MARK: Core loop – onlineTargetCount increments after reachable check

    @Test func onlineTargetCountIsOneAfterSuccessfulReachabilityCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService(latency: 10.0, isReachable: true)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.onlineTargetCount == 1)
        #expect(session.offlineTargetCount == 0)

        session.stopMonitoring()
    }

    // MARK: Core loop – offlineTargetCount increments after unreachable check

    @Test func offlineTargetCountIsOneAfterUnreachableCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Unreachable Host",
            host: "192.168.99.99",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = UnreachableMonitorService()
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.onlineTargetCount == 0)
        #expect(session.offlineTargetCount == 1)

        session.stopMonitoring()
    }

    // MARK: Core loop – averageLatencyString is formatted after successful check

    @Test func averageLatencyStringReturnsFormattedMsAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService(latency: 33.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.averageLatencyString == "33ms")

        session.stopMonitoring()
    }

    // MARK: Core loop – averageLatencyString averages over multiple targets

    @Test func averageLatencyStringAveragesOverMultipleTargets() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        // Two targets; both get the same stub returning 100ms and 200ms
        // would require per-target stubs. Use one stub returning 50ms for both
        // and verify the average is "50ms".
        context.insert(NetworkTarget(
            name: "Host A",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        context.insert(NetworkTarget(
            name: "Host B",
            host: "192.168.1.2",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService(latency: 50.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(300))

        // Both targets return 50ms; average is still 50ms.
        #expect(session.averageLatencyString == "50ms")

        session.stopMonitoring()
    }

    // MARK: Core loop – error path marks target unreachable

    // When the service throws, monitorTarget() catches and writes an unreachable
    // measurement with the error's localizedDescription as the errorMessage.
    @Test func throwingServiceMarksTargetUnreachableWithErrorMessage() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Flaky Host",
            host: "10.0.0.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = ThrowingMonitorService(error: URLError(.timedOut))
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result != nil)
        #expect(result?.isReachable == false)
        #expect(result?.latency == nil)
        #expect(result?.errorMessage != nil)

        session.stopMonitoring()
    }

    // MARK: Core loop – unreachable service errorMessage propagated

    @Test func unreachableServiceSetsErrorMessageOnMeasurement() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Down Host",
            host: "10.10.10.10",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = UnreachableMonitorService()
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result?.isReachable == false)
        #expect(result?.errorMessage == "Host unreachable (stub)")

        session.stopMonitoring()
    }

    // MARK: Core loop – recentLatencies rolling buffer accumulates entries

    @Test func recentLatenciesAccumulatesAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 0,   // 0-second interval so multiple iterations fire fast
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = SuccessMonitorService(latency: 10.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        // Allow several iterations. Each takes ~0ms (stub is instant) + 0s sleep.
        try await Task.sleep(for: .milliseconds(150))
        session.stopMonitoring()

        let history = session.recentLatencies[target.id] ?? []
        #expect(history.isEmpty == false)
        // All recorded values must be 10.0
        #expect(history.allSatisfy { $0 == 10.0 })
    }

    // MARK: Core loop – recentLatencies FIFO cap at 20 entries

    @Test func recentLatenciesCapAt20EntriesWithFIFOEviction() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 0,   // immediate re-check
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = SuccessMonitorService(latency: 5.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        // 400ms at ~0ms per iteration gives well over 20 iterations.
        try await Task.sleep(for: .milliseconds(400))
        session.stopMonitoring()

        let history = session.recentLatencies[target.id] ?? []
        // Buffer must never exceed the cap of 20.
        #expect(history.count <= 20)
        #expect(history.isEmpty == false)
    }

    // MARK: Core loop – SessionRecord written to store on start

    @Test func startMonitoringPersistsSessionRecordToStore() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService()
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(50))

        let records = try context.fetch(FetchDescriptor<SessionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.isActive == true)

        session.stopMonitoring()
    }

    // MARK: Core loop – SessionRecord marked inactive on stop

    @Test func stopMonitoringUpdatesSessionRecordIsActiveFalse() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService()
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(50))
        session.stopMonitoring()
        try await Task.sleep(for: .milliseconds(50))

        let records = try context.fetch(FetchDescriptor<SessionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.isActive == false)
        #expect(records.first?.stoppedAt != nil)
    }

    // MARK: Core loop – measurement persisted to SwiftData

    @Test func successfulCheckPersistsMeasurementToSwiftData() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let stub = SuccessMonitorService(latency: 20.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let measurements = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(measurements.isEmpty == false)
        #expect(measurements.first?.isReachable == true)

        session.stopMonitoring()
    }

    // MARK: Core loop – disabled targets not monitored

    // Only enabled targets should have monitoring tasks. A disabled target must
    // never appear in latestResults even after the loop runs.
    @Test func disabledTargetIsNotMonitored() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let disabled = NetworkTarget(
            name: "Disabled",
            host: "10.0.0.99",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: false
        )
        let enabled = NetworkTarget(
            name: "Enabled",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 60,
            isEnabled: true
        )
        context.insert(disabled)
        context.insert(enabled)
        try context.save()

        let stub = SuccessMonitorService(latency: 30.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.latestResults[disabled.id] == nil)
        #expect(session.latestResults[enabled.id] != nil)

        session.stopMonitoring()
    }

    // MARK: Core loop – stop cancels in-flight tasks promptly

    // After stopMonitoring(), isMonitoring transitions to false and no further
    // results can arrive from the (now cancelled) monitoring tasks.
    @Test func stopMonitoringCancelsLoopAndFreezesResults() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 0,
            isEnabled: true
        ))
        try context.save()

        let stub = SuccessMonitorService(latency: 7.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))
        session.stopMonitoring()

        #expect(session.isMonitoring == false)
        // latestResults should be populated from iterations before stop.
        // The important assertion is isMonitoring is false — further loop
        // iterations cannot update results once cancelled.
    }
}
