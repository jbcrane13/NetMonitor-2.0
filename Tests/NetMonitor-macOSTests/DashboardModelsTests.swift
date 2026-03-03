import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - LatencyStats Basic Stats

@Suite("LatencyStats – basic stats")
struct LatencyStatsBasicTests {

    @Test func emptyArrayYieldsNilAvg() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.avg == nil)
    }

    @Test func emptyArrayYieldsNilMin() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.min == nil)
    }

    @Test func emptyArrayYieldsNilMax() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.max == nil)
    }

    @Test func emptyArrayYieldsNilJitter() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.jitter == nil)
    }

    @Test func singleValueAvgEqualsValue() {
        let stats = LatencyStats(latencies: [42.0])
        #expect(stats.avg == 42.0)
    }

    @Test func singleValueMinEqualsValue() {
        let stats = LatencyStats(latencies: [42.0])
        #expect(stats.min == 42.0)
    }

    @Test func singleValueMaxEqualsValue() {
        let stats = LatencyStats(latencies: [42.0])
        #expect(stats.max == 42.0)
    }

    @Test func singleValueJitterIsNilBecauseCountIsOne() {
        let stats = LatencyStats(latencies: [42.0])
        // jitter requires count > 1
        #expect(stats.jitter == nil)
    }

    @Test func avgIsCorrectMeanOfKnownValues() {
        // mean of [10, 20, 30] = 20
        let stats = LatencyStats(latencies: [10.0, 20.0, 30.0])
        #expect(stats.avg == 20.0)
    }

    @Test func avgIsCorrectForUnevenSpread() {
        // mean of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] = 5.5
        let values = (1...10).map(Double.init)
        let stats = LatencyStats(latencies: values)
        #expect(stats.avg == 5.5)
    }

    @Test func minPicksSmallestValue() {
        let stats = LatencyStats(latencies: [50.0, 3.0, 200.0, 1.0, 100.0])
        #expect(stats.min == 1.0)
    }

    @Test func maxPicksLargestValue() {
        let stats = LatencyStats(latencies: [50.0, 3.0, 200.0, 1.0, 100.0])
        #expect(stats.max == 200.0)
    }

    @Test func jitterIsPopulationStdDevOfTwoValues() {
        // [4.0, 8.0]: avg=6, variance=((4-6)^2 + (8-6)^2)/2 = (4+4)/2 = 4, stdDev=2.0
        let stats = LatencyStats(latencies: [4.0, 8.0])
        #expect(stats.jitter == 2.0)
    }

    @Test func jitterOfThreeEqualValuesIsZero() {
        let stats = LatencyStats(latencies: [10.0, 10.0, 10.0])
        #expect(stats.jitter == 0.0)
    }

    @Test func jitterOfThreeKnownValues() {
        // [0, 6, 12]: avg=6, variance=((0-6)^2+(6-6)^2+(12-6)^2)/3 = (36+0+36)/3 = 24, stdDev=sqrt(24)
        let stats = LatencyStats(latencies: [0.0, 6.0, 12.0])
        let expected = sqrt(24.0)
        let actual = stats.jitter ?? -1
        #expect(abs(actual - expected) < 0.0001)
    }
}

// MARK: - LatencyStats Histogram Buckets

@Suite("LatencyStats – histogram buckets")
struct LatencyStatsHistogramTests {

    @Test func allUnder5msGoesToUnder5Bucket() {
        let stats = LatencyStats(latencies: [1.0, 2.0, 3.0, 4.0])
        let buckets = stats.histogramBuckets
        #expect(buckets.under5ms == 4)
        #expect(buckets.ms5to20 == 0)
        #expect(buckets.ms20to50 == 0)
        #expect(buckets.over50ms == 0)
    }

    @Test func allOver50msGoesToOver50Bucket() {
        let stats = LatencyStats(latencies: [51.0, 100.0, 200.0])
        let buckets = stats.histogramBuckets
        #expect(buckets.under5ms == 0)
        #expect(buckets.ms5to20 == 0)
        #expect(buckets.ms20to50 == 0)
        #expect(buckets.over50ms == 3)
    }

    @Test func spreadAcrossAllFourBuckets() {
        // 2 under5ms, 3 in 5-20, 1 in 20-50, 2 over50ms
        let stats = LatencyStats(latencies: [1.0, 4.0, 5.0, 10.0, 19.0, 25.0, 51.0, 100.0])
        let buckets = stats.histogramBuckets
        #expect(buckets.under5ms == 2)
        #expect(buckets.ms5to20 == 3)
        #expect(buckets.ms20to50 == 1)
        #expect(buckets.over50ms == 2)
    }

    @Test func totalEqualsCountOfAllInputValues() {
        let latencies = [1.0, 5.0, 20.0, 50.0, 75.0]
        let stats = LatencyStats(latencies: latencies)
        let buckets = stats.histogramBuckets
        #expect(buckets.total == latencies.count)
    }

    @Test func totalOfEmptyArrayIsZero() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.histogramBuckets.total == 0)
    }

    // MARK: Boundary Values

    // Buckets: ..<5, 5..<20, 20..<50, default(>=50)
    // Parameterized boundary test: (value, expectedBucket) where bucket index 0=under5, 1=5to20, 2=20to50, 3=over50
    @Test(arguments: zip(
        [4.999, 5.0, 19.999, 20.0, 49.999, 50.0],
        [0, 1, 1, 2, 2, 3] // expected bucket index: 0=under5, 1=5to20, 2=20to50, 3=over50
    ))
    func boundaryValuesRoutedCorrectly(value: Double, expectedBucketIndex: Int) {
        let stats = LatencyStats(latencies: [value])
        let buckets = stats.histogramBuckets
        let counts = [buckets.under5ms, buckets.ms5to20, buckets.ms20to50, buckets.over50ms]
        for (i, count) in counts.enumerated() {
            if i == expectedBucketIndex {
                #expect(count == 1, "Expected value \(value) in bucket \(i) but got \(count)")
            } else {
                #expect(count == 0, "Expected bucket \(i) to be 0 for value \(value) but got \(count)")
            }
        }
    }
}

// MARK: - LatencyStats normalizedHeights

@Suite("LatencyStats – normalizedHeights")
struct LatencyStatsNormalizedHeightsTests {

    @Test func emptyInputAllHeightsAreZero() {
        let stats = LatencyStats(latencies: [])
        let buckets = stats.histogramBuckets
        let heights = buckets.normalizedHeights
        #expect(heights.count == 4)
        for height in heights {
            #expect(height == 0.0)
        }
    }

    @Test func peakBucketNormalizedToOne() {
        // All in under5ms → that bucket is the peak → height 1.0
        let stats = LatencyStats(latencies: [1.0, 2.0, 3.0])
        let heights = stats.histogramBuckets.normalizedHeights
        #expect(heights[0] == 1.0)
    }

    @Test func zeroBucketsNormalizedToZero() {
        // Only values in under5ms, other buckets must be 0.0
        let stats = LatencyStats(latencies: [1.0, 2.0])
        let heights = stats.histogramBuckets.normalizedHeights
        #expect(heights[1] == 0.0)
        #expect(heights[2] == 0.0)
        #expect(heights[3] == 0.0)
    }

    @Test func allEqualCountsYieldAllHeightsOfOne() {
        // One value in each bucket → all heights 1.0
        let stats = LatencyStats(latencies: [2.0, 10.0, 30.0, 60.0])
        let heights = stats.histogramBuckets.normalizedHeights
        for height in heights {
            #expect(height == 1.0)
        }
    }

    @Test func heightsAreInZeroToOneRange() {
        let stats = LatencyStats(latencies: [1.0, 2.0, 3.0, 4.0, 10.0, 30.0, 60.0])
        let heights = stats.histogramBuckets.normalizedHeights
        for height in heights {
            #expect(height >= 0.0)
            #expect(height <= 1.0)
        }
    }

    @Test func peakIsOneAndOtherHeightsAreProportional() {
        // under5ms: 4, ms5to20: 2, ms20to50: 1, over50ms: 0
        let stats = LatencyStats(latencies: [1.0, 2.0, 3.0, 4.0, 10.0, 15.0, 30.0])
        let heights = stats.histogramBuckets.normalizedHeights
        // Peak = under5ms (4 items) → normalized to 1.0
        #expect(heights[0] == 1.0)
        // ms5to20 has 2 items → 2/4 = 0.5
        #expect(abs(heights[1] - 0.5) < 0.0001)
        // ms20to50 has 1 item → 1/4 = 0.25
        #expect(abs(heights[2] - 0.25) < 0.0001)
        // over50ms has 0 items → 0.0
        #expect(heights[3] == 0.0)
    }
}
