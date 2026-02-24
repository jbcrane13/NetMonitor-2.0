import XCTest
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - Mock Service

private final class MockWorldPingService: WorldPingServiceProtocol, @unchecked Sendable {
    var mockResults: [WorldPingLocationResult] = []
    var shouldDelay: Bool = false

    func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult> {
        let results = mockResults
        return AsyncStream { continuation in
            Task {
                for result in results {
                    if self.shouldDelay {
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    continuation.yield(result)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Tests

@MainActor
final class WorldPingToolViewModelTests: XCTestCase {

    private func makeResult(
        id: String = "node1",
        country: String = "Germany",
        city: String = "Frankfurt",
        latencyMs: Double? = 42.0,
        isSuccess: Bool = true
    ) -> WorldPingLocationResult {
        WorldPingLocationResult(id: id, country: country, city: city, latencyMs: latencyMs, isSuccess: isSuccess)
    }

    func testInitialState() {
        let vm = WorldPingToolViewModel(service: MockWorldPingService())
        XCTAssertEqual(vm.hostInput, "")
        XCTAssertFalse(vm.isRunning)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testCanRun_emptyHost_returnsFalse() {
        let vm = WorldPingToolViewModel(service: MockWorldPingService())
        XCTAssertFalse(vm.canRun)
    }

    func testCanRun_withHost_returnsTrue() {
        let vm = WorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "google.com"
        XCTAssertTrue(vm.canRun)
    }

    func testCanRun_whitespaceOnly_returnsFalse() {
        let vm = WorldPingToolViewModel(service: MockWorldPingService())
        vm.hostInput = "   "
        XCTAssertFalse(vm.canRun)
    }

    func testRun_populatesResults() async {
        let mock = MockWorldPingService()
        mock.mockResults = [
            makeResult(id: "de1", city: "Frankfurt", latencyMs: 30),
            makeResult(id: "us1", country: "USA", city: "Ashburn", latencyMs: 80)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "google.com"
        vm.run()

        // Wait for task to complete
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(vm.results.isEmpty)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNil(vm.errorMessage)
    }

    func testRun_emptyResults_setsError() async {
        let mock = MockWorldPingService()
        mock.mockResults = []
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "unreachable.invalid"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isRunning)
    }

    func testAverageLatency_withSuccessfulResults() async {
        let mock = MockWorldPingService()
        mock.mockResults = [
            makeResult(id: "n1", latencyMs: 40),
            makeResult(id: "n2", latencyMs: 80),
            makeResult(id: "n3", latencyMs: 120)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        let avg = vm.averageLatencyMs
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!, 80.0, accuracy: 0.01)
    }

    func testAverageLatency_noSuccessfulNodes_returnsNil() {
        let vm = WorldPingToolViewModel(service: MockWorldPingService())
        XCTAssertNil(vm.averageLatencyMs)
    }

    func testBestLatency_returnsMinimum() async {
        let mock = MockWorldPingService()
        mock.mockResults = [
            makeResult(id: "n1", latencyMs: 100),
            makeResult(id: "n2", latencyMs: 25),
            makeResult(id: "n3", latencyMs: 60)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.bestLatencyMs, 25.0)
    }

    func testSuccessCount_countsOnlySuccessfulNodes() async {
        let mock = MockWorldPingService()
        mock.mockResults = [
            makeResult(id: "n1", isSuccess: true),
            makeResult(id: "n2", isSuccess: false),
            makeResult(id: "n3", isSuccess: true)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.successCount, 2)
    }

    func testClear_resetsAllState() async {
        let mock = MockWorldPingService()
        mock.mockResults = [makeResult()]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))
        vm.clear()

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isRunning)
    }

    func testHasResults_afterSuccessfulRun_returnsTrue() async {
        let mock = MockWorldPingService()
        mock.mockResults = [makeResult()]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(vm.hasResults)
    }

    func testResultsSortedByLatency() async {
        let mock = MockWorldPingService()
        mock.mockResults = [
            makeResult(id: "n1", city: "Tokyo", latencyMs: 200),
            makeResult(id: "n2", city: "London", latencyMs: 20),
            makeResult(id: "n3", city: "Sydney", latencyMs: 150)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.results.count, 3)
        // Should be sorted by latency ascending
        let latencies = vm.results.compactMap { $0.latencyMs }
        XCTAssertEqual(latencies, latencies.sorted())
    }
}

// MARK: - Swift Testing Suite

private final class MockWorldPingServiceSwift: WorldPingServiceProtocol, @unchecked Sendable {
    var mockResults: [WorldPingLocationResult] = []

    func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult> {
        let results = mockResults
        return AsyncStream { continuation in
            for result in results { continuation.yield(result) }
            continuation.finish()
        }
    }
}

@Suite("WorldPingToolViewModel Edge Cases")
@MainActor
struct WorldPingToolViewModelEdgeCaseTests {

    private func makeResult(
        id: String,
        latencyMs: Double? = 42.0,
        isSuccess: Bool = true
    ) -> WorldPingLocationResult {
        WorldPingLocationResult(id: id, country: "USA", city: "New York", latencyMs: latencyMs, isSuccess: isSuccess)
    }

    @Test func emptyResultsSetsErrorMessage() async throws {
        let mock = MockWorldPingServiceSwift()
        mock.mockResults = []
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "unreachable.invalid"
        vm.run()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isRunning == false)
    }

    @Test func partialResultsWithSomeFailures() async throws {
        let mock = MockWorldPingServiceSwift()
        mock.mockResults = [
            makeResult(id: "n1", latencyMs: 20, isSuccess: true),
            makeResult(id: "n2", latencyMs: nil, isSuccess: false),
            makeResult(id: "n3", latencyMs: 50, isSuccess: true)
        ]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.results.count == 3)
        #expect(vm.successCount == 2)
        // average only counts successful nodes with latency
        let avg = vm.averageLatencyMs
        #expect(avg != nil)
        #expect(abs((avg ?? 0) - 35.0) < 0.01)
    }

    @Test func stopClearsIsRunning() {
        let mock = MockWorldPingServiceSwift()
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()
        vm.stop()
        #expect(vm.isRunning == false)
    }

    @Test func clearAfterRunResetsAllState() async throws {
        let mock = MockWorldPingServiceSwift()
        mock.mockResults = [makeResult(id: "n1")]
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()
        try await Task.sleep(for: .milliseconds(200))
        vm.clear()
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isRunning == false)
    }

    @Test func canRunFalseWhileRunning() {
        let mock = MockWorldPingServiceSwift()
        let vm = WorldPingToolViewModel(service: mock)
        vm.hostInput = "test.com"
        vm.run()
        #expect(vm.canRun == false)
        vm.stop()
    }
}
