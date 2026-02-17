import Foundation
import SwiftData

// MARK: - TargetMeasurement

/// Measurement result from a single network target check.
///
/// NOTE: @Model generates an unavailable Sendable extension; cross-actor access
/// should use `persistentModelID` to avoid data races.
@Model
public final class TargetMeasurement {
    public var id: UUID
    public var timestamp: Date
    public var latency: Double?
    public var isReachable: Bool
    public var errorMessage: String?

    public var target: NetworkTarget?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        latency: Double? = nil,
        isReachable: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latency = latency
        self.isReachable = isReachable
        self.errorMessage = errorMessage
    }
}

// MARK: - MeasurementStatistics

/// Aggregated statistics derived from a collection of TargetMeasurements.
public struct MeasurementStatistics: Sendable {
    public let averageLatency: Double?
    public let minLatency: Double?
    public let maxLatency: Double?
    public let uptimePercentage: Double?

    public init(
        averageLatency: Double?,
        minLatency: Double?,
        maxLatency: Double?,
        uptimePercentage: Double?
    ) {
        self.averageLatency = averageLatency
        self.minLatency = minLatency
        self.maxLatency = maxLatency
        self.uptimePercentage = uptimePercentage
    }

    public var averageLatencyFormatted: String {
        guard let avg = averageLatency else { return "—" }
        return String(format: "%.0f", avg)
    }

    public var minLatencyFormatted: String {
        guard let min = minLatency else { return "—" }
        return String(format: "%.0f", min)
    }

    public var maxLatencyFormatted: String {
        guard let max = maxLatency else { return "—" }
        return String(format: "%.0f", max)
    }

    public var uptimeFormatted: String {
        guard let uptime = uptimePercentage else { return "—" }
        return String(format: "%.1f", uptime)
    }
}

// MARK: - Statistics Calculation

extension TargetMeasurement {
    /// Calculates aggregate statistics from an array of measurements.
    public static func calculateStatistics(from measurements: [TargetMeasurement]) -> MeasurementStatistics {
        guard !measurements.isEmpty else {
            return MeasurementStatistics(
                averageLatency: nil,
                minLatency: nil,
                maxLatency: nil,
                uptimePercentage: nil
            )
        }

        let latencies = measurements.compactMap { $0.latency }
        let avgLatency: Double? = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
        let minLat: Double? = latencies.min()
        let maxLat: Double? = latencies.max()

        let reachableCount = measurements.filter { $0.isReachable }.count
        let uptime = (Double(reachableCount) / Double(measurements.count)) * 100

        return MeasurementStatistics(
            averageLatency: avgLatency,
            minLatency: minLat,
            maxLatency: maxLat,
            uptimePercentage: uptime
        )
    }
}
