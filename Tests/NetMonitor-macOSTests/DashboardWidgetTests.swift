import Testing
import Foundation
@testable import NetMonitor_macOS

@Suite("LatencyStats")
struct LatencyStatsTests {

    @Test func emptyLatenciesHaveNilStats() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.avg == nil)
        #expect(stats.min == nil)
        #expect(stats.max == nil)
        #expect(stats.jitter == nil)
    }

    @Test func singleValueHasCorrectStats() {
        let stats = LatencyStats(latencies: [5.0])
        #expect(stats.avg == 5.0)
        #expect(stats.min == 5.0)
        #expect(stats.max == 5.0)
        #expect(stats.jitter == nil)  // needs >1 value
    }

    @Test func multipleValuesComputeCorrectAvg() {
        let stats = LatencyStats(latencies: [2.0, 4.0, 6.0])
        #expect(stats.avg == 4.0)
        #expect(stats.min == 2.0)
        #expect(stats.max == 6.0)
    }

    @Test func jitterIsStdDevOfLatencies() {
        // [2,4,6]: mean=4, deviations=[4,0,4], variance=8/3, stddev≈1.633
        let stats = LatencyStats(latencies: [2.0, 4.0, 6.0])
        let expected = sqrt(8.0 / 3.0)
        #expect(abs((stats.jitter ?? 0) - expected) < 0.001)
    }

    @Test func histogramBucketsCountCorrectly() {
        let latencies: [Double] = [1, 3, 8, 15, 25, 60, 100]
        let stats = LatencyStats(latencies: latencies)
        let buckets = stats.histogramBuckets
        #expect(buckets.under5ms == 2)    // 1, 3
        #expect(buckets.ms5to20 == 2)     // 8, 15
        #expect(buckets.ms20to50 == 1)    // 25
        #expect(buckets.over50ms == 2)    // 60, 100
    }

    @Test func histogramBucketHeightsNormalizeToOne() {
        let latencies: [Double] = [1, 8, 25, 60]
        let stats = LatencyStats(latencies: latencies)
        let heights = stats.histogramBuckets.normalizedHeights
        #expect(heights.max() ?? 0 == 1.0)
        #expect(heights.min() ?? 0 >= 0.0)
    }
}
