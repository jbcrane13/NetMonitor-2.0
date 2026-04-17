import Foundation
import Testing
@testable import NetMonitor_iOS

@MainActor
struct RoomPlanTaskTimeoutTests {
    @Test func timeoutRunReturnsValueWhenOperationCompletesInTime() async throws {
        let result = try await RoomPlanTaskTimeout.run(timeout: .seconds(1)) {
            "done"
        }

        #expect(result == "done")
    }

    @Test func timeoutRunThrowsWhenOperationTakesTooLong() async {
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
}
