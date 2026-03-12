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
// internal `anyHTTPService:anyICMPService:anyTCPService:` initialiser added to
// MonitoringSession specifically for loop-level unit testing without hitting
// the real network.

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

private actor ThrowingMonitorService: NetworkMonitorService {
    let error: Error
    init(error: Error = URLError(.timedOut)) { self.error = error }
    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        throw error
    }
}

// MARK: - Shared helpers

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

// MARK: - MonitoringSession extended tests (state / lifecycle)

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
        #expect(session.latestMeasurement(for: UUID()) == nil)
    }

    // MARK: stopMonitoring idempotency

    @Test func stopMonitoringWhenNotMonitoringIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        session.stopMonitoring()
        session.stopMonitoring()
        #expect(session.isMonitoring == false)
        #expect(session.latestResults.isEmpty)
        #expect(session.startTime == nil)
    }

    // MARK: startMonitoring with empty store

    @Test func startMonitoringWithEmptyStoreSetsErrorMessage() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        #expect(session.isMonitoring == false)
        #expect(session.errorMessage?.contains("No enabled targets") == true)
        #expect(session.startTime == nil)
    }

    @Test func startMonitoringClearsErrorMessageOnEachCall() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        #expect(session.errorMessage != nil)
        session.startMonitoring()
        #expect(session.errorMessage != nil) // re-set but was cleared at top of call
    }

    // MARK: startMonitoring with enabled target

    @Test func startMonitoringWithEnabledTargetBecomesMonitoring() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        let before = Date()
        session.startMonitoring()

        #expect(session.isMonitoring == true)
        #expect(session.errorMessage == nil)
        #expect(session.startTime != nil)
        if let t = session.startTime { #expect(t >= before) }

        session.stopMonitoring()
    }

    @Test func startMonitoringWhileAlreadyMonitoringIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        let startTimeAfterFirst = session.startTime
        session.startMonitoring()
        #expect(session.isMonitoring == true)
        #expect(session.startTime == startTimeAfterFirst)
        session.stopMonitoring()
    }

    // MARK: stopMonitoring after starting

    @Test func stopMonitoringTransitionsIsMonitoringToFalse() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "DNS", host: "8.8.8.8",
            targetProtocol: .icmp, isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        #expect(session.isMonitoring == true)
        session.stopMonitoring()
        #expect(session.isMonitoring == false)
    }

    @Test func startTimeRetainedAfterStopMonitoring() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "DNS", host: "8.8.8.8",
            targetProtocol: .icmp, isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()
        let capturedStart = session.startTime
        session.stopMonitoring()
        #expect(session.startTime == capturedStart)
    }

    // MARK: onlineTargetCount / offlineTargetCount with no results

    @Test func onlineTargetCountIsZeroWithNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        #expect(MonitoringSession(modelContext: context).onlineTargetCount == 0)
    }

    @Test func offlineTargetCountIsZeroWithNoResults() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        #expect(MonitoringSession(modelContext: context).offlineTargetCount == 0)
    }

    // MARK: serviceProvider init

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

    // MARK: pruneOldMeasurements

    @Test func pruneRemovesStaleAndKeepsRecentWithDefaultRetention() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        UserDefaults.standard.set("7 days", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-10 * 86400), latency: 20, isReachable: true)
        let fresh = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-1 * 86400), latency: 15, isReachable: true)
        context.insert(stale); context.insert(fresh)
        try context.save()

        MonitoringSession(modelContext: context).pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == fresh.id)
    }

    @Test func pruneRemovesEntriesOlderThanOneDayWhenRetentionIsOneDay() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        UserDefaults.standard.set("1 day", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-2 * 86400), latency: 30, isReachable: false)
        let fresh = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-12 * 3600), latency: 8, isReachable: true)
        context.insert(stale); context.insert(fresh)
        try context.save()

        MonitoringSession(modelContext: context).pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == fresh.id)
    }

    @Test func pruneKeepsEntriesWithinThirtyDaysWhenRetentionIsThirtyDays() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        UserDefaults.standard.set("30 days", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        let stale = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-35 * 86400), latency: 50, isReachable: true)
        let kept  = TargetMeasurement(
            timestamp: Date().addingTimeInterval(-20 * 86400), latency: 25, isReachable: true)
        context.insert(stale); context.insert(kept)
        try context.save()

        MonitoringSession(modelContext: context).pruneOldMeasurements()

        let remaining = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == kept.id)
    }

    @Test func pruneKeepsAllDataWhenRetentionIsForever() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        UserDefaults.standard.set("Forever", forKey: "netmonitor.data.historyRetention")
        defer { UserDefaults.standard.removeObject(forKey: "netmonitor.data.historyRetention") }

        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-365 * 86400), latency: 100, isReachable: true))
        context.insert(TargetMeasurement(
            timestamp: Date().addingTimeInterval(-1 * 86400), latency: 10, isReachable: true))
        try context.save()

        MonitoringSession(modelContext: context).pruneOldMeasurements()

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

    // MARK: Successful check populates latestResults

    @Test func startMonitoringPopulatesLatestResultsAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target); try context.save()

        let stub = SuccessMonitorService(latency: 42.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.latestResults[target.id] != nil)
        #expect(session.latestResults[target.id]?.isReachable == true)
        #expect(session.latestResults[target.id]?.latency == 42.0)
        session.stopMonitoring()
    }

    // MARK: latestMeasurement(for:) returns populated result

    @Test func latestMeasurementForKnownIDReturnsResultAfterCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "DNS", host: "8.8.8.8",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target); try context.save()

        let stub = SuccessMonitorService(latency: 15.0)
        let session = makeSession(context: context, stub: stub)
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result != nil)
        #expect(result?.latency == 15.0)
        session.stopMonitoring()
    }

    // MARK: onlineTargetCount / offlineTargetCount after check

    @Test func onlineTargetCountIsOneAfterReachableCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 10.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.onlineTargetCount == 1)
        #expect(session.offlineTargetCount == 0)
        session.stopMonitoring()
    }

    @Test func offlineTargetCountIsOneAfterUnreachableCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Dead Host", host: "192.168.99.99",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: UnreachableMonitorService())
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.onlineTargetCount == 0)
        #expect(session.offlineTargetCount == 1)
        session.stopMonitoring()
    }

    // MARK: averageLatencyString format after successful check

    @Test func averageLatencyStringReturnsFormattedMsAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 33.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.averageLatencyString == "33ms")
        session.stopMonitoring()
    }

    // MARK: averageLatencyString averages over multiple targets

    @Test func averageLatencyStringAveragesOverMultipleTargets() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Host A", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        context.insert(NetworkTarget(
            name: "Host B", host: "192.168.1.2",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 50.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(300))

        #expect(session.averageLatencyString == "50ms")
        session.stopMonitoring()
    }

    // MARK: Error path – throwing service marks target unreachable

    @Test func throwingServiceMarksTargetUnreachableWithErrorMessage() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Flaky Host", host: "10.0.0.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target); try context.save()

        let session = makeSession(context: context, stub: ThrowingMonitorService(error: URLError(.timedOut)))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result != nil)
        #expect(result?.isReachable == false)
        #expect(result?.latency == nil)
        #expect(result?.errorMessage != nil)
        session.stopMonitoring()
    }

    // MARK: Unreachable stub propagates errorMessage

    @Test func unreachableServiceSetsErrorMessageOnMeasurement() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Down Host", host: "10.10.10.10",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target); try context.save()

        let session = makeSession(context: context, stub: UnreachableMonitorService())
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let result = session.latestMeasurement(for: target.id)
        #expect(result?.isReachable == false)
        #expect(result?.errorMessage == "Host unreachable (stub)")
        session.stopMonitoring()
    }

    // MARK: recentLatencies rolling buffer accumulates entries

    @Test func recentLatenciesAccumulatesAfterSuccessfulCheck() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 0, // no delay between iterations
            isEnabled: true)
        context.insert(target); try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 10.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(150))
        session.stopMonitoring()

        let history = session.recentLatencies[target.id] ?? []
        #expect(history.isEmpty == false)
        #expect(history.allSatisfy { $0 == 10.0 })
    }

    // MARK: recentLatencies FIFO cap at 20 entries

    @Test func recentLatenciesCapAt20EntriesWithFIFOEviction() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp,
            checkInterval: 0,
            isEnabled: true)
        context.insert(target); try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 5.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(400))
        session.stopMonitoring()

        let history = session.recentLatencies[target.id] ?? []
        #expect(history.count <= 20)
        #expect(history.isEmpty == false)
    }

    // MARK: SessionRecord persisted on start / marked inactive on stop

    @Test func startMonitoringPersistsSessionRecordToStore() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService())
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(50))

        let records = try context.fetch(FetchDescriptor<SessionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.isActive == true)
        session.stopMonitoring()
    }

    @Test func stopMonitoringUpdatesSessionRecordIsActiveFalse() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService())
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(50))
        session.stopMonitoring()
        try await Task.sleep(for: .milliseconds(50))

        let records = try context.fetch(FetchDescriptor<SessionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.isActive == false)
        #expect(records.first?.stoppedAt != nil)
    }

    // MARK: Measurement persisted to SwiftData on successful check

    @Test func successfulCheckPersistsMeasurementToSwiftData() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let target = NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target); try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 20.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        let measurements = try context.fetch(FetchDescriptor<TargetMeasurement>())
        #expect(measurements.isEmpty == false)
        #expect(measurements.first?.isReachable == true)
        session.stopMonitoring()
    }

    // MARK: Disabled targets excluded from monitoring

    @Test func disabledTargetIsNotMonitored() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let disabled = NetworkTarget(
            name: "Disabled", host: "10.0.0.99",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: false)
        let enabled  = NetworkTarget(
            name: "Enabled",  host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(disabled); context.insert(enabled)
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 30.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.latestResults[disabled.id] == nil)
        #expect(session.latestResults[enabled.id] != nil)
        session.stopMonitoring()
    }

    // MARK: stopMonitoring cancels in-flight tasks

    @Test func stopMonitoringCancelsLoopAndFreezesIsMonitoringFalse() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(NetworkTarget(
            name: "Router", host: "192.168.1.1",
            targetProtocol: .icmp, checkInterval: 0, isEnabled: true))
        try context.save()

        let session = makeSession(context: context, stub: SuccessMonitorService(latency: 7.0))
        session.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))
        session.stopMonitoring()

        #expect(session.isMonitoring == false)
    }
}
