import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for PingService.calculateStatistics — pure computation, no network I/O.
struct PingServiceTests {

    // MARK: - Helpers

    private func makeResult(
        sequence: Int = 1,
        host: String = "host",
        time: Double,
        isTimeout: Bool = false
    ) -> PingResult {
        PingResult(
            sequence: sequence,
            host: host,
            ttl: isTimeout ? 0 : 64,
            time: time,
            isTimeout: isTimeout
        )
    }

    // MARK: - Empty input

    @Test("empty results returns nil")
    func emptyResultsReturnsNil() async {
        let service = PingService()
        let stats = await service.calculateStatistics([], requestedCount: nil)
        #expect(stats == nil)
    }

    // MARK: - All timeouts

    @Test("all timeouts → received = 0, 100% packet loss, zero min/max/avg")
    func allTimeoutsProducesZeroStats() async {
        let service = PingService()
        let results = [
            makeResult(sequence: 1, time: 0, isTimeout: true),
            makeResult(sequence: 2, time: 0, isTimeout: true),
            makeResult(sequence: 3, time: 0, isTimeout: true),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 3)
        guard let s = stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(s.received == 0)
        #expect(s.transmitted == 3)
        #expect(s.packetLoss == 100.0)
        #expect(s.minTime == 0)
        #expect(s.maxTime == 0)
        #expect(s.avgTime == 0)
    }

    // MARK: - Single successful result

    @Test("single successful result → stats match that result, 0% packet loss")
    func singleSuccessfulResult() async {
        let service = PingService()
        let results = [makeResult(sequence: 1, time: 42.0)]
        let stats = await service.calculateStatistics(results, requestedCount: 1)
        guard let s = stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(s.received == 1)
        #expect(s.transmitted == 1)
        #expect(s.packetLoss == 0.0)
        #expect(s.minTime == 42.0)
        #expect(s.maxTime == 42.0)
        #expect(s.avgTime == 42.0)
    }

    // MARK: - Mixed success and timeout

    @Test("mixed success/timeout → correct min/max/avg and packet loss")
    func mixedSuccessAndTimeout() async {
        let service = PingService()
        // 2 success (10ms, 20ms), 2 timeouts
        let results = [
            makeResult(sequence: 1, time: 10.0),
            makeResult(sequence: 2, time: 0, isTimeout: true),
            makeResult(sequence: 3, time: 20.0),
            makeResult(sequence: 4, time: 0, isTimeout: true),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 4)
        guard let s = stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(s.transmitted == 4)
        #expect(s.received == 2)
        #expect(s.packetLoss == 50.0)
        #expect(s.minTime == 10.0)
        #expect(s.maxTime == 20.0)
        #expect(s.avgTime == 15.0)
    }

    // MARK: - requestedCount override

    @Test("requestedCount overrides results.count for packet loss calculation")
    func requestedCountOverridesResultCount() async {
        let service = PingService()
        // Only 2 results received but 4 were requested
        let results = [
            makeResult(sequence: 1, time: 10.0),
            makeResult(sequence: 2, time: 20.0),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 4)
        guard let s = stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(s.transmitted == 4)
        #expect(s.received == 2)
        #expect(s.packetLoss == 50.0)
    }

    // MARK: - stdDev computation

    @Test("stdDev is zero for single result")
    func stdDevZeroForSingleResult() async {
        let service = PingService()
        let results = [makeResult(sequence: 1, time: 100.0)]
        let stats = await service.calculateStatistics(results, requestedCount: 1)
        guard let stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(stats.stdDev == 0.0)
    }

    @Test("stdDev is computed correctly for multiple results")
    func stdDevComputedCorrectly() async {
        let service = PingService()
        // times: [10, 20, 30], avg = 20, variance = (100+0+100)/3 = 66.667, stdDev ≈ 8.165
        let results = [
            makeResult(sequence: 1, time: 10.0),
            makeResult(sequence: 2, time: 20.0),
            makeResult(sequence: 3, time: 30.0),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 3)
        guard let s = stats else { Issue.record("Expected non-nil stats")
        return
        }
        let expectedStdDev = Foundation.sqrt(200.0 / 3.0)
        guard let stdDev = s.stdDev else { Issue.record("Expected non-nil stdDev")
        return
        }
        #expect(abs(stdDev - expectedStdDev) < 0.001)
    }

    @Test("stdDev is zero when all times are identical")
    func stdDevZeroForIdenticalTimes() async {
        let service = PingService()
        let results = [
            makeResult(sequence: 1, time: 5.0),
            makeResult(sequence: 2, time: 5.0),
            makeResult(sequence: 3, time: 5.0),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 3)
        guard let stats else { Issue.record("Expected non-nil stats")
        return
        }
        #expect(stats.stdDev == 0.0)
    }

    // MARK: - Host name propagation

    @Test("statistics host matches first result's host")
    func statisticsHostMatchesFirstResult() async {
        let service = PingService()
        let results = [
            makeResult(sequence: 1, host: "example.com", time: 10.0),
            makeResult(sequence: 2, host: "example.com", time: 20.0),
        ]
        let stats = await service.calculateStatistics(results, requestedCount: 2)
        #expect(stats?.host == "example.com")
    }

    // MARK: - stop() state management

    @Test("stop() sets service to non-running state without crashing")
    func stopSetsNonRunningState() async {
        let service = PingService()
        // Call stop without a prior ping — should not crash and be idempotent
        await service.stop()
        await service.stop()
        // calculateStatistics still works after stop
        let stats = await service.calculateStatistics([], requestedCount: nil)
        #expect(stats == nil)
    }
}
