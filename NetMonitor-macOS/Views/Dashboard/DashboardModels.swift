import Foundation

// MARK: - LatencyStats

/// Computes summary statistics and histogram buckets from an array of latency measurements.
/// Pure value type — no SwiftUI/UIKit dependencies, fully testable.
struct LatencyStats {
    let latencies: [Double]

    // MARK: Basic stats

    var avg: Double? {
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var min: Double? { latencies.min() }
    var max: Double? { latencies.max() }

    /// Population standard deviation of latency values (jitter proxy).
    var jitter: Double? {
        guard let a = avg, latencies.count > 1 else { return nil }
        let variance = latencies.map { pow($0 - a, 2) }.reduce(0, +) / Double(latencies.count)
        return sqrt(variance)
    }

    // MARK: Histogram

    // periphery:ignore
    struct HistogramBuckets {
        let under5ms:  Int
        let ms5to20:   Int
        let ms20to50:  Int
        let over50ms:  Int

        var total: Int { under5ms + ms5to20 + ms20to50 + over50ms }

        /// Heights normalized 0–1 relative to the tallest bucket. Order: [<5, 5-20, 20-50, >50].
        var normalizedHeights: [Double] {
            let counts = [under5ms, ms5to20, ms20to50, over50ms].map(Double.init)
            let peak = counts.max() ?? 1
            guard peak > 0 else { return [0, 0, 0, 0] }
            return counts.map { $0 / peak }
        }
    }

    // periphery:ignore
    var histogramBuckets: HistogramBuckets {
        var u5 = 0, s5 = 0, s20 = 0, o50 = 0
        for l in latencies {
            switch l {
            case ..<5:    u5  += 1
            case 5..<20:  s5  += 1
            case 20..<50: s20 += 1
            default:      o50 += 1
            }
        }
        return HistogramBuckets(under5ms: u5, ms5to20: s5, ms20to50: s20, over50ms: o50)
    }
}
