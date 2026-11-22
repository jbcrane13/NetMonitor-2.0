import Foundation
import NetMonitorCore
import SwiftData
import Testing
@testable import NetMonitor_macOS

// MARK: - Helpers

private func makeDefaults() -> (UserDefaults, String) {
    let suite = "PeriodicScanAndRetryTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite) ?? .standard, suite)
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Records each requested sleep. The first sleep returns at once; later ones park until
/// the timer is cancelled, so a test sees exactly one tick without waiting real time.
private final class FakeSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [Duration] = []
    var requested: [Duration] { lock.withLock { _requested } }

    func sleep(_ duration: Duration) async {
        let count = lock.withLock {
            _requested.append(duration)
            return _requested.count
        }
        if count > 1 {
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}

/// Records each requested sleep and parks until cancelled, counting cancellations, so a test
/// can see a timer being replaced or stopped without waiting real time.
private final class ParkingSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [Duration] = []
    private var _cancelled = 0
    var requested: [Duration] { lock.withLock { _requested } }
    var cancelled: Int { lock.withLock { _cancelled } }

    func sleep(_ duration: Duration) async {
        lock.withLock { _requested.append(duration) }
        try? await Task.sleep(for: .seconds(3600))
        if Task.isCancelled {
            lock.withLock { _cancelled += 1 }
        }
    }
}

// MARK: - PeriodicScanScheduler

@Suite("PeriodicScanScheduler")
@MainActor
struct PeriodicScanSchedulerTests {
    @Test func defaultFrequencyIsFiveMinutes() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = PeriodicScanScheduler(defaults: defaults, rescan: { true })
        #expect(scheduler.configuredInterval == 300)
    }

    @Test func timerFiresAtTheChosenFrequencyAndStartsAScan() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(120, forKey: PeriodicScanScheduler.frequencyKey)
        let sleeper = FakeSleeper()
        var scans = 0
        let scheduler = PeriodicScanScheduler(
            defaults: defaults,
            rescan: {
                scans += 1
                return true
            },
            sleep: { await sleeper.sleep($0) }
        )
        scheduler.start()
        defer { scheduler.stop() }

        await waitUntil { scans == 1 }
        #expect(scans == 1)
        #expect(scheduler.activeInterval == 120)
        #expect(sleeper.requested.first == .seconds(120))
    }

    @Test func offMeansNoTimer() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: PeriodicScanScheduler.frequencyKey)
        let sleeper = FakeSleeper()
        let scheduler = PeriodicScanScheduler(
            defaults: defaults,
            rescan: { true },
            sleep: { await sleeper.sleep($0) }
        )
        scheduler.start()
        defer { scheduler.stop() }
        #expect(scheduler.activeInterval == nil)
        #expect(sleeper.requested.isEmpty)
    }

    /// No reload() call: the change must reach the scheduler through its UserDefaults observer.
    @Test func changingTheSavedFrequencyReplacesThenCancelsTheTimer() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(60, forKey: PeriodicScanScheduler.frequencyKey)
        let clock = ParkingSleeper()
        let scheduler = PeriodicScanScheduler(
            defaults: defaults,
            rescan: { true },
            sleep: { await clock.sleep($0) }
        )
        scheduler.start()
        defer { scheduler.stop() }
        await waitUntil { clock.requested == [.seconds(60)] }
        #expect(clock.requested == [.seconds(60)])

        defaults.set(600, forKey: PeriodicScanScheduler.frequencyKey)
        await waitUntil { clock.requested == [.seconds(60), .seconds(600)] && clock.cancelled == 1 }
        #expect(clock.requested == [.seconds(60), .seconds(600)], "A new timer runs at the new frequency")
        #expect(clock.cancelled == 1, "The old timer was cancelled")
        #expect(scheduler.activeInterval == 600)

        defaults.set(0, forKey: PeriodicScanScheduler.frequencyKey)
        await waitUntil { clock.cancelled == 2 }
        #expect(clock.cancelled == 2, "Off cancels the running timer")
        #expect(clock.requested.count == 2, "Off starts no new timer")
        #expect(scheduler.activeInterval == nil)
    }

    @Test func tickReportsWhetherTheRescanStarted() {
        var started = false
        var asks = 0
        let scheduler = PeriodicScanScheduler(rescan: {
            asks += 1
            return started
        })
        #expect(scheduler.tick() == false)
        started = true
        #expect(scheduler.tick() == true)
        #expect(asks == 2)
    }

    @Test func stopCancelsTheTimer() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(60, forKey: PeriodicScanScheduler.frequencyKey)
        let scheduler = PeriodicScanScheduler(defaults: defaults, rescan: { true })
        scheduler.start()
        scheduler.stop()
        #expect(scheduler.activeInterval == nil)
    }
}

// MARK: - CheckRetryPolicy

@Suite("CheckRetryPolicy")
struct CheckRetryPolicyTests {
    @Test func retryOffMarksDownAfterOneFailure() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = CheckRetryPolicy(defaults: defaults)
        #expect(policy.requiredFailures == 1)
        #expect(!policy.shouldRetry(afterConsecutiveFailures: 1))
    }

    @Test func retryOnUsesTheSavedCount() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CheckRetryPolicy.enabledKey)
        defaults.set(4, forKey: CheckRetryPolicy.countKey)
        let policy = CheckRetryPolicy(defaults: defaults)
        #expect(policy.requiredFailures == 4)
        #expect(policy.shouldRetry(afterConsecutiveFailures: 3))
        #expect(!policy.shouldRetry(afterConsecutiveFailures: 4))
    }

    @Test func retryOnWithoutASavedCountUsesThree() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CheckRetryPolicy.enabledKey)
        #expect(CheckRetryPolicy(defaults: defaults).requiredFailures == 3)
    }

    /// A count of 1 means down after one failure, the same as retry off (brief: "N consecutive failed checks").
    @Test func countOfOneBehavesLikeRetryOff() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CheckRetryPolicy.enabledKey)
        defaults.set(1, forKey: CheckRetryPolicy.countKey)
        #expect(CheckRetryPolicy(defaults: defaults).requiredFailures == 1)
    }
}

// MARK: - MonitoringSession retry

/// Fails the first `failuresBeforeSuccess` checks, then succeeds. Counts every check.
private actor FlakyMonitorService: NetMonitor_macOS.NetworkMonitorService {
    let failuresBeforeSuccess: Int
    private(set) var checks = 0
    init(failuresBeforeSuccess: Int) { self.failuresBeforeSuccess = failuresBeforeSuccess }

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        checks += 1
        let reachable = checks > failuresBeforeSuccess
        return MeasurementResult(
            targetID: request.id, timestamp: Date(),
            latency: reachable ? 10 : nil, isReachable: reachable,
            errorMessage: reachable ? nil : "down (stub)"
        )
    }
}

@Suite("MonitoringSession retry", .serialized)
@MainActor
struct MonitoringSessionRetryTests {
    private func run(
        failuresBeforeSuccess: Int,
        retryEnabled: Bool,
        retryCount: Int
    ) async throws -> (reachable: Bool?, checks: Int, saved: Int) {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let target = NetworkTarget(name: "Router", host: "192.168.1.1", targetProtocol: .icmp, checkInterval: 60, isEnabled: true)
        context.insert(target)
        try context.save()

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(retryEnabled, forKey: CheckRetryPolicy.enabledKey)
        defaults.set(retryCount, forKey: CheckRetryPolicy.countKey)

        let stub = FlakyMonitorService(failuresBeforeSuccess: failuresBeforeSuccess)
        let session = MonitoringSession(
            modelContext: context,
            anyHTTPService: stub, anyICMPService: stub, anyTCPService: stub,
            defaults: defaults
        )
        session.startMonitoring()
        await waitUntil { session.latestResults[target.id] != nil }
        let reachable = session.latestResults[target.id]?.isReachable
        await session.stopMonitoringAndWait()
        let saved = try context.fetch(FetchDescriptor<TargetMeasurement>()).count
        return await (reachable, stub.checks, saved)
    }

    @Test func retryOffMarksDownAfterTheFirstFailure() async throws {
        let result = try await run(failuresBeforeSuccess: 2, retryEnabled: false, retryCount: 3)
        #expect(result.reachable == false)
        #expect(result.checks == 1)
    }

    @Test func retryOnStaysUpWhenAFailureIsFollowedBySuccess() async throws {
        let result = try await run(failuresBeforeSuccess: 2, retryEnabled: true, retryCount: 3)
        #expect(result.reachable == true)
        #expect(result.checks == 3)
        #expect(result.saved == 1, "Only the final result is saved to history")
    }

    @Test func retryOnMarksDownAfterNConsecutiveFailures() async throws {
        let result = try await run(failuresBeforeSuccess: 10, retryEnabled: true, retryCount: 3)
        #expect(result.reachable == false)
        #expect(result.checks == 3)
        #expect(result.saved == 1)
    }
}
