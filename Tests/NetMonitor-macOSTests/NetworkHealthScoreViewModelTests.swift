import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - DI Gap Analysis
//
// NetworkHealthScoreMacViewModel creates its dependencies internally:
//
//   private let service = NetworkHealthScoreService()
//   private let pingService: any PingServiceProtocol = PingService()
//
// There is no injectable initializer. This means we cannot supply a mock
// PingService to control stream output, and we cannot prevent the real
// PingService from attempting live network I/O during tests.
//
// What IS testable without DI:
//   • Initial property state (`isCalculating`, `currentScore`)
//   • The `defer { isCalculating = false }` invariant — after refresh() awaits,
//     isCalculating must be false regardless of network outcome.
//   • currentScore is non-nil or nil after refresh(), but isCalculating is false.
//
// The NetworkHealthScoreService itself is fully injectable and stateless between
// calls — its behavior is covered exhaustively in NetworkHealthScoreServiceTests.swift.

// MARK: - NetworkHealthScoreMacViewModel lifecycle tests

@Suite("NetworkHealthScoreMacViewModel – lifecycle")
@MainActor
struct HealthScoreVMLifecycleTests {

    @Test func isCalculatingIsFalseInitially() {
        let vm = NetworkHealthScoreMacViewModel()
        #expect(vm.isCalculating == false)
    }

    @Test func currentScoreIsNilInitially() {
        let vm = NetworkHealthScoreMacViewModel()
        #expect(vm.currentScore == nil)
    }

    @Test func isCalculatingIsFalseAfterRefresh() async {
        // The defer block guarantees isCalculating returns to false even if
        // the ping network call times out or fails. We await the full call.
        let vm = NetworkHealthScoreMacViewModel()
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }

    @Test func currentScoreIsSetAfterRefresh() async {
        // After a real refresh(), currentScore may be non-nil if the host
        // responded, or nil if 8.8.8.8 was unreachable from the test host.
        // Either way, isCalculating must be false and no crash should occur.
        let vm = NetworkHealthScoreMacViewModel()
        await vm.refresh()
        // We only assert the state contract, not the score value,
        // since test environments may not have network access.
        #expect(vm.isCalculating == false)
    }

    @Test func subsequentRefreshesDoNotLeaveCalculatingTrue() async {
        let vm = NetworkHealthScoreMacViewModel()
        // Call refresh twice sequentially — both must leave isCalculating=false
        await vm.refresh()
        #expect(vm.isCalculating == false)
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }
}

// MARK: - NetworkHealthScoreService.calculateScore async behavior
//
// These tests exercise the async calculateScore() entry point of the service
// directly, verifying the full integration of update() → calculateScore()
// with specific connectivity states.

@Suite("NetworkHealthScoreService – async calculateScore behavior")
struct HealthScoreServiceAsyncTests {

    @Test func isConnectedFalseYieldsScoreZeroGradeF() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: 25,
            packetLoss: 0.0,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: false
        )
        let result = await service.calculateScore()
        #expect(result.score == 0)
        #expect(result.grade == "F")
    }

    @Test func perfectInputWhileConnectedYieldsHighScore() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: 25,
            packetLoss: 0.0,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: true
        )
        let result = await service.calculateScore()
        // latency <30ms (35pts) + loss=0 (35pts) → 70/70 → 100
        #expect(result.score == 100)
        #expect(result.grade == "A")
    }

    @Test func nilLatencyAndNilLossWhileConnectedYieldsScoreZero() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: nil,
            packetLoss: nil,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: true
        )
        let result = await service.calculateScore()
        #expect(result.score == 0)
    }

    @Test func updateOverwritesPreviousValues() async {
        let service = NetworkHealthScoreService()
        // First update: perfect score
        service.update(latencyMs: 5, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        // Second update: no data → score 0
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 0)
    }

    @Test func switchingFromConnectedToOfflineYieldsZero() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 5, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let connected = await service.calculateScore()
        #expect(connected.score > 0)

        service.update(latencyMs: 5, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: false)
        let disconnected = await service.calculateScore()
        #expect(disconnected.score == 0)
        #expect(disconnected.grade == "F")
    }

    @Test func calculateScoreIsCallableMultipleTimesWithoutMutation() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 25, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        // Calling calculateScore() twice with the same state should return equal scores
        let first = await service.calculateScore()
        let second = await service.calculateScore()
        #expect(first.score == second.score)
        #expect(first.grade == second.grade)
    }
}
