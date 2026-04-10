import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - StatisticsWindow Tests

struct StatisticsWindowTests {

    @Test func twoMinutesTimeInterval() {
        #expect(StatisticsWindow.twoMinutes.timeInterval == 120)
    }

    @Test func tenMinutesTimeInterval() {
        #expect(StatisticsWindow.tenMinutes.timeInterval == 600)
    }

    @Test func allTimeIntervalIsNil() {
        #expect(StatisticsWindow.allTime.timeInterval == nil)
    }

    @Test func twoMinutesDisplayName() {
        #expect(StatisticsWindow.twoMinutes.displayName == "Last 2 Minutes")
    }

    @Test func tenMinutesDisplayName() {
        #expect(StatisticsWindow.tenMinutes.displayName == "Last 10 Minutes")
    }

    @Test func allTimeDisplayName() {
        #expect(StatisticsWindow.allTime.displayName == "All Time")
    }

    @Test func allCasesCountIsThree() {
        #expect(StatisticsWindow.allCases.count == 3)
    }

    @Test func rawValues() {
        #expect(StatisticsWindow.twoMinutes.rawValue == "2min")
        #expect(StatisticsWindow.tenMinutes.rawValue == "10min")
        #expect(StatisticsWindow.allTime.rawValue == "all")
    }
}

// MARK: - TargetStatistics Tests

struct TargetStatisticsTests {

    @Test func successfulChecksIsTotal_minus_failed() {
        let stats = TargetStatistics(
            targetID: UUID(),
            targetName: "Test",
            window: .allTime,
            averageLatency: nil,
            minLatency: nil,
            maxLatency: nil,
            uptimePercentage: 70.0,
            totalChecks: 10,
            failedChecks: 3,
            calculatedAt: Date()
        )
        #expect(stats.successfulChecks == 7)
    }

    @Test func successfulChecksZeroFailed() {
        let stats = TargetStatistics(
            targetID: UUID(),
            targetName: "Test",
            window: .allTime,
            averageLatency: 10.0,
            minLatency: 5.0,
            maxLatency: 20.0,
            uptimePercentage: 100.0,
            totalChecks: 5,
            failedChecks: 0,
            calculatedAt: Date()
        )
        #expect(stats.successfulChecks == 5)
    }

    @Test func successfulChecksAllFailed() {
        let stats = TargetStatistics(
            targetID: UUID(),
            targetName: "Test",
            window: .allTime,
            averageLatency: nil,
            minLatency: nil,
            maxLatency: nil,
            uptimePercentage: 0.0,
            totalChecks: 4,
            failedChecks: 4,
            calculatedAt: Date()
        )
        #expect(stats.successfulChecks == 0)
    }
}

// MARK: - StatisticsService Tests

struct StatisticsServiceTests {

    let service = StatisticsService()
    let targetID = UUID()

    @Test func emptyMeasurementsYieldsZeroUptime() async {
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: [],
            window: .allTime
        )
        #expect(stats.uptimePercentage == 0.0)
        #expect(stats.totalChecks == 0)
        #expect(stats.failedChecks == 0)
        #expect(stats.successfulChecks == 0)
        #expect(stats.averageLatency == nil)
        #expect(stats.minLatency == nil)
        #expect(stats.maxLatency == nil)
    }

    @Test func targetMetadataPreserved() async {
        let id = UUID()
        let stats = await service.calculate(
            for: id,
            targetName: "My Target",
            measurements: [],
            window: .twoMinutes
        )
        #expect(stats.targetID == id)
        #expect(stats.targetName == "My Target")
        #expect(stats.window == .twoMinutes)
    }

    @Test func allReachableGives100PercentUptime() async {
        let measurements = [
            TargetMeasurement(latency: 10.0, isReachable: true),
            TargetMeasurement(latency: 20.0, isReachable: true),
            TargetMeasurement(latency: 30.0, isReachable: true),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.uptimePercentage == 100.0)
        #expect(stats.totalChecks == 3)
        #expect(stats.failedChecks == 0)
        #expect(stats.averageLatency == 20.0)
        #expect(stats.minLatency == 10.0)
        #expect(stats.maxLatency == 30.0)
    }

    @Test func allUnreachableGivesZeroUptimeAndNoLatency() async {
        let measurements = [
            TargetMeasurement(isReachable: false),
            TargetMeasurement(isReachable: false),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.uptimePercentage == 0.0)
        #expect(stats.totalChecks == 2)
        #expect(stats.failedChecks == 2)
        #expect(stats.averageLatency == nil)
    }

    @Test func mixedReachabilityGivesHalfUptime() async {
        let measurements = [
            TargetMeasurement(latency: 10.0, isReachable: true),
            TargetMeasurement(isReachable: false),
            TargetMeasurement(latency: 20.0, isReachable: true),
            TargetMeasurement(isReachable: false),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.uptimePercentage == 50.0)
        #expect(stats.totalChecks == 4)
        #expect(stats.failedChecks == 2)
        #expect(stats.averageLatency == 15.0)
    }

    @Test func twoMinuteWindowFiltersOldMeasurements() async {
        let now = Date()
        let old = now.addingTimeInterval(-200)    // outside 2-minute window
        let recent = now.addingTimeInterval(-60)  // inside 2-minute window
        let measurements = [
            TargetMeasurement(timestamp: old, latency: 100.0, isReachable: true),
            TargetMeasurement(timestamp: recent, latency: 20.0, isReachable: true),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .twoMinutes
        )
        #expect(stats.totalChecks == 1)
        #expect(stats.averageLatency == 20.0)
    }

    @Test func tenMinuteWindowFiltersVeryOldMeasurements() async {
        let now = Date()
        let tooOld = now.addingTimeInterval(-700)   // outside 10-minute window
        let ok = now.addingTimeInterval(-300)        // inside 10-minute window
        let measurements = [
            TargetMeasurement(timestamp: tooOld, latency: 50.0, isReachable: true),
            TargetMeasurement(timestamp: ok, latency: 10.0, isReachable: true),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .tenMinutes
        )
        #expect(stats.totalChecks == 1)
        #expect(stats.averageLatency == 10.0)
    }

    @Test func allTimeWindowIncludesAllMeasurements() async {
        let now = Date()
        let veryOld = now.addingTimeInterval(-86400)  // 1 day ago
        let measurements = [
            TargetMeasurement(timestamp: veryOld, latency: 50.0, isReachable: true),
            TargetMeasurement(latency: 10.0, isReachable: true),
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.totalChecks == 2)
        #expect(stats.averageLatency == 30.0)
    }

    @Test func calculateWindowsReturnsAllThreeWindows() async {
        let measurements = [TargetMeasurement(latency: 10.0, isReachable: true)]
        let windows = await service.calculateWindows(
            for: targetID,
            targetName: "Test",
            measurements: measurements
        )
        #expect(windows.count == 3)
        #expect(windows[.twoMinutes] != nil)
        #expect(windows[.tenMinutes] != nil)
        #expect(windows[.allTime] != nil)
    }

    @Test func calculateAllReturnsResultForEachTarget() async {
        let id1 = UUID()
        let id2 = UUID()
        let targets: [(id: UUID, name: String, measurements: [TargetMeasurement])] = [
            (id: id1, name: "T1", measurements: [TargetMeasurement(latency: 10.0, isReachable: true)]),
            (id: id2, name: "T2", measurements: [TargetMeasurement(isReachable: false)]),
        ]
        let allStats = await service.calculateAll(targets: targets)
        #expect(allStats.count == 2)
        #expect(allStats[id1] != nil)
        #expect(allStats[id2] != nil)
    }

    @Test func calculateAllWindowStatsPerTarget() async {
        let id = UUID()
        let targets: [(id: UUID, name: String, measurements: [TargetMeasurement])] = [
            (id: id, name: "T1", measurements: [TargetMeasurement(latency: 5.0, isReachable: true)]),
        ]
        let allStats = await service.calculateAll(targets: targets)
        let windowStats = allStats[id]
        #expect(windowStats?.count == 3)
        #expect(windowStats?[.allTime] != nil)
    }

    @Test func aggregateOverallAveragesLatency() async {
        let id1 = UUID()
        let id2 = UUID()
        let allStats: [UUID: [StatisticsWindow: TargetStatistics]] = [
            id1: [.allTime: TargetStatistics(
                targetID: id1, targetName: "T1", window: .allTime,
                averageLatency: 10.0, minLatency: 5.0, maxLatency: 20.0,
                uptimePercentage: 100.0, totalChecks: 1, failedChecks: 0, calculatedAt: Date()
            )],
            id2: [.allTime: TargetStatistics(
                targetID: id2, targetName: "T2", window: .allTime,
                averageLatency: 30.0, minLatency: 25.0, maxLatency: 40.0,
                uptimePercentage: 100.0, totalChecks: 1, failedChecks: 0, calculatedAt: Date()
            )],
        ]
        let overall = await service.aggregateOverall(allStats: allStats, window: .allTime)
        #expect(overall.averageLatency == 20.0)
        #expect(overall.totalTargets == 2)
        #expect(overall.onlineTargets == 2)
        #expect(overall.offlineTargets == 0)
    }

    @Test func aggregateOverallEmptyStatsYieldsZeros() async {
        let overall = await service.aggregateOverall(allStats: [:], window: .allTime)
        #expect(overall.averageLatency == nil)
        #expect(overall.averageUptime == 0.0)
        #expect(overall.totalTargets == 0)
        #expect(overall.onlineTargets == 0)
        #expect(overall.offlineTargets == 0)
    }

    @Test func aggregateOverallOfflineTargetIsTargetWithZeroUptime() async {
        let id = UUID()
        let allStats: [UUID: [StatisticsWindow: TargetStatistics]] = [
            id: [.allTime: TargetStatistics(
                targetID: id, targetName: "Down", window: .allTime,
                averageLatency: nil, minLatency: nil, maxLatency: nil,
                uptimePercentage: 0.0, totalChecks: 3, failedChecks: 3, calculatedAt: Date()
            )],
        ]
        let overall = await service.aggregateOverall(allStats: allStats, window: .allTime)
        #expect(overall.totalTargets == 1)
        #expect(overall.onlineTargets == 0)
        #expect(overall.offlineTargets == 1)
    }
}

// MARK: - StatisticsService Extended Tests

struct StatisticsServiceExtendedTests {

    let service = StatisticsService()
    let targetID = UUID()

    // MARK: - Metric Aggregation Over Time Window

    @Test func latencyAggregationIgnoresOutOfWindowMeasurements() async {
        let now = Date()
        // One measurement inside the 2-min window, one outside
        let inWindow = TargetMeasurement(timestamp: now.addingTimeInterval(-60), latency: 20.0, isReachable: true)
        let outOfWindow = TargetMeasurement(timestamp: now.addingTimeInterval(-300), latency: 200.0, isReachable: true)

        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: [inWindow, outOfWindow],
            window: .twoMinutes
        )
        #expect(stats.totalChecks == 1)
        #expect(stats.averageLatency == 20.0)
        #expect(stats.minLatency == 20.0)
        #expect(stats.maxLatency == 20.0)
    }

    @Test func latencyMinAndMaxAreCorrectOverWindow() async {
        let now = Date()
        let measurements = [
            TargetMeasurement(timestamp: now.addingTimeInterval(-30), latency: 5.0, isReachable: true),
            TargetMeasurement(timestamp: now.addingTimeInterval(-60), latency: 95.0, isReachable: true),
            TargetMeasurement(timestamp: now.addingTimeInterval(-90), latency: 50.0, isReachable: true),
        ]

        let stats = await service.calculate(
            for: targetID,
            targetName: "Test",
            measurements: measurements,
            window: .twoMinutes
        )
        #expect(stats.totalChecks == 3)
        #expect(stats.minLatency == 5.0)
        #expect(stats.maxLatency == 95.0)
        #expect(abs((stats.averageLatency ?? 0) - 50.0) < 0.001)
    }

    // MARK: - Empty Data → Zero Metrics

    @Test func emptyDataYieldsZeroTotalChecks() async {
        let stats = await service.calculate(
            for: targetID,
            targetName: "Empty",
            measurements: [],
            window: .twoMinutes
        )
        #expect(stats.totalChecks == 0)
        #expect(stats.failedChecks == 0)
        #expect(stats.successfulChecks == 0)
    }

    @Test func emptyDataYieldsZeroUptimeAndNilLatency() async {
        let stats = await service.calculate(
            for: targetID,
            targetName: "Empty",
            measurements: [],
            window: .allTime
        )
        #expect(stats.uptimePercentage == 0.0)
        #expect(stats.averageLatency == nil)
        #expect(stats.minLatency == nil)
        #expect(stats.maxLatency == nil)
    }

    // MARK: - Data Point Accuracy

    @Test func singleMeasurementLatencyIsExact() async {
        let measurements = [TargetMeasurement(latency: 42.5, isReachable: true)]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Precise",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.averageLatency == 42.5)
        #expect(stats.minLatency == 42.5)
        #expect(stats.maxLatency == 42.5)
        #expect(stats.uptimePercentage == 100.0)
    }

    @Test func unreachableMeasurementExcludedFromLatencyButCountedInTotal() async {
        let measurements = [
            TargetMeasurement(latency: 10.0, isReachable: true),
            TargetMeasurement(isReachable: false),   // no latency
        ]
        let stats = await service.calculate(
            for: targetID,
            targetName: "Mixed",
            measurements: measurements,
            window: .allTime
        )
        #expect(stats.totalChecks == 2)
        #expect(stats.failedChecks == 1)
        #expect(stats.successfulChecks == 1)
        // Only the reachable measurement contributes to latency
        #expect(stats.averageLatency == 10.0)
    }
}
