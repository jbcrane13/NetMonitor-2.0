import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("PingToolViewModel", .serialized)
@MainActor
struct PingToolViewModelTests {

    @Test func initialState() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.host == "")
        #expect(vm.isRunning == false)
        #expect(vm.results.isEmpty)
        #expect(vm.statistics == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialHostIsSet() {
        let vm = PingToolViewModel(pingService: MockPingService(), initialHost: "192.168.1.1")
        #expect(vm.host == "192.168.1.1")
    }

    @Test func availablePingCountsAreCorrect() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.availablePingCounts == [4, 10, 20, 50, 100])
    }

    @Test func canStartPingFalseWhenHostEmpty() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = ""
        #expect(vm.canStartPing == false)
    }

    @Test func canStartPingFalseWhenHostIsWhitespace() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "   "
        #expect(vm.canStartPing == false)
    }

    @Test func canStartPingTrueWithValidHost() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        #expect(vm.canStartPing == true)
    }

    @Test func canStartPingFalseWhileRunning() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.isRunning = true
        #expect(vm.canStartPing == false)
    }

    @Test func clearResultsResetsState() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [PingResult(sequence: 1, host: "test", ttl: 64, time: 10.0)]
        vm.statistics = PingStatistics(
            host: "test", transmitted: 1, received: 1,
            packetLoss: 0, minTime: 10, maxTime: 10, avgTime: 10
        )
        vm.errorMessage = "Some error"

        vm.clearResults()

        #expect(vm.results.isEmpty)
        #expect(vm.statistics == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func startPingSetsIsRunningImmediately() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.startPing()
        #expect(vm.isRunning == true)
    }

    @Test func startPingClearsExistingResultsSynchronously() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.results = [PingResult(sequence: 1, host: "old", ttl: 64, time: 5.0)]
        vm.startPing()
        // clearResults() is called synchronously before spawning the Task
        #expect(vm.results.isEmpty)
    }

    @Test func startPingIgnoredWhenCannotStart() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "" // cannot start
        vm.startPing()
        #expect(vm.isRunning == false)
    }

    @Test func stopPingSetsIsRunningFalse() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.startPing()
        vm.stopPing()
        #expect(vm.isRunning == false)
    }
}

// MARK: - Live Stats Computation

@Suite("PingToolViewModel - Live Stats")
@MainActor
struct PingToolViewModelLiveStatsTests {

    @Test("liveAvgLatency computes mean of successful pings")
    func liveAvgLatencyNormal() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 10.0),
            PingResult(sequence: 2, host: "h", ttl: 64, time: 20.0),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 30.0),
        ]
        #expect(vm.liveAvgLatency == 20.0)
    }

    @Test("liveAvgLatency excludes timeout results")
    func liveAvgLatencyExcludesTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 10.0),
            PingResult(sequence: 2, host: "h", ttl: 0, time: 0.0, isTimeout: true),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 30.0),
        ]
        #expect(vm.liveAvgLatency == 20.0)
    }

    @Test("liveAvgLatency returns 0 when all results are timeouts")
    func liveAvgLatencyAllTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 0, time: 0.0, isTimeout: true),
            PingResult(sequence: 2, host: "h", ttl: 0, time: 0.0, isTimeout: true),
        ]
        #expect(vm.liveAvgLatency == 0)
    }

    @Test("liveAvgLatency returns 0 when results are empty")
    func liveAvgLatencyEmpty() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.liveAvgLatency == 0)
    }

    @Test("liveMinLatency returns smallest successful ping time")
    func liveMinLatency() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 15.0),
            PingResult(sequence: 2, host: "h", ttl: 64, time: 5.0),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 25.0),
        ]
        #expect(vm.liveMinLatency == 5.0)
    }

    @Test("liveMinLatency returns 0 when no successful pings")
    func liveMinLatencyEmpty() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.liveMinLatency == 0)
    }

    @Test("liveMaxLatency returns largest successful ping time")
    func liveMaxLatency() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 15.0),
            PingResult(sequence: 2, host: "h", ttl: 64, time: 5.0),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 25.0),
        ]
        #expect(vm.liveMaxLatency == 25.0)
    }

    @Test("liveMaxLatency returns 0 when no successful pings")
    func liveMaxLatencyEmpty() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.liveMaxLatency == 0)
    }

    @Test("liveMinLatency excludes timeouts")
    func liveMinLatencyExcludesTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 0, time: 0.0, isTimeout: true),
            PingResult(sequence: 2, host: "h", ttl: 64, time: 12.0),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 8.0),
        ]
        #expect(vm.liveMinLatency == 8.0)
    }
}

// MARK: - chartYAxisMax Distribution Tests

@Suite("PingToolViewModel - chartYAxisMax")
@MainActor
struct PingToolViewModelChartYAxisMaxTests {

    @Test("normal distribution uses P95-based calculation")
    func normalDistribution() {
        let vm = PingToolViewModel(pingService: MockPingService())
        // 10 results with values 10..19
        vm.results = (0..<10).map { i in
            PingResult(sequence: i + 1, host: "h", ttl: 64, time: Double(10 + i))
        }
        let yMax = vm.chartYAxisMax
        // P95 index = Int(9 * 0.95) = 8 => value 18
        // Median index = 10 / 2 = 5 => value 15
        // max(18, 15 * 1.5) = max(18, 22.5) = 22.5
        // 22.5 * 1.15 = 25.875
        #expect(yMax > 0)
        #expect(yMax > 18.0) // must be above P95
    }

    @Test("spike distribution clips outlier via P95")
    func spikeDistribution() {
        let vm = PingToolViewModel(pingService: MockPingService())
        // 9 normal values around 10ms, one spike at 500ms
        var results: [PingResult] = (0..<9).map { i in
            PingResult(sequence: i + 1, host: "h", ttl: 64, time: 10.0 + Double(i))
        }
        results.append(PingResult(sequence: 10, host: "h", ttl: 64, time: 500.0))
        vm.results = results

        let yMax = vm.chartYAxisMax
        // The Y-axis max should be well below 500 because P95 clips the spike
        #expect(yMax < 500.0)
        #expect(yMax > 10.0)
    }

    @Test("single result returns value * 1.2")
    func singleResult() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [PingResult(sequence: 1, host: "h", ttl: 64, time: 10.0)]
        let yMax = vm.chartYAxisMax
        // guard times.count >= 2 fails, so max(10 * 1.2, 1) = 12.0
        #expect(yMax == 12.0)
    }

    @Test("empty results returns at least 1")
    func emptyResults() {
        let vm = PingToolViewModel(pingService: MockPingService())
        let yMax = vm.chartYAxisMax
        // guard times.count >= 2 fails, times.first is nil => max(nil ?? 10 * 1.2, 1) = 12.0
        #expect(yMax >= 1.0)
    }

    @Test("all same values produces stable axis")
    func allSameValues() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = (0..<5).map { i in
            PingResult(sequence: i + 1, host: "h", ttl: 64, time: 15.0)
        }
        let yMax = vm.chartYAxisMax
        // P95 = 15, median = 15, max(15, 15*1.5) = 22.5, * 1.15 = 25.875
        #expect(yMax > 15.0)
    }

    @Test("all timeouts returns minimum axis value")
    func allTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = (0..<5).map { i in
            PingResult(sequence: i + 1, host: "h", ttl: 0, time: 0.0, isTimeout: true)
        }
        let yMax = vm.chartYAxisMax
        // successfulPings is empty => guard fails => max((nil ?? 10) * 1.2, 1) = 12.0
        #expect(yMax >= 1.0)
    }
}

// MARK: - successfulPings Filter Tests

@Suite("PingToolViewModel - successfulPings")
@MainActor
struct PingToolViewModelSuccessfulPingsTests {

    @Test("excludes timeout results")
    func excludesTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 10.0),
            PingResult(sequence: 2, host: "h", ttl: 0, time: 0.0, isTimeout: true),
            PingResult(sequence: 3, host: "h", ttl: 64, time: 20.0),
            PingResult(sequence: 4, host: "h", ttl: 0, time: 0.0, isTimeout: true),
        ]
        let successful = vm.successfulPings
        #expect(successful.count == 2)
        #expect(successful[0].sequence == 1)
        #expect(successful[1].sequence == 3)
    }

    @Test("returns all when none are timeouts")
    func allSuccessful() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 64, time: 10.0),
            PingResult(sequence: 2, host: "h", ttl: 64, time: 20.0),
        ]
        #expect(vm.successfulPings.count == 2)
    }

    @Test("returns empty when all are timeouts")
    func allTimeouts() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [
            PingResult(sequence: 1, host: "h", ttl: 0, time: 0.0, isTimeout: true),
            PingResult(sequence: 2, host: "h", ttl: 0, time: 0.0, isTimeout: true),
        ]
        #expect(vm.successfulPings.isEmpty)
    }

    @Test("returns empty when results are empty")
    func emptyResults() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.successfulPings.isEmpty)
    }
}

// MARK: - startPing/stopPing Lifecycle Tests

@Suite("PingToolViewModel - Ping Lifecycle", .serialized)
@MainActor
struct PingToolViewModelLifecycleTests {

    @Test("startPing processes mock results via AsyncStream")
    func startPingProcessesResults() async throws {
        let mock = MockPingService()
        mock.mockResults = [
            PingResult(sequence: 1, host: "test.com", ttl: 64, time: 10.0),
            PingResult(sequence: 2, host: "test.com", ttl: 64, time: 12.0),
            PingResult(sequence: 3, host: "test.com", ttl: 64, time: 11.0),
        ]
        mock.mockStatistics = PingStatistics(
            host: "test.com", transmitted: 3, received: 3,
            packetLoss: 0, minTime: 10, maxTime: 12, avgTime: 11
        )

        let vm = PingToolViewModel(pingService: mock)
        vm.host = "test.com"
        vm.startPing()

        // Wait for the async Task to complete
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.results.count == 3)
        #expect(vm.results[0].time == 10.0)
        #expect(vm.results[1].time == 12.0)
        #expect(vm.results[2].time == 11.0)
        #expect(vm.statistics != nil)
        #expect(vm.statistics?.avgTime == 11)
        #expect(vm.isRunning == false)
        #expect(mock.pingCallCount == 1)
    }

    @Test("stopPing cancels in-flight task and calls service stop")
    func stopPingCancelsAndCallsStop() async throws {
        let mock = MockPingService()
        let vm = PingToolViewModel(pingService: mock)
        vm.host = "192.168.1.1"
        vm.startPing()
        #expect(vm.isRunning == true)

        vm.stopPing()
        #expect(vm.isRunning == false)

        // Give time for stop() async call to execute
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.stopCallCount == 1)
    }

    @Test("startPing clears previous results before new run")
    func startPingClearsPreviousResults() async throws {
        let mock = MockPingService()
        mock.mockResults = [
            PingResult(sequence: 1, host: "new.com", ttl: 64, time: 5.0),
        ]

        let vm = PingToolViewModel(pingService: mock)
        vm.host = "new.com"

        // Pre-populate with old data
        vm.results = [PingResult(sequence: 1, host: "old.com", ttl: 64, time: 99.0)]
        vm.statistics = PingStatistics(
            host: "old.com", transmitted: 1, received: 1,
            packetLoss: 0, minTime: 99, maxTime: 99, avgTime: 99
        )
        vm.errorMessage = "old error"

        vm.startPing()

        // Synchronously cleared
        #expect(vm.errorMessage == nil)

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.results.count == 1)
        #expect(vm.results[0].host == "new.com")
    }
}

// MARK: - pingCount UserDefaults Persistence Tests

@Suite("PingToolViewModel - pingCount Persistence")
@MainActor
struct PingToolViewModelPingCountTests {

    @Test("pingCount reads from UserDefaults on init")
    func pingCountReadsFromDefaults() {
        let key = AppSettings.Keys.defaultPingCount
        UserDefaults.standard.set(50, forKey: key)
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.pingCount == 50)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("pingCount defaults to 20 when UserDefaults has no value")
    func pingCountDefaultsTo20() {
        let key = AppSettings.Keys.defaultPingCount
        UserDefaults.standard.removeObject(forKey: key)
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.pingCount == 20)
    }
}
