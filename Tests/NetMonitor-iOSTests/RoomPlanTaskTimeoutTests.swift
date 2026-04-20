import Foundation
import Testing
@testable import NetMonitor_iOS

struct RoomPlanTaskTimeoutTests {
    @Test func timeoutRunReturnsValueWhenOperationCompletesInTime() async throws {
        let result = try await RoomPlanTaskTimeout.run(timeout: .seconds(1)) {
            "done"
        }

        #expect(result == "done")
    }

    @Test func timeoutRunThrowsTimeoutErrorWhenOperationTakesTooLong() async {
        do {
            _ = try await RoomPlanTaskTimeout.run(timeout: .milliseconds(50)) {
                try await Task.sleep(for: .seconds(1))
                return "too late"
            }
            Issue.record("Expected timeout error but operation succeeded")
        } catch let error as RoomPlanBuildError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected RoomPlanBuildError.timeout, got \(error)")
        }
    }

    /// Regression guard: non-timeout errors thrown by the operation must
    /// propagate unchanged. Wrapping them as `.timeout` would cause the
    /// `buildCapturedRoom` fallback path (which pattern-matches on `.timeout`)
    /// to run a second 30s attempt on deterministic failures, doubling the
    /// latency before the user sees the real error.
    @Test func operationErrorRethrownNotWrapped() async {
        struct SentinelError: Error, Equatable {}

        do {
            _ = try await RoomPlanTaskTimeout.run(timeout: .seconds(1)) {
                throw SentinelError()
            }
            Issue.record("Expected SentinelError but operation succeeded")
        } catch is RoomPlanBuildError {
            Issue.record("SentinelError was wrapped as RoomPlanBuildError — should be rethrown unchanged")
        } catch is SentinelError {
            // Expected.
        } catch {
            Issue.record("Expected SentinelError, got \(error)")
        }
    }
}
