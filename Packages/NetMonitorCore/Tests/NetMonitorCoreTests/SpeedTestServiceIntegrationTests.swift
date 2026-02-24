import Foundation
import Testing
@testable import NetMonitorCore

/// Integration tests for SpeedTestService.
/// These run real speed tests against Cloudflare — tag .integration for offline CI filtering.
///
/// SILENT FAILURE NOTE: measureLatency() swallows individual iteration errors with
/// `catch { continue }`. If all 3 latency probes fail, it returns 0.0 (not an error).
/// This means the user sees "0 ms" latency instead of an error message when the server
/// is unreachable. The download/upload phases will also return 0 in that scenario.
/// Fix path: change measureLatency to throw when all iterations fail.
@Suite("SpeedTestService Integration Tests")
@MainActor
struct SpeedTestServiceIntegrationTests {

    @Test("Real speed test produces non-zero download and upload speeds",
          .tags(.integration), .timeLimit(.minutes(1)))
    func realSpeedTestProducesResults() async throws {
        let service = SpeedTestService()
        service.duration = 2.0

        let result = try await service.startTest()

        #expect(result.downloadSpeed > 0, "Download speed must be > 0 on working network")
        #expect(result.uploadSpeed > 0, "Upload speed must be > 0 on working network")
        #expect(result.latency >= 0, "Latency must be non-negative")
        #expect(service.phase == .complete, "Phase must be .complete after test")
        #expect(service.isRunning == false, "isRunning must be false after test")
        #expect(service.errorMessage == nil, "No error expected on successful test")
    }

    @Test("Speed test result data matches final service state",
          .tags(.integration), .timeLimit(.minutes(1)))
    func resultMatchesServiceState() async throws {
        let service = SpeedTestService()
        service.duration = 2.0

        let result = try await service.startTest()

        #expect(service.downloadSpeed == result.downloadSpeed,
                "Service downloadSpeed should match returned result")
        #expect(service.uploadSpeed == result.uploadSpeed,
                "Service uploadSpeed should match returned result")
        #expect(service.latency == result.latency,
                "Service latency should match returned result")
    }

    @Test("Speed test progress reaches 1.0 on completion",
          .tags(.integration), .timeLimit(.minutes(1)))
    func progressReachesOneOnCompletion() async throws {
        let service = SpeedTestService()
        service.duration = 2.0

        _ = try await service.startTest()

        #expect(service.progress == 1.0, "Progress must be 1.0 after completion")
    }

    @Test("stopTest during real speed test cancels without crash", .tags(.integration))
    func stopDuringRealTestNoCrash() async {
        let service = SpeedTestService()
        service.duration = 10.0
        let task = Task {
            try? await service.startTest()
        }
        try? await Task.sleep(for: .milliseconds(500))
        service.stopTest()
        task.cancel()
        #expect(service.isRunning == false, "isRunning must be false after stop")
    }
}

// MARK: - SpeedTestError Tests

@Suite("SpeedTestError")
struct SpeedTestErrorTests {

    @Test("serverError has descriptive error message")
    func serverErrorDescription() {
        let err = SpeedTestError.serverError
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.contains("server") == true)
    }

    @Test("cancelled has descriptive error message")
    func cancelledErrorDescription() {
        let err = SpeedTestError.cancelled
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.contains("cancelled") == true)
    }

    @Test("serverError converts to NetworkError.serverError")
    func serverErrorConvertsToNetworkError() {
        let networkErr = SpeedTestError.serverError.asNetworkError
        if case .serverError = networkErr {
            // correct
        } else {
            Issue.record("Expected .serverError, got \(networkErr)")
        }
    }

    @Test("cancelled converts to NetworkError.cancelled")
    func cancelledConvertsToNetworkError() {
        let networkErr = SpeedTestError.cancelled.asNetworkError
        if case .cancelled = networkErr {
            // correct
        } else {
            Issue.record("Expected .cancelled, got \(networkErr)")
        }
    }
}

// MARK: - AtomicInt64 Concurrent Safety

@Suite("AtomicInt64 - Concurrent Safety")
struct AtomicInt64ConcurrentTests {

    @Test("Concurrent increments produce correct total")
    func concurrentIncrementsCorrectTotal() async {
        let counter = AtomicInt64()
        let iterations = 1000

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    counter.add(1)
                }
            }
        }

        #expect(counter.load() == Int64(iterations),
                "After \(iterations) concurrent +1 adds, expected \(iterations)")
    }

    @Test("Concurrent mixed adds and subtracts produce correct total")
    func concurrentMixedOperations() async {
        let counter = AtomicInt64()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask { counter.add(10) }
            }
            for _ in 0..<300 {
                group.addTask { counter.add(-3) }
            }
        }

        #expect(counter.load() == 500 * 10 - 300 * 3)
    }
}
