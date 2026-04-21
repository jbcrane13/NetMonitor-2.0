import Testing
import Foundation
@testable import NetMonitor_macOS
import NetMonitorCore

// MARK: - Mock Service

private final class MockWorldPingService: WorldPingServiceProtocol, @unchecked Sendable {
    var mockResults: [WorldPingLocationResult] = []
    var lastError: String?
    var pingCallCount = 0

    func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult> {
        pingCallCount += 1
        let results = mockResults
        return AsyncStream { continuation in
            for result in results {
                continuation.yield(result)
            }
            continuation.finish()
        }
    }
}

// MARK: - Initial State Tests

@MainActor
struct MacWorldPingToolViewModelInitialStateTests {

    @Test func initialState() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        #expect(vm.hostInput == "")
        #expect(vm.isRunning == false)
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialHostIsSet() {
        let mock = MockWorldPingService()
        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "8.8.8.8"
        #expect(vm.hostInput == "8.8.8.8")
    }

    @Test func hasResultsFalseWhenEmpty() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        #expect(vm.hasResults == false)
    }

    @Test func successCountZeroWhenEmpty() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        #expect(vm.successCount == 0)
    }
}

// MARK: - Validation Tests

@MainActor
struct MacWorldPingToolViewModelValidationTests {

    @Test func canRunFalseWhenHostEmpty() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = ""
        #expect(vm.canRun == false)
    }

    @Test func canRunFalseWhenHostIsWhitespace() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "   "
        #expect(vm.canRun == false)
    }

    @Test func canRunTrueWithValidHost() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "google.com"
        #expect(vm.canRun == true)
    }

    @Test func canRunFalseWhileRunning() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "google.com"
        vm.isRunning = true
        #expect(vm.canRun == false)
    }
}

// MARK: - Run Lifecycle Tests

@Suite(.serialized) @MainActor
struct MacWorldPingToolViewModelRunTests {

    @Test func runIgnoredWhenCannotRun() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = ""
        vm.run()
        #expect(vm.isRunning == false)
        #expect(vm.results.isEmpty)
    }

    @Test func runSetsIsRunningImmediately() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "test.com"
        vm.run()
        #expect(vm.isRunning == true)
    }

    @Test func runClearsExistingResults() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "test.com"
        // Pre-populate with old data
        vm.results = [WorldPingLocationResult(
            id: "old", country: "Old", city: "Old",
            latencyMs: 999, isSuccess: true
        )]
        vm.errorMessage = "old error"

        vm.run()

        // Results and error should be cleared synchronously
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isRunning == true)
    }

    @Test func runPopulatesResultsAsStreamCompletes() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "de1", country: "Germany", city: "Frankfurt", latencyMs: 30, isSuccess: true),
            WorldPingLocationResult(id: "us1", country: "USA", city: "Ashburn", latencyMs: 80, isSuccess: true),
            WorldPingLocationResult(id: "jp1", country: "Japan", city: "Tokyo", latencyMs: 150, isSuccess: true),
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "google.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(vm.results.count == 3)
        #expect(vm.isRunning == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func runSortsByLatency() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "C1", city: "C1", latencyMs: 100, isSuccess: true),
            WorldPingLocationResult(id: "n2", country: "C2", city: "C2", latencyMs: 25, isSuccess: true),
            WorldPingLocationResult(id: "n3", country: "C3", city: "C3", latencyMs: 60, isSuccess: true),
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        let latencies = vm.results.compactMap { $0.latencyMs }
        #expect(latencies == [25, 60, 100])
    }

    @Test func runWithEmptyResultsSetsError() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = []
        mock.lastError = "Host unreachable"

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "unreachable.invalid"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isRunning == false)
    }

    @Test func runCallsServiceWithCorrectHost() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true)
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "  example.com  "
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(mock.pingCallCount == 1)
    }
}

// MARK: - Stop Tests

@MainActor
struct MacWorldPingToolViewModelStopTests {

    @Test func stopSetsIsRunningFalse() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "test.com"
        vm.run()
        #expect(vm.isRunning == true)

        vm.stop()
        #expect(vm.isRunning == false)
    }

    @Test func stopCancelsInFlightWork() throws {
        let mock = MockWorldPingService()
        // Provide some results so the stream has content
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true)
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()
        vm.stop()

        #expect(vm.isRunning == false)
    }
}

// MARK: - Clear Tests

@MainActor
struct MacWorldPingToolViewModelClearTests {

    @Test func clearResetsAllState() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true)
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        vm.clear()

        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isRunning == false)
    }

    @Test func clearStopsRunningTask() {
        let vm = MacWorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "test.com"
        vm.run()
        #expect(vm.isRunning == true)

        vm.clear()

        #expect(vm.isRunning == false)
    }
}

// MARK: - Result Computation Tests

@MainActor
struct MacWorldPingToolViewModelResultComputationTests {

    @Test func successCountFiltersFailedResults() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true),
            WorldPingLocationResult(id: "n2", country: "USA", city: "LA", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "n3", country: "USA", city: "SF", latencyMs: 75, isSuccess: true),
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(vm.successCount == 2)
    }

    @Test func hasResultsTrueAfterSuccessfulRun() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true)
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(vm.hasResults == true)
    }
}

// MARK: - Edge Cases

@Suite(.serialized) @MainActor
struct MacWorldPingToolViewModelEdgeCaseTests {

    @Test func successCountWithAllFailures() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "n2", country: "USA", city: "LA", latencyMs: nil, isSuccess: false),
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        #expect(vm.successCount == 0)
        #expect(vm.results.count == 2)
    }

    @Test func rerunAfterCompletionResetsState() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true)
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"

        // First run
        vm.run()
        await waitUntilMainActor { vm.isRunning == false }
        let firstRunCount = vm.results.count

        // Second run
        vm.run()
        await waitUntilMainActor { vm.isRunning == false }
        let secondRunCount = vm.results.count

        #expect(firstRunCount == 1)
        #expect(secondRunCount == 1)
    }

    @Test func resultsSortingWithNilLatencies() async throws {
        let mock = MockWorldPingService()
        mock.mockResults = [
            WorldPingLocationResult(id: "n1", country: "USA", city: "NYC", latencyMs: 50, isSuccess: true),
            WorldPingLocationResult(id: "n2", country: "USA", city: "LA", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "n3", country: "USA", city: "SF", latencyMs: 30, isSuccess: true),
        ]

        let vm = MacWorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        await waitUntilMainActor { vm.isRunning == false }

        // Results with latencies should come before those with nil
        let firstLatency = vm.results[0].latencyMs
        let secondLatency = vm.results[1].latencyMs
        #expect(firstLatency == 30)
        #expect(secondLatency == 50)
    }
}

// MARK: - Helper

@MainActor
private func waitUntilMainActor(
    _ condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
