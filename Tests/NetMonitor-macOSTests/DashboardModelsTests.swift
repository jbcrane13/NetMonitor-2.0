import Testing
import Foundation
import SwiftUI
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - LatencyStats Extended Tests

@Suite("LatencyStats – extended")
struct LatencyStatsExtendedTests {

    // MARK: avg

    @Test func avgWithKnownValues() {
        let stats = LatencyStats(latencies: [10.0, 20.0, 30.0, 40.0])
        #expect(stats.avg == 25.0)
    }

    @Test func avgWithIdenticalValues() {
        let stats = LatencyStats(latencies: [7.5, 7.5, 7.5])
        #expect(stats.avg == 7.5)
    }

    @Test func avgWithSingleValue() {
        let stats = LatencyStats(latencies: [42.0])
        #expect(stats.avg == 42.0)
    }

    // MARK: min / max

    @Test func minAndMaxWithDecimalValues() {
        let stats = LatencyStats(latencies: [3.14, 1.41, 2.72, 0.58])
        #expect(stats.min == 0.58)
        #expect(stats.max == 3.14)
    }

    @Test func minAndMaxWhenAllSame() {
        let stats = LatencyStats(latencies: [5.0, 5.0, 5.0])
        #expect(stats.min == 5.0)
        #expect(stats.max == 5.0)
    }

    // MARK: jitter

    @Test func jitterIsZeroWhenAllIdentical() {
        let stats = LatencyStats(latencies: [10.0, 10.0, 10.0, 10.0])
        #expect(stats.jitter == 0.0)
    }

    @Test func jitterComputesPopulationStdDev() {
        // [10, 20]: mean=15, deviations=[25,25], variance=25, stddev=5
        let stats = LatencyStats(latencies: [10.0, 20.0])
        #expect(abs((stats.jitter ?? -1) - 5.0) < 0.001)
    }

    @Test func jitterNilForSingleValue() {
        let stats = LatencyStats(latencies: [100.0])
        #expect(stats.jitter == nil)
    }

    // MARK: Empty returns nil

    @Test func emptyReturnsNilForAllStats() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.avg == nil)
        #expect(stats.min == nil)
        #expect(stats.max == nil)
        #expect(stats.jitter == nil)
    }
}

// MARK: - HistogramBuckets Tests

@Suite("LatencyStats.HistogramBuckets")
struct HistogramBucketsTests {

    @Test func allValuesUnder5ms() {
        let stats = LatencyStats(latencies: [0.5, 1.0, 2.5, 3.0, 4.9])
        let b = stats.histogramBuckets
        #expect(b.under5ms == 5)
        #expect(b.ms5to20 == 0)
        #expect(b.ms20to50 == 0)
        #expect(b.over50ms == 0)
        #expect(b.total == 5)
    }

    @Test func allValuesOver50ms() {
        let stats = LatencyStats(latencies: [50.0, 100.0, 200.0])
        let b = stats.histogramBuckets
        #expect(b.under5ms == 0)
        #expect(b.ms5to20 == 0)
        #expect(b.ms20to50 == 0)
        #expect(b.over50ms == 3)
        #expect(b.total == 3)
    }

    @Test func boundaryValues() {
        // Exact boundaries: 5 goes to 5-20, 20 goes to 20-50, 50 goes to >50
        let stats = LatencyStats(latencies: [4.999, 5.0, 19.999, 20.0, 49.999, 50.0])
        let b = stats.histogramBuckets
        #expect(b.under5ms == 1)   // 4.999
        #expect(b.ms5to20 == 2)    // 5.0, 19.999
        #expect(b.ms20to50 == 2)   // 20.0, 49.999
        #expect(b.over50ms == 1)   // 50.0
    }

    @Test func totalEqualsInputCount() {
        let latencies = [1.0, 6.0, 25.0, 60.0, 3.0, 15.0, 40.0, 100.0]
        let stats = LatencyStats(latencies: latencies)
        #expect(stats.histogramBuckets.total == latencies.count)
    }

    @Test func emptyLatenciesGiveZeroBuckets() {
        let stats = LatencyStats(latencies: [])
        let b = stats.histogramBuckets
        #expect(b.under5ms == 0)
        #expect(b.ms5to20 == 0)
        #expect(b.ms20to50 == 0)
        #expect(b.over50ms == 0)
        #expect(b.total == 0)
    }

    @Test func normalizedHeightsAllZeroForEmpty() {
        let stats = LatencyStats(latencies: [])
        #expect(stats.histogramBuckets.normalizedHeights == [0, 0, 0, 0])
    }

    @Test func normalizedHeightsMaxIsOne() {
        let stats = LatencyStats(latencies: [1.0, 2.0, 3.0, 10.0, 30.0, 60.0])
        let heights = stats.histogramBuckets.normalizedHeights
        #expect(heights.max() == 1.0)
        for h in heights {
            #expect(h >= 0.0)
            #expect(h <= 1.0)
        }
    }

    @Test func normalizedHeightsReflectsDistribution() {
        // 4 values under 5ms, 2 in 5-20, 1 in 20-50, 0 over 50
        let stats = LatencyStats(latencies: [1, 2, 3, 4, 10, 15, 30])
        let heights = stats.histogramBuckets.normalizedHeights
        // under5ms=4 (peak=1.0), ms5to20=2 (0.5), ms20to50=1 (0.25), over50ms=0 (0.0)
        #expect(heights[0] == 1.0)
        #expect(heights[1] == 0.5)
        #expect(heights[2] == 0.25)
        #expect(heights[3] == 0.0)
    }

    @Test func normalizedHeightsEqualDistribution() {
        // 2 in each bucket => all heights should be 1.0
        let stats = LatencyStats(latencies: [1, 2, 10, 15, 30, 40, 60, 100])
        let heights = stats.histogramBuckets.normalizedHeights
        #expect(heights == [1.0, 1.0, 1.0, 1.0])
    }
}

// MARK: - BandwidthRange Tests

@Suite("InternetActivityCard.BandwidthRange")
struct BandwidthRangeTests {

    @Test func hasTwoFourHourCase() {
        let range = InternetActivityCard.BandwidthRange.h24
        #expect(range.rawValue == "24H")
    }

    @Test func hasSevenDayCase() {
        let range = InternetActivityCard.BandwidthRange.d7
        #expect(range.rawValue == "7D")
    }

    @Test func hasThirtyDayCase() {
        let range = InternetActivityCard.BandwidthRange.d30
        #expect(range.rawValue == "30D")
    }

    @Test func allCasesContainsThreeValues() {
        #expect(InternetActivityCard.BandwidthRange.allCases.count == 3)
    }

    @Test func allCasesOrder() {
        let cases = InternetActivityCard.BandwidthRange.allCases
        #expect(cases[0] == .h24)
        #expect(cases[1] == .d7)
        #expect(cases[2] == .d30)
    }
}

// MARK: - MacTheme.Colors.latencyColor Tests

@Suite("MacTheme.Colors.latencyColor")
struct LatencyColorTests {

    @Test func under50msReturnsSuccess() {
        let color = MacTheme.Colors.latencyColor(ms: 10.0)
        #expect(color == MacTheme.Colors.success)
    }

    @Test func zeroMsReturnsSuccess() {
        let color = MacTheme.Colors.latencyColor(ms: 0.0)
        #expect(color == MacTheme.Colors.success)
    }

    @Test func at49msReturnsSuccess() {
        let color = MacTheme.Colors.latencyColor(ms: 49.9)
        #expect(color == MacTheme.Colors.success)
    }

    @Test func at50msReturnsWarning() {
        let color = MacTheme.Colors.latencyColor(ms: 50.0)
        #expect(color == MacTheme.Colors.warning)
    }

    @Test func at149msReturnsWarning() {
        let color = MacTheme.Colors.latencyColor(ms: 149.9)
        #expect(color == MacTheme.Colors.warning)
    }

    @Test func at150msReturnsError() {
        let color = MacTheme.Colors.latencyColor(ms: 150.0)
        #expect(color == MacTheme.Colors.error)
    }

    @Test func highLatencyReturnsError() {
        let color = MacTheme.Colors.latencyColor(ms: 500.0)
        #expect(color == MacTheme.Colors.error)
    }
}

// MARK: - MacTheme.Colors.healthScoreColor Tests

@Suite("MacTheme.Colors.healthScoreColor")
struct HealthScoreColorTests {

    @Test func score100ReturnsSuccess() {
        #expect(MacTheme.Colors.healthScoreColor(100) == MacTheme.Colors.success)
    }

    @Test func score80ReturnsSuccess() {
        #expect(MacTheme.Colors.healthScoreColor(80) == MacTheme.Colors.success)
    }

    @Test func score79ReturnsWarning() {
        #expect(MacTheme.Colors.healthScoreColor(79) == MacTheme.Colors.warning)
    }

    @Test func score60ReturnsWarning() {
        #expect(MacTheme.Colors.healthScoreColor(60) == MacTheme.Colors.warning)
    }

    @Test func score59ReturnsOrange() {
        // 40..<60 maps to orange (Color(hex: "F97316"))
        let color = MacTheme.Colors.healthScoreColor(59)
        #expect(color != MacTheme.Colors.success)
        #expect(color != MacTheme.Colors.warning)
        #expect(color != MacTheme.Colors.error)
    }

    @Test func score40ReturnsOrange() {
        let color = MacTheme.Colors.healthScoreColor(40)
        #expect(color != MacTheme.Colors.success)
        #expect(color != MacTheme.Colors.warning)
        #expect(color != MacTheme.Colors.error)
    }

    @Test func score39ReturnsError() {
        #expect(MacTheme.Colors.healthScoreColor(39) == MacTheme.Colors.error)
    }

    @Test func score0ReturnsError() {
        #expect(MacTheme.Colors.healthScoreColor(0) == MacTheme.Colors.error)
    }
}

// MARK: - HealthGaugeCard latency/loss percentage logic
//
// The HealthGaugeCard has private helper functions:
//   latencyPct(_:) -> Double
//   lossPct(_:) -> Double
//
// These are private to the view. We replicate the logic here and test it
// to ensure the formulas are correct. If the logic is later extracted into
// the model layer, these tests remain valid.

@Suite("Health gauge percentage formulas")
struct HealthGaugePercentageTests {

    /// Mirrors HealthGaugeCard.latencyPct
    private func latencyPct(_ score: NetworkHealthScore) -> Double {
        guard let ms = score.latencyMs else { return 0 }
        return ms < 10 ? 1.0 : ms < 50 ? 0.85 : ms < 100 ? 0.6 : 0.3
    }

    /// Mirrors HealthGaugeCard.lossPct
    private func lossPct(_ score: NetworkHealthScore) -> Double {
        guard let loss = score.packetLoss else { return 0 }
        return 1.0 - loss
    }

    // MARK: latencyPct

    @Test func latencyUnder10msGivesFull() {
        let score = NetworkHealthScore(score: 90, grade: "A", latencyMs: 5.0)
        #expect(latencyPct(score) == 1.0)
    }

    @Test func latency10msGives085() {
        let score = NetworkHealthScore(score: 80, grade: "B", latencyMs: 10.0)
        #expect(latencyPct(score) == 0.85)
    }

    @Test func latency49msGives085() {
        let score = NetworkHealthScore(score: 75, grade: "C", latencyMs: 49.0)
        #expect(latencyPct(score) == 0.85)
    }

    @Test func latency50msGives060() {
        let score = NetworkHealthScore(score: 60, grade: "C", latencyMs: 50.0)
        #expect(latencyPct(score) == 0.6)
    }

    @Test func latency99msGives060() {
        let score = NetworkHealthScore(score: 50, grade: "D", latencyMs: 99.0)
        #expect(latencyPct(score) == 0.6)
    }

    @Test func latency100msGives030() {
        let score = NetworkHealthScore(score: 30, grade: "F", latencyMs: 100.0)
        #expect(latencyPct(score) == 0.3)
    }

    @Test func latency500msGives030() {
        let score = NetworkHealthScore(score: 20, grade: "F", latencyMs: 500.0)
        #expect(latencyPct(score) == 0.3)
    }

    @Test func latencyNilGivesZero() {
        let score = NetworkHealthScore(score: 50, grade: "D", latencyMs: nil)
        #expect(latencyPct(score) == 0.0)
    }

    // MARK: lossPct

    @Test func zeroLossGivesFull() {
        let score = NetworkHealthScore(score: 95, grade: "A", packetLoss: 0.0)
        #expect(lossPct(score) == 1.0)
    }

    @Test func halfLossGivesHalf() {
        let score = NetworkHealthScore(score: 40, grade: "D", packetLoss: 0.5)
        #expect(lossPct(score) == 0.5)
    }

    @Test func fullLossGivesZero() {
        let score = NetworkHealthScore(score: 10, grade: "F", packetLoss: 1.0)
        #expect(lossPct(score) == 0.0)
    }

    @Test func lossNilGivesZero() {
        let score = NetworkHealthScore(score: 50, grade: "D", packetLoss: nil)
        #expect(lossPct(score) == 0.0)
    }

    @Test func tenPercentLossGives090() {
        let score = NetworkHealthScore(score: 70, grade: "C", packetLoss: 0.1)
        #expect(abs(lossPct(score) - 0.9) < 0.001)
    }
}

// MARK: - ConnectivityCard location string logic

@Suite("Connectivity location string logic")
struct ConnectivityLocationTests {

    /// Mirrors ConnectivityCard.locationString
    private func locationString(city: String?, country: String?) -> String {
        if let city, let country {
            return "\(city), \(country)"
        }
        return country ?? "—"
    }

    @Test func cityAndCountryFormattedCorrectly() {
        #expect(locationString(city: "San Francisco", country: "US") == "San Francisco, US")
    }

    @Test func onlyCountryReturnsCountry() {
        #expect(locationString(city: nil, country: "US") == "US")
    }

    @Test func neitherReturnsDash() {
        #expect(locationString(city: nil, country: nil) == "\u{2014}")
    }

    @Test func cityWithoutCountryReturnsDash() {
        // If country is nil, city alone can't form the string
        #expect(locationString(city: "London", country: nil) == "\u{2014}")
    }
}

// MARK: - MacTheme.Colors.statusColor Tests

@Suite("MacTheme.Colors.statusColor")
struct StatusColorTests {

    @Test func onlineReturnsSuccess() {
        #expect(MacTheme.Colors.statusColor(.online) == MacTheme.Colors.success)
    }

    @Test func offlineReturnsError() {
        #expect(MacTheme.Colors.statusColor(.offline) == MacTheme.Colors.error)
    }

    @Test func idleReturnsWarning() {
        #expect(MacTheme.Colors.statusColor(.idle) == MacTheme.Colors.warning)
    }

    @Test func unknownReturnsGray() {
        #expect(MacTheme.Colors.statusColor(.unknown) == Color.gray)
    }
}
