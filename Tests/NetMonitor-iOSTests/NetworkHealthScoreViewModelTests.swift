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

// NOTE: Scoring algorithm tests (grade, computeScore) are in the package test target:
// Packages/NetMonitorCore/Tests/NetMonitorCoreTests/NetworkHealthScoreServiceTests.swift
// Those APIs are internal to NetMonitorCore and cannot be accessed from the app test target.
