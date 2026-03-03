import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Mock Service

@MainActor
private final class MockNetworkHealthScoreService: NetworkHealthScoreServiceProtocol, @unchecked Sendable {
    var mockScore = NetworkHealthScore(score: 85, grade: "B", latencyMs: 25, packetLoss: 0.02, details: ["latency": "25 ms"])
    var calculateCallCount = 0

    func calculateScore() async -> NetworkHealthScore {
        calculateCallCount += 1
        return mockScore
    }
}

@MainActor
private final class SlowNetworkHealthScoreService: NetworkHealthScoreServiceProtocol, @unchecked Sendable {
    var mockScore = NetworkHealthScore(score: 85, grade: "B", latencyMs: 25, packetLoss: 0.02, details: [:])
    var calculateCallCount = 0

    func calculateScore() async -> NetworkHealthScore {
        calculateCallCount += 1
        try? await Task.sleep(for: .milliseconds(200))
        return mockScore
    }
}

@MainActor
private final class MockPingServiceForHealth: PingServiceProtocol, @unchecked Sendable {
    var mockResults: [PingResult] = []

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        let results = mockResults
        return AsyncStream { continuation in
            for r in results { continuation.yield(r) }
            continuation.finish()
        }
    }

    func stop() async {}
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

@MainActor
private final class MockNetworkMonitor: NetworkMonitorServiceProtocol, @unchecked Sendable {
    var isConnected: Bool = true
    var connectionType: ConnectionType = .wifi
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var statusText: String = "Connected"
    func startMonitoring() {}
    func stopMonitoring() {}
}

// MARK: - Tests

@Suite("NetworkHealthScoreViewModel")
@MainActor
struct NetworkHealthScoreViewModelTests {

    @Test func initialStateIsEmpty() {
        let vm = NetworkHealthScoreViewModel(
            service: MockNetworkHealthScoreService(),
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        #expect(vm.currentScore == nil)
        #expect(vm.isCalculating == false)
        #expect(vm.lastUpdated == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func gradeTextReturnsEmDashWhenNoScore() {
        let vm = NetworkHealthScoreViewModel(
            service: MockNetworkHealthScoreService(),
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        #expect(vm.gradeText == "—")
    }

    @Test func scoreValueReturnsZeroWhenNoScore() {
        let vm = NetworkHealthScoreViewModel(
            service: MockNetworkHealthScoreService(),
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        #expect(vm.scoreValue == 0)
    }

    @Test func latencyTextReturnsEmDashWhenNoScore() {
        let vm = NetworkHealthScoreViewModel(
            service: MockNetworkHealthScoreService(),
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        #expect(vm.latencyText == "—")
    }

    @Test func packetLossTextReturnsEmDashWhenNoScore() {
        let vm = NetworkHealthScoreViewModel(
            service: MockNetworkHealthScoreService(),
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        #expect(vm.packetLossText == "—")
    }
}

// MARK: - Async Refresh Tests

@Suite("NetworkHealthScoreViewModel Refresh")
@MainActor
struct NetworkHealthScoreViewModelRefreshTests {

    func makeVM(
        score: NetworkHealthScore = NetworkHealthScore(score: 85, grade: "B", latencyMs: 25, packetLoss: 0.02, details: [:]),
        pingResults: [PingResult] = []
    ) -> NetworkHealthScoreViewModel {
        let mockService = MockNetworkHealthScoreService()
        mockService.mockScore = score
        let mockPing = MockPingServiceForHealth()
        mockPing.mockResults = pingResults
        return NetworkHealthScoreViewModel(
            service: mockService,
            pingService: mockPing,
            networkMonitor: MockNetworkMonitor()
        )
    }

    @Test func refreshSetsLastUpdated() async throws {
        let vm = makeVM()
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.lastUpdated != nil)
    }

    @Test func refreshSetsCurrentScore() async throws {
        let score = NetworkHealthScore(score: 72, grade: "C", latencyMs: 80, packetLoss: 0.1, details: [:])
        let vm = makeVM(score: score)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.currentScore?.score == 72)
        #expect(vm.currentScore?.grade == "C")
    }

    @Test func refreshIsNotReentrant() async throws {
        // Use a slow service so isCalculating stays true long enough for the guard to fire
        let slowService = SlowNetworkHealthScoreService()
        let vm = NetworkHealthScoreViewModel(
            service: slowService,
            pingService: MockPingServiceForHealth(),
            networkMonitor: MockNetworkMonitor()
        )
        vm.refresh()
        await waitUntil { vm.isCalculating == true }  // task has started
        vm.refresh()  // guard fires — isCalculating is true → no-op
        await waitUntil { vm.isCalculating == false }
        #expect(slowService.calculateCallCount == 1)
    }

    @Test func gradeTextAfterRefresh() async throws {
        let score = NetworkHealthScore(score: 90, grade: "A", latencyMs: 10, packetLoss: 0.0, details: [:])
        let vm = makeVM(score: score)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.gradeText == "A")
    }

    @Test func scoreValueAfterRefresh() async throws {
        let score = NetworkHealthScore(score: 55, grade: "D", latencyMs: 200, packetLoss: 0.15, details: [:])
        let vm = makeVM(score: score)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.scoreValue == 55)
    }

    @Test func latencyTextAfterRefresh() async throws {
        let score = NetworkHealthScore(score: 80, grade: "B", latencyMs: 42, packetLoss: 0.01, details: [:])
        let vm = makeVM(score: score)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.latencyText == "42 ms")
    }

    @Test func packetLossTextAfterRefresh() async throws {
        let score = NetworkHealthScore(score: 75, grade: "C", latencyMs: 30, packetLoss: 0.05, details: [:])
        let vm = makeVM(score: score)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.packetLossText == "5%")
    }

    @Test func refreshWithPingResultsComputesLatency() async throws {
        let results = [
            PingResult(sequence: 1, host: "8.8.8.8", ttl: 64, time: 20.0, isTimeout: false),
            PingResult(sequence: 2, host: "8.8.8.8", ttl: 64, time: 30.0, isTimeout: false),
            PingResult(sequence: 3, host: "8.8.8.8", ttl: 64, time: 0.0, isTimeout: true),
        ]
        let vm = makeVM(pingResults: results)
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.currentScore != nil)
    }

    @Test func isCalculatingFalseAfterRefreshCompletes() async throws {
        let vm = makeVM()
        vm.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isCalculating == false)
    }
}

// NOTE: Scoring algorithm tests (grade, computeScore) are in the package test target:
// Packages/NetMonitorCore/Tests/NetMonitorCoreTests/NetworkHealthScoreServiceTests.swift
// Those APIs are internal to NetMonitorCore and cannot be accessed from the app test target.
