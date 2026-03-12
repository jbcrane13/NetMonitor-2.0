import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - Mock Ping Service

/// Synchronously yields a fixed list of PingResults then finishes the stream.
private final class MockPingService: PingServiceProtocol, @unchecked Sendable {
    var mockResults: [PingResult] = []
    var capturedHost: String?
    var capturedCount: Int?
    var capturedTimeout: TimeInterval?

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        capturedHost = host
        capturedCount = count
        capturedTimeout = timeout
        let results = mockResults
        return AsyncStream { continuation in
            for result in results { continuation.yield(result) }
            continuation.finish()
        }
    }

    func stop() async {}
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

// MARK: - Helpers

private func makePingResult(sequence: Int, time: Double, isTimeout: Bool = false) -> PingResult {
    PingResult(sequence: sequence, host: "8.8.8.8", ttl: 64, time: time, isTimeout: isTimeout)
}

// MARK: - Initial State Tests

@Suite("NetworkHealthScoreMacViewModel – initial state")
@MainActor
struct HealthScoreMacVMInitialStateTests {

    @Test func currentScoreIsNilInitially() {
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: MockPingService()
        )
        #expect(vm.currentScore == nil)
    }

    @Test func isCalculatingIsFalseInitially() {
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: MockPingService()
        )
        #expect(vm.isCalculating == false)
    }
}

// MARK: - Lifecycle Tests

@Suite("NetworkHealthScoreMacViewModel – lifecycle")
@MainActor
struct HealthScoreMacVMLifecycleTests {

    @Test func isCalculatingIsFalseAfterRefreshWithEmptyStream() async {
        let mockPing = MockPingService()
        mockPing.mockResults = []
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }

    @Test func isCalculatingIsFalseAfterRefreshWithSuccessfulResults() async {
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 20.0),
            makePingResult(sequence: 2, time: 25.0),
            makePingResult(sequence: 3, time: 30.0),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }

    @Test func isCalculatingIsFalseAfterRefreshWithAllTimeouts() async {
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 0, isTimeout: true),
            makePingResult(sequence: 2, time: 0, isTimeout: true),
            makePingResult(sequence: 3, time: 0, isTimeout: true),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }

    @Test func subsequentRefreshesLeaveIsCalculatingFalse() async {
        let mockPing = MockPingService()
        mockPing.mockResults = [makePingResult(sequence: 1, time: 15.0)]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.isCalculating == false)
        await vm.refresh()
        #expect(vm.isCalculating == false)
    }
}

// MARK: - Score Population Tests

@Suite("NetworkHealthScoreMacViewModel – score population")
@MainActor
struct HealthScoreMacVMScorePopulationTests {

    @Test func currentScoreNonNilAfterRefreshWithResults() async {
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 20.0),
            makePingResult(sequence: 2, time: 22.0),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.currentScore != nil)
    }

    @Test func currentScoreNonNilAfterRefreshWithEmptyStream() async {
        // Even with no ping results, refresh sets currentScore (score=0 because no data)
        let mockPing = MockPingService()
        mockPing.mockResults = []
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        // currentScore is set (to a zero score), not nil
        #expect(vm.currentScore != nil)
    }

    @Test func emptyStreamYieldsScoreZeroWithGradeF() async {
        let mockPing = MockPingService()
        mockPing.mockResults = []
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(vm.currentScore?.score == 0)
        #expect(vm.currentScore?.grade == "F")
    }

    @Test func allTimeoutsYieldsNilLatencyAndFullPacketLoss() async throws {
        // All timeouts → latencyMs=nil, packetLoss=1.0 → 0pts from latency, 0pts from loss
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 0, isTimeout: true),
            makePingResult(sequence: 2, time: 0, isTimeout: true),
            makePingResult(sequence: 3, time: 0, isTimeout: true),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        // packetLoss=1.0 ≥ 0.10 → 0pts loss; latencyMs=nil → not contributed
        // total=0, max=35 (loss only) → score=0
        #expect(score.latencyMs == nil)
        #expect(score.packetLoss == 1.0)
        #expect(score.score == 0)
    }

    @Test func perfectPingsYieldHighScore() async throws {
        // 5 pings at 10ms, 0 timeouts → latencyMs=10, packetLoss=0.0
        // latency<30ms→35pts, loss=0→35pts, total=70/70→100
        let mockPing = MockPingService()
        mockPing.mockResults = (1...5).map { makePingResult(sequence: $0, time: 10.0) }
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        #expect(score.score == 100)
        #expect(score.grade == "A")
    }

    @Test func latencyAveragedFromNonTimeoutResults() async throws {
        // 2 success at 20ms and 40ms → avg=30ms; 1 timeout
        // latency=30ms→30pts, packetLoss=1/3≈0.333≥0.10→0pts
        // total=30, max=70 → Int(30/70*100)=42
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 20.0),
            makePingResult(sequence: 2, time: 40.0),
            makePingResult(sequence: 3, time: 0.0, isTimeout: true),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        #expect(score.latencyMs == 30.0)
    }

    @Test func packetLossRatioCorrectFromMixedResults() async throws {
        // 3 success, 2 timeout out of 5 → packetLoss = 2/5 = 0.4 (≥0.10 → 0pts)
        let mockPing = MockPingService()
        mockPing.mockResults = [
            makePingResult(sequence: 1, time: 20.0),
            makePingResult(sequence: 2, time: 20.0),
            makePingResult(sequence: 3, time: 20.0),
            makePingResult(sequence: 4, time: 0.0, isTimeout: true),
            makePingResult(sequence: 5, time: 0.0, isTimeout: true),
        ]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        #expect(score.packetLoss == 0.4)
    }

    @Test func singleSuccessfulPingYieldsNonZeroScore() async throws {
        let mockPing = MockPingService()
        mockPing.mockResults = [makePingResult(sequence: 1, time: 15.0)]
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        // latency<30ms→35pts, packetLoss=0.0→35pts → 100
        #expect(score.score > 0)
    }

    @Test func scoreRemainsWithinValidRange() async throws {
        let mockPing = MockPingService()
        mockPing.mockResults = (1...5).map { makePingResult(sequence: $0, time: 500.0) }
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let score = try #require(vm.currentScore)
        #expect(score.score >= 0)
        #expect(score.score <= 100)
    }

    @Test func refreshOverwritesPreviousScore() async {
        let mockPing = MockPingService()
        // First refresh: perfect
        mockPing.mockResults = (1...5).map { makePingResult(sequence: $0, time: 10.0) }
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        let firstScore = vm.currentScore?.score

        // Second refresh: all timeouts → score 0
        mockPing.mockResults = (1...5).map { makePingResult(sequence: $0, time: 0, isTimeout: true) }
        await vm.refresh()

        #expect(vm.currentScore?.score != firstScore)
        #expect(vm.currentScore?.score == 0)
    }
}

// MARK: - Ping Parameters Tests

@Suite("NetworkHealthScoreMacViewModel – ping parameters")
@MainActor
struct HealthScoreMacVMPingParametersTests {

    @Test func pingTargetsGoogleDNS() async {
        let mockPing = MockPingService()
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(mockPing.capturedHost == "8.8.8.8")
    }

    @Test func pingUsesFivePackets() async {
        let mockPing = MockPingService()
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(mockPing.capturedCount == 5)
    }

    @Test func pingUsesThreeSecondTimeout() async {
        let mockPing = MockPingService()
        let vm = NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: mockPing
        )
        await vm.refresh()
        #expect(mockPing.capturedTimeout == 3)
    }
}
