//
//  StatisticsService.swift
//  NetMonitor
//
//  Created by Claude on 2026-01-28.
//

import Foundation

/// Time window for statistics calculation
enum StatisticsWindow: String, Sendable, CaseIterable {
    case twoMinutes = "2min"
    case tenMinutes = "10min"
    case allTime = "all"

    var timeInterval: TimeInterval? {
        switch self {
        case .twoMinutes: return 120
        case .tenMinutes: return 600
        case .allTime: return nil  // No limit
        }
    }

    var displayName: String {
        switch self {
        case .twoMinutes: return "Last 2 Minutes"
        case .tenMinutes: return "Last 10 Minutes"
        case .allTime: return "All Time"
        }
    }
}

/// Statistics for a single target within a time window
struct TargetStatistics: Sendable {
    let targetID: UUID
    let targetName: String
    let window: StatisticsWindow
    let averageLatency: Double?
    let minLatency: Double?
    let maxLatency: Double?
    let uptimePercentage: Double  // 0.0 to 100.0
    let totalChecks: Int
    let failedChecks: Int
    let calculatedAt: Date

    var successfulChecks: Int {
        totalChecks - failedChecks
    }
}

/// Aggregated statistics across all targets
struct OverallStatistics: Sendable {
    let window: StatisticsWindow
    let averageLatency: Double?
    let averageUptime: Double
    let totalTargets: Int
    let onlineTargets: Int
    let offlineTargets: Int
    let calculatedAt: Date
}

/// Actor-based service for calculating monitoring statistics
actor StatisticsService {

    // MARK: - Single Target Statistics

    /// Calculate statistics for a specific target and time window
    /// - Parameters:
    ///   - targetID: UUID of the target
    ///   - targetName: Display name of the target
    ///   - measurements: Array of measurements to analyze
    ///   - window: Time window for filtering measurements
    /// - Returns: Calculated statistics for the target
    func calculate(
        for targetID: UUID,
        targetName: String,
        measurements: [TargetMeasurement],
        window: StatisticsWindow
    ) -> TargetStatistics {
        let now = Date()

        // Filter measurements by time window
        let filtered: [TargetMeasurement]
        if let interval = window.timeInterval {
            let cutoff = now.addingTimeInterval(-interval)
            filtered = measurements.filter { $0.timestamp >= cutoff }
        } else {
            filtered = measurements
        }

        // Calculate latency statistics
        let latencies = filtered.compactMap { $0.latency }
        let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min()
        let maxLatency = latencies.max()

        // Calculate uptime
        let totalChecks = filtered.count
        let successfulChecks = filtered.filter { $0.isReachable }.count
        let failedChecks = totalChecks - successfulChecks
        let uptime = totalChecks > 0 ? (Double(successfulChecks) / Double(totalChecks)) * 100.0 : 0.0

        return TargetStatistics(
            targetID: targetID,
            targetName: targetName,
            window: window,
            averageLatency: avgLatency,
            minLatency: minLatency,
            maxLatency: maxLatency,
            uptimePercentage: uptime,
            totalChecks: totalChecks,
            failedChecks: failedChecks,
            calculatedAt: now
        )
    }

    // MARK: - Batch Calculations

    /// Calculate statistics for all targets across all time windows
    /// - Parameter targets: Array of (id, name, measurements) tuples
    /// - Returns: Dictionary mapping target ID to window statistics
    func calculateAll(
        targets: [(id: UUID, name: String, measurements: [TargetMeasurement])]
    ) -> [UUID: [StatisticsWindow: TargetStatistics]] {
        var result: [UUID: [StatisticsWindow: TargetStatistics]] = [:]

        for target in targets {
            var windowStats: [StatisticsWindow: TargetStatistics] = [:]

            for window in StatisticsWindow.allCases {
                let stats = calculate(
                    for: target.id,
                    targetName: target.name,
                    measurements: target.measurements,
                    window: window
                )
                windowStats[window] = stats
            }

            result[target.id] = windowStats
        }

        return result
    }

    // MARK: - Aggregate Statistics

    /// Get aggregated statistics across all targets for a specific window
    /// - Parameters:
    ///   - allStats: Dictionary of all target statistics
    ///   - window: Time window to aggregate
    /// - Returns: Overall statistics across all targets
    func aggregateOverall(
        allStats: [UUID: [StatisticsWindow: TargetStatistics]],
        window: StatisticsWindow
    ) -> OverallStatistics {
        let now = Date()

        // Extract statistics for this window
        let windowStats = allStats.values.compactMap { $0[window] }

        // Calculate average latency
        let latencies = windowStats.compactMap { $0.averageLatency }
        let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        // Calculate average uptime
        let uptimes = windowStats.map { $0.uptimePercentage }
        let avgUptime = uptimes.isEmpty ? 0.0 : uptimes.reduce(0, +) / Double(uptimes.count)

        // Count online/offline targets
        let totalTargets = windowStats.count
        let onlineTargets = windowStats.filter { $0.uptimePercentage > 0 }.count
        let offlineTargets = totalTargets - onlineTargets

        return OverallStatistics(
            window: window,
            averageLatency: avgLatency,
            averageUptime: avgUptime,
            totalTargets: totalTargets,
            onlineTargets: onlineTargets,
            offlineTargets: offlineTargets,
            calculatedAt: now
        )
    }

    // MARK: - Convenience Methods

    /// Calculate statistics for a single target across all windows
    /// - Parameters:
    ///   - targetID: UUID of the target
    ///   - targetName: Display name of the target
    ///   - measurements: Array of measurements to analyze
    /// - Returns: Dictionary mapping window to statistics
    func calculateWindows(
        for targetID: UUID,
        targetName: String,
        measurements: [TargetMeasurement]
    ) -> [StatisticsWindow: TargetStatistics] {
        var result: [StatisticsWindow: TargetStatistics] = [:]

        for window in StatisticsWindow.allCases {
            result[window] = calculate(
                for: targetID,
                targetName: targetName,
                measurements: measurements,
                window: window
            )
        }

        return result
    }
}
