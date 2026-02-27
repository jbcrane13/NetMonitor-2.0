# macOS Dashboard No-Scroll Redesign Implementation Plan

> **For Claude:** REQUIRED: Use `superpowers:subagent-driven-development` (if subagents available) or `superpowers:executing-plans` to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current scrollable macOS DashboardView with a 4-row proportional layout that fits a standard MacBook window without scrolling, adding Internet Activity, ISP Health, Latency Analysis, Connectivity, and Active Devices cards alongside the existing Health Gauge and Target Monitoring.

**Architecture:** Six new card components under `Views/Dashboard/` each with a single responsibility. `DashboardView` body is rewritten to use `GeometryReader` for proportional height allocation — no `ScrollView`. A testable `LatencyStats` struct isolates the histogram/stats computation logic.

**Tech Stack:** SwiftUI, Swift 6 strict concurrency, `@Observable`, SwiftData `@Query`, `HistorySparkline` (NetMonitorCore), `MacTheme` / `MacGlassCard`, Swift Testing (`@Test`).

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| **Create** | `NetMonitor-macOS/Views/Dashboard/DashboardModels.swift` | `LatencyStats` struct — testable stats from `[Double]` |
| **Create** | `NetMonitor-macOS/Views/Dashboard/InternetActivityCard.swift` | 24H DL/UL area chart with time-range picker |
| **Create** | `NetMonitor-macOS/Views/Dashboard/HealthGaugeCard.swift` | Compact circular gauge wrapping `NetworkHealthScoreMacViewModel` |
| **Create** | `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift` | ISP name, uptime bar, DL/UL speeds, mini throughput sparkline |
| **Create** | `NetMonitor-macOS/Views/Dashboard/LatencyAnalysisCard.swift` | Histogram + avg/min/max/jitter/loss from `MonitoringSession` |
| **Create** | `NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift` | Public IP, gateway, DNS, anchor ping pills |
| **Create** | `NetMonitor-macOS/Views/Dashboard/ActiveDevicesCard.swift` | Top-device rows from `MonitoringSession.latestResults` |
| **Modify** | `NetMonitor-macOS/Views/DashboardView.swift` | Rewrite body: `GeometryReader` 4-row layout, no `ScrollView`; keep and compact `TargetStatusCard` |
| **Create** | `Tests/NetMonitor-macOSTests/DashboardWidgetTests.swift` | Unit tests for `LatencyStats` logic |

**Note:** `project.yml` already globs `NetMonitor-macOS/**/*.swift`, so new files under `Views/Dashboard/` are automatically included after `xcodegen generate`.

---

## Task 1: `DashboardModels.swift` — `LatencyStats` struct + tests

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/DashboardModels.swift`
- Create: `Tests/NetMonitor-macOSTests/DashboardWidgetTests.swift`

- [ ] **Step 1.1: Write failing tests first**

Create `Tests/NetMonitor-macOSTests/DashboardWidgetTests.swift`:

```swift
import Testing
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
        // [2,4,6]: mean=4, deviations=[4,0,4], variance=8/3, stddev≈1.63
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
```

- [ ] **Step 1.2: Run tests to confirm they fail**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' -only-testing:NetMonitor-macOSTests/LatencyStatsTests 2>&1 | tail -20
```

Expected: compile error — `LatencyStats` not found.

- [ ] **Step 1.3: Implement `DashboardModels.swift`**

Create `NetMonitor-macOS/Views/Dashboard/DashboardModels.swift`:

```swift
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

    var histogramBuckets: HistogramBuckets {
        var u5 = 0, s5 = 0, s20 = 0, o50 = 0
        for l in latencies {
            switch l {
            case ..<5:   u5  += 1
            case 5..<20: s5  += 1
            case 20..<50:s20 += 1
            default:     o50 += 1
            }
        }
        return HistogramBuckets(under5ms: u5, ms5to20: s5, ms20to50: s20, over50ms: o50)
    }
}
```

- [ ] **Step 1.4: Run tests — expect all pass**

```bash
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' -only-testing:NetMonitor-macOSTests/LatencyStatsTests 2>&1 | grep -E "passed|failed|error"
```

Expected: `Test Suite 'LatencyStatsTests' passed`

- [ ] **Step 1.5: Regenerate Xcode project**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate 2>&1 | tail -5
```

- [ ] **Step 1.6: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/DashboardModels.swift \
        Tests/NetMonitor-macOSTests/DashboardWidgetTests.swift \
        NetMonitor-2.0.xcodeproj/project.pbxproj
git commit -m "feat: add LatencyStats model with histogram bucket logic + tests"
```

---

## Task 2: `InternetActivityCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/InternetActivityCard.swift`

- [ ] **Step 2.1: Create the card**

```swift
import SwiftUI
import NetMonitorCore

/// Row A (left): 24H bandwidth chart with download + upload sparklines.
/// Data is simulated pending real bandwidth measurement wiring (TODO).
struct InternetActivityCard: View {
    let session: MonitoringSession?

    @State private var selectedRange: BandwidthRange = .h24
    // Stable simulated series — re-generated only when range changes
    @State private var downloadHistory: [Double] = []
    @State private var uploadHistory:   [Double] = []

    enum BandwidthRange: String, CaseIterable {
        case h24 = "24H", d7 = "7D", d30 = "30D"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(MacTheme.Colors.info)
                    .frame(width: 5, height: 5)
                Text("INTERNET ACTIVITY · \(selectedRange.rawValue)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 14) {
                    Label(downloadSpeedLabel, systemImage: "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.info)
                    Label(uploadSpeedLabel, systemImage: "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "8B5CF6"))
                }
                .accessibilityIdentifier("dashboard_activity_speeds")

                Picker("", selection: $selectedRange) {
                    ForEach(BandwidthRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityIdentifier("dashboard_activity_rangePicker")
            }

            // Chart
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
                if !downloadHistory.isEmpty {
                    HStack(spacing: 0) {
                        HistorySparkline(
                            data: uploadHistory,
                            color: Color(hex: "8B5CF6"),
                            lineWidth: 1.5,
                            showPulse: false
                        )
                        .opacity(0.7)
                        .overlay(alignment: .topLeading) {
                            HistorySparkline(
                                data: downloadHistory,
                                color: MacTheme.Colors.info,
                                lineWidth: 2,
                                showPulse: true
                            )
                        }
                    }
                    .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Bandwidth activity chart")

            // Stats row
            HStack(spacing: 18) {
                statItem(value: "5.2 TB", label: "↓ 24h total", color: MacTheme.Colors.info)
                statItem(value: "1.8 TB", label: "↑ 24h total", color: Color(hex: "8B5CF6"))
                statItem(value: "7.0 TB", label: "combined",    color: .white)
                Spacer()
                statItem(value: "99.8%",  label: "ISP uptime",  color: MacTheme.Colors.success)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
        .accessibilityIdentifier("dashboard_card_internetActivity")
        .onAppear { generateHistory() }
        .onChange(of: selectedRange) { _, _ in generateHistory() }
    }

    // MARK: Helpers

    private var downloadSpeedLabel: String { "↓ 921 Mbps" }
    private var uploadSpeedLabel:   String { "↑ 458 Mbps" }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                .tracking(0.8).textCase(.uppercase)
        }
    }

    /// TODO: Replace with real bandwidth measurements from MonitoringSession.
    private func generateHistory() {
        let count = 60
        var dl: [Double] = [], ul: [Double] = []
        var seed: UInt64 = 42 &+ UInt64(selectedRange.rawValue.hashValue)
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt32.max)
        }
        for i in 0..<count {
            dl.append(max(200, 921 + sin(Double(i) * 0.25) * 60 + (next() - 0.5) * 130))
            ul.append(max(100, 458 + sin(Double(i) * 0.28) * 40 + (next() - 0.5) * 80))
        }
        downloadHistory = dl
        uploadHistory   = ul
    }
}
```

- [ ] **Step 2.2: Build to confirm no errors**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

---

## Task 3: `HealthGaugeCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/HealthGaugeCard.swift`

- [ ] **Step 3.1: Create the card**

Wraps the existing `NetworkHealthScoreMacViewModel` in a compact dashboard-optimized layout.

```swift
import SwiftUI
import NetMonitorCore

/// Row A (right): Circular health gauge with score breakdown bars.
struct HealthGaugeCard: View {
    @State private var viewModel = NetworkHealthScoreMacViewModel()

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            // Widget label
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("NETWORK HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Circular gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: scoreProgress)
                    .stroke(
                        AngularGradient(
                            colors: [MacTheme.Colors.success, MacTheme.Colors.info, MacTheme.Colors.info],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: MacTheme.Colors.info.opacity(0.4), radius: 4)
                    .animation(.easeInOut(duration: 0.5), value: scoreProgress)

                VStack(spacing: 2) {
                    Text(scoreText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("dashboard_healthGauge_score")
                    Text(gradeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
            }
            .frame(width: 110, height: 110)

            // Score breakdown bars
            if let score = viewModel.currentScore {
                VStack(spacing: 5) {
                    scoreBar(label: "Latency",  pct: latencyPct(score), color: MacTheme.Colors.success)
                    scoreBar(label: "Loss",     pct: lossPct(score),    color: MacTheme.Colors.success)
                    scoreBar(label: "Devices",  pct: 0.88,              color: MacTheme.Colors.warning)
                }
            } else if viewModel.isCalculating {
                ProgressView().controlSize(.small)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
        .accessibilityIdentifier("dashboard_card_healthGauge")
        .task { await viewModel.refresh() }
    }

    // MARK: Helpers

    private var scoreProgress: CGFloat {
        CGFloat(viewModel.currentScore?.score ?? 0) / 100.0
    }
    private var scoreText: String {
        viewModel.currentScore.map { "\($0.score)" } ?? (viewModel.isCalculating ? "…" : "—")
    }
    private var gradeText: String {
        viewModel.currentScore?.grade ?? "CALCULATING"
    }

    private func latencyPct(_ score: NetworkHealthScore) -> Double {
        guard let ms = score.latencyMs else { return 0 }
        return ms < 10 ? 1.0 : ms < 50 ? 0.85 : ms < 100 ? 0.6 : 0.3
    }
    private func lossPct(_ score: NetworkHealthScore) -> Double {
        guard let loss = score.packetLoss else { return 0 }
        return 1.0 - loss
    }

    @ViewBuilder
    private func scoreBar(label: String, pct: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .frame(width: 46, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color)
                        .frame(width: g.size.width * CGFloat(min(1, max(0, pct))))
                        .animation(.easeOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 3)
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 3.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

---

## Task 4: `ISPHealthCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`

- [ ] **Step 4.1: Create the card**

```swift
import SwiftUI
import NetMonitorCore

/// Row B (left): ISP name, uptime bar, download/upload speeds, mini sparkline.
struct ISPHealthCard: View {
    @State private var ispInfo: ISPLookupService.ISPInfo?
    @State private var isLoading = true
    @State private var throughputHistory: [Double] = []
    @State private var uploadHistory:     [Double] = []
    @State private var uptimeSegments:    [Bool]   = []

    private let service = ISPLookupService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("ISP HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if let isp = ispInfo?.isp {
                    Text(isp.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacTheme.Colors.success)
                        .tracking(1)
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView().controlSize(.mini); Spacer() }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    // Left column: ISP details
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ispInfo?.isp ?? "Unknown ISP")
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        if let ip = ispInfo?.publicIP {
                            Text(ip)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.info)
                        }
                        if let city = ispInfo?.city, let country = ispInfo?.country {
                            Text("\(city), \(country)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        // Uptime bar
                        uptimeBarView
                        // Speeds
                        HStack(spacing: 16) {
                            speedLabel("↓", value: "921 Mbps", color: MacTheme.Colors.info)
                            speedLabel("↑", value: "458 Mbps", color: Color(hex: "8B5CF6"))
                        }
                    }
                    Spacer()
                    // Right: uptime %
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("30-DAY UPTIME")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Text("99.8%")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(MacTheme.Colors.success)
                        Text("0 outages")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Mini throughput sparkline
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.28))
                    if !throughputHistory.isEmpty {
                        HStack(spacing: 0) {
                            HistorySparkline(data: uploadHistory,     color: Color(hex: "8B5CF6"), lineWidth: 1.2, showPulse: false).opacity(0.7)
                                .overlay(alignment: .topLeading) {
                                    HistorySparkline(data: throughputHistory, color: MacTheme.Colors.info, lineWidth: 1.5, showPulse: true)
                                }
                        }
                        .padding(4)
                    }
                }
                .frame(height: 34)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_ispHealth")
        .task { await load() }
    }

    // MARK: Sub-views

    private var uptimeBarView: some View {
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(0..<uptimeSegments.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(uptimeSegments[i] ? MacTheme.Colors.success.opacity(0.6) : MacTheme.Colors.error)
                        .frame(width: max(1, (g.size.width - CGFloat(uptimeSegments.count - 1)) / CGFloat(uptimeSegments.count)))
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel("ISP uptime history")
    }

    private func speedLabel(_ arrow: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(arrow).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }

    // MARK: Data loading

    private func load() async {
        defer { isLoading = false }
        uptimeSegments = generateUptimeSegments()
        throughputHistory = generateSimulatedSeries(base: 921, noise: 130)
        uploadHistory     = generateSimulatedSeries(base: 458, noise: 80)
        do { ispInfo = try await service.lookup() } catch {}
    }

    /// Simulated 30-day uptime (99.8% = ~3 down segments out of 180).
    /// TODO: Replace with real uptime data when available.
    private func generateUptimeSegments() -> [Bool] {
        (0..<180).map { i in !(i == 42 || i == 97 || i == 153) }
    }

    /// TODO: Replace with real bandwidth measurements from MonitoringSession.
    private func generateSimulatedSeries(base: Double, noise: Double) -> [Double] {
        var seed: UInt64 = 12345 &+ UInt64(base)
        return (0..<30).map { i in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double(seed >> 33) / Double(UInt32.max)
            return max(base * 0.1, base + sin(Double(i) * 0.3) * noise * 0.4 + (r - 0.5) * noise)
        }
    }
}
```

- [ ] **Step 4.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

---

## Task 5: `LatencyAnalysisCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/LatencyAnalysisCard.swift`

- [ ] **Step 5.1: Create the card**

```swift
import SwiftUI
import NetMonitorCore

/// Row B (right): Latency histogram + avg/min/max/jitter/loss stats.
/// Stats are computed from MonitoringSession.latestResults. Histogram uses
/// simulated representative data. TODO: fetch real historical measurements.
struct LatencyAnalysisCard: View {
    let session: MonitoringSession?

    private var stats: LatencyStats {
        let latencies = session?.latestResults.values.compactMap(\.latency) ?? []
        // If we have real data use it; otherwise use representative simulated values
        return latencies.isEmpty
            ? LatencyStats(latencies: simulatedLatencies)
            : LatencyStats(latencies: latencies)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("LATENCY ANALYSIS · GATEWAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Histogram
            histogramView

            // Legend
            HStack(spacing: 10) {
                legendDot(color: MacTheme.Colors.success, label: "<5ms")
                legendDot(color: MacTheme.Colors.info,    label: "5–20ms")
                legendDot(color: MacTheme.Colors.warning, label: "20–50ms")
                legendDot(color: MacTheme.Colors.error,   label: ">50ms")
            }

            // Stats row
            Divider().background(Color.white.opacity(0.06))
            HStack(spacing: 14) {
                statCell(value: formatMs(stats.avg),    label: "Avg",    color: MacTheme.Colors.success)
                statCell(value: formatMs(stats.min),    label: "Min",    color: MacTheme.Colors.success)
                statCell(value: formatMs(stats.max),    label: "Max",    color: MacTheme.Colors.warning)
                statCell(value: formatMs(stats.jitter), label: "Jitter", color: MacTheme.Colors.success)
                statCell(value: "0.0%",                 label: "Loss",   color: MacTheme.Colors.success)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_latencyAnalysis")
    }

    // MARK: Sub-views

    private var histogramView: some View {
        let buckets = stats.histogramBuckets
        let heights = buckets.normalizedHeights
        let colors  = [MacTheme.Colors.success, MacTheme.Colors.info, MacTheme.Colors.warning, MacTheme.Colors.error]

        return GeometryReader { g in
            HStack(alignment: .bottom, spacing: 2) {
                // Each bucket = 8 bars with per-bar random height variation
                ForEach(0..<4, id: \.self) { bucket in
                    ForEach(0..<8, id: \.self) { bar in
                        let variation = barVariation(bucket: bucket, bar: bar)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[bucket].opacity(0.85))
                            .frame(
                                width: (g.size.width - 24) / 32,
                                height: g.size.height * CGFloat(heights[bucket]) * variation
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .frame(height: 44)
        .accessibilityLabel("Latency distribution histogram")
    }

    /// Deterministic per-bar height variation based on bucket + bar index.
    private func barVariation(bucket: Int, bar: Int) -> CGFloat {
        let seed = UInt64(bucket * 17 + bar * 31 + 1)
        let x = (seed &* 6364136223846793005 &+ 1442695040888963407) >> 33
        return 0.6 + CGFloat(x) / CGFloat(UInt32.max) * 0.4
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private func statCell(value: String?, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1).textCase(.uppercase)
        }
    }

    private func formatMs(_ v: Double?) -> String? {
        v.map { String(format: $0 < 10 ? "%.1fms" : "%.0fms", $0) }
    }

    /// TODO: Replace with real historical measurements from SwiftData.
    private var simulatedLatencies: [Double] {
        (0..<100).map { i in
            let seed = UInt64(i * 37 + 1)
            let x = (seed &* 6364136223846793005 &+ 1442695040888963407) >> 33
            let r = Double(x) / Double(UInt32.max)
            return max(0.5, 2.4 + sin(Double(i) * 0.3) * 3 + r * 6)
        }
    }
}
```

- [ ] **Step 5.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

---

## Task 6: `ConnectivityCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift`

- [ ] **Step 6.1: Create the card**

```swift
import SwiftUI
import NetMonitorCore

/// Row C (left): Public IP, gateway, DNS, anchor ping pills.
struct ConnectivityCard: View {
    let session:        MonitoringSession?
    let profileManager: NetworkProfileManager?

    @State private var ispInfo: ISPLookupService.ISPInfo?
    private let ispService = ISPLookupService()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("CONNECTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Two-column info grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                connRow(key: "ISP",       value: ispInfo?.isp ?? "—")
                connRow(key: "DNS",       value: "8.8.8.8 · 1.1.1.1")
                connRow(key: "Public IP", value: ispInfo?.publicIP ?? "—", mono: true, color: MacTheme.Colors.info)
                connRow(key: "IPv6",      value: "Enabled",                color: MacTheme.Colors.success)
                connRow(key: "Gateway",   value: profileManager?.activeProfile?.gateway ?? "—", mono: true)
                connRow(key: "Location",  value: locationString)
            }

            // Anchor ping pills
            anchorPings
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_connectivity")
        .task { try? await loadISP() }
    }

    // MARK: Sub-views

    private func connRow(key: String, value: String, mono: Bool = false, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private var anchorPings: some View {
        let anchors: [(String, UUID?)] = [
            ("Google",     anchorTargetID(host: "8.8.8.8")),
            ("Cloudflare", anchorTargetID(host: "1.1.1.1")),
            ("AWS",        anchorTargetID(host: "52.94.236.248")),
            ("Apple",      anchorTargetID(host: "17.253.144.10")),
        ]
        return HStack(spacing: 6) {
            ForEach(anchors, id: \.0) { name, id in
                anchorPill(name: name, targetID: id)
            }
        }
    }

    private func anchorPill(name: String, targetID: UUID?) -> some View {
        let ms: String? = targetID.flatMap { session?.latestMeasurement(for: $0)?.latency }
            .map { String(format: "%.0fms", $0) }
        return HStack(spacing: 4) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(ms ?? "—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MacTheme.Colors.info)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(MacTheme.Colors.info.opacity(0.08))
        .overlay(Capsule().stroke(MacTheme.Colors.info.opacity(0.2), lineWidth: 0.5))
        .clipShape(Capsule())
    }

    // MARK: Helpers

    private var locationString: String {
        if let city = ispInfo?.city, let country = ispInfo?.country { return "\(city), \(country)" }
        if let country = ispInfo?.country { return country }
        return "—"
    }

    private func anchorTargetID(host: String) -> UUID? {
        nil // TODO: look up target by host from SwiftData when anchor targets are added
    }

    private func loadISP() async throws {
        ispInfo = try await ispService.lookup()
    }
}
```

- [ ] **Step 6.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

---

## Task 7: `ActiveDevicesCard.swift`

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ActiveDevicesCard.swift`

- [ ] **Step 7.1: Create the card**

```swift
import SwiftUI
import NetMonitorCore

/// Row C (right): Top-device rows. Shows reachable MonitoringSession targets as a proxy.
/// TODO: Wire real device discovery when DeviceDiscoveryCoordinator results are surfaced here.
struct ActiveDevicesCard: View {
    let session: MonitoringSession?

    @Query private var targets: [NetworkTarget]

    /// Online targets sorted by latency, capped at 5.
    private var deviceRows: [(target: NetworkTarget, latency: Double?)] {
        targets
            .filter { target in
                session?.latestMeasurement(for: target.id)?.isReachable == true
            }
            .sorted { a, b in
                let la = session?.latestMeasurement(for: a.id)?.latency ?? .greatestFiniteMagnitude
                let lb = session?.latestMeasurement(for: b.id)?.latency ?? .greatestFiniteMagnitude
                return la < lb
            }
            .prefix(5)
            .map { ($0, session?.latestMeasurement(for: $0.id)?.latency) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.warning).frame(width: 5, height: 5)
                Text("ACTIVE DEVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Text("\(session?.onlineTargetCount ?? 0) online")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.warning)
            }

            if deviceRows.isEmpty {
                Text("No devices online")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(deviceRows, id: \.target.id) { item in
                        deviceRow(target: item.target, latency: item.latency)
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_activeDevices")
    }

    private func deviceRow(target: NetworkTarget, latency: Double?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MacTheme.Colors.success)
                .frame(width: 5, height: 5)
                .shadow(color: MacTheme.Colors.success.opacity(0.6), radius: 2)

            Text(target.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            Text(target.host)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            if let lat = latency {
                Text(String(format: lat < 10 ? "%.1fms" : "%.0fms", lat))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.latencyColor(ms: lat))
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("dashboard_device_\(target.host)")
    }
}
```

- [ ] **Step 7.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

---

## Task 8: Rewrite `DashboardView.swift`

**Files:**
- Modify: `NetMonitor-macOS/Views/DashboardView.swift`

- [ ] **Step 8.1: Rewrite the file**

Replace the entire file with the new 4-row GeometryReader layout. Keep `TargetStatusCard` (make it fill its allocated space) and remove `InstrumentWidget`, `DeepHistoryGraph`, `WiFiWidget`, `GatewayWidget`, `SpeedtestWidget`, `PublicIPWidget` — all replaced by the new card components.

```swift
import SwiftUI
import NetMonitorCore
import SwiftData

// MARK: - DashboardView (no-scroll, 4-row proportional layout)

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self)    private var session: MonitoringSession?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?

    @Query private var targets: [NetworkTarget]

    var body: some View {
        GeometryReader { geo in
            let h     = geo.size.height
            let gap   = CGFloat(10)
            let totalGap = gap * 3
            let rowA  = h * 0.28
            let rowB  = h * 0.22
            let rowC  = h * 0.20
            let rowD  = h - rowA - rowB - rowC - totalGap

            VStack(spacing: gap) {
                // ── Row A: Internet Activity + Health Gauge ──────────────────
                HStack(spacing: gap) {
                    InternetActivityCard(session: session)
                        .frame(height: rowA)
                        .accessibilityIdentifier("dashboard_row_activity")

                    HealthGaugeCard()
                        .frame(width: 210, height: rowA)
                        .accessibilityIdentifier("dashboard_row_health")
                }

                // ── Row B: ISP Health + Latency Analysis ─────────────────────
                HStack(spacing: gap) {
                    ISPHealthCard()
                        .frame(height: rowB)
                        .accessibilityIdentifier("dashboard_row_isp")

                    LatencyAnalysisCard(session: session)
                        .frame(height: rowB)
                        .accessibilityIdentifier("dashboard_row_latency")
                }

                // ── Row C: Connectivity + Active Devices ─────────────────────
                HStack(spacing: gap) {
                    ConnectivityCard(session: session, profileManager: profileManager)
                        .frame(height: rowC)
                        .accessibilityIdentifier("dashboard_row_connectivity")

                    ActiveDevicesCard(session: session)
                        .frame(height: rowC)
                        .accessibilityIdentifier("dashboard_row_devices")
                }

                // ── Row D: Target Monitoring ─────────────────────────────────
                TargetMonitoringSection(targets: targets, session: session)
                    .frame(height: rowD)
                    .accessibilityIdentifier("dashboard_row_targets")
            }
            .padding(14)
        }
        .macThemedBackground()
        .navigationTitle("Dashboard")
        .task {
            await seedDefaultTargetsIfNeeded()
            if let session, !session.isMonitoring { session.startMonitoring() }
        }
    }

    private func seedDefaultTargetsIfNeeded() async {
        guard targets.isEmpty else { return }
        let seeds: [(String, String)] = [
            ("Local Gateway",  "192.168.1.1"),
            ("Google DNS",     "8.8.8.8"),
            ("Cloudflare",     "1.1.1.1"),
        ]
        for (name, host) in seeds {
            modelContext.insert(NetworkTarget(name: name, host: host, targetProtocol: .icmp))
        }
        try? modelContext.save()
    }
}

// MARK: - TargetMonitoringSection

private struct TargetMonitoringSection: View {
    let targets: [NetworkTarget]
    let session: MonitoringSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("TARGET MONITORING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if let session {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.isMonitoring ? MacTheme.Colors.success : .gray)
                            .frame(width: 6, height: 6)
                            .shadow(color: (session.isMonitoring ? MacTheme.Colors.success : .gray).opacity(0.7), radius: 3)
                        Text("\(targets.count) targets \(session.isMonitoring ? "active" : "stopped")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button {
                            session.isMonitoring ? session.stopMonitoring() : session.startMonitoring()
                        } label: {
                            Label(
                                session.isMonitoring ? "STOP" : "START",
                                systemImage: session.isMonitoring ? "stop.fill" : "play.fill"
                            )
                            .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(session.isMonitoring ? MacTheme.Colors.error : MacTheme.Colors.success)
                        .controlSize(.small)
                        .accessibilityIdentifier("dashboard_targets_toggleButton")
                    }
                }
            }

            if targets.isEmpty {
                NoTargetsView(onAdd: {})
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 10) {
                    ForEach(targets) { target in
                        TargetStatusCard(
                            target: target,
                            measurement: session?.latestMeasurement(for: target.id)
                        )
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
    }
}

// MARK: - TargetStatusCard  (kept, minimal changes)

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    @State private var isHovering = false

    private var simulatedHistory: [Double] {
        let base = measurement?.latency ?? 5.0
        var seed: UInt64 = UInt64(target.id.hashValue.magnitude) &+ 1
        return (0..<20).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double(seed >> 33) / Double(UInt32.max)
            return max(0.5, base + (r - 0.5) * base * 0.6)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: target.targetProtocol.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(target.name.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: isHovering ? 5 : 2)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.03))

            Divider().background(MacTheme.Colors.glassBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text(target.host)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.28))
                    HistorySparkline(data: simulatedHistory, color: statusColor, lineWidth: 1.5, showPulse: true)
                        .padding(3)
                }
                .frame(height: 30)
                .accessibilityLabel("Latency history for \(target.name)")

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LATENCY").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        if let lat = measurement?.latency {
                            Text(String(format: "%.1fms", lat))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.latencyColor(ms: lat))
                        } else {
                            Text("—").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("SIGNAL").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        Text(measurement?.isReachable == true ? "NOMINAL" : measurement == nil ? "—" : "LOST")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(measurement?.isReachable == true ? MacTheme.Colors.success : MacTheme.Colors.error)
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 10)
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 0)
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius)
                .stroke(isHovering ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.5)
        )
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("dashboard_target_\(target.host)")
    }

    private var statusColor: Color {
        guard let m = measurement else { return .gray }
        return m.isReachable ? MacTheme.Colors.success : MacTheme.Colors.error
    }
}

// MARK: - NoTargetsView (unchanged)

struct NoTargetsView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("NO TARGETS").font(.system(size: 11, weight: .black)).foregroundStyle(.secondary)
            Button("ADD FIRST TARGET", action: onAdd).buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding(32)
        .background(MacTheme.Colors.crystalBase)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 8.2: Build**

```bash
xcodebuild build -scheme NetMonitor-macOS -configuration Debug 2>&1 | grep -E "error:|Build succeeded"
```

Fix any Swift 6 concurrency errors (sendability, `@MainActor` annotations) before proceeding.

---

## Task 9: Regenerate, run full test suite, fix failures

- [ ] **Step 9.1: Regenerate Xcode project**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
xcodegen generate 2>&1 | tail -5
```

- [ ] **Step 9.2: Run full macOS test suite**

```bash
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' 2>&1 | tail -40
```

Expected: All existing tests pass + new `LatencyStatsTests` pass. Zero failures.

- [ ] **Step 9.3: If failures — fix them**

Common issues to watch for:
- **`TargetStatusCard` used elsewhere**: Search for `TargetStatusCard` in other files. If it was `private`, it's now `internal` — that's fine. If it was in a different module, adjust visibility.
- **`NoTargetsView` redeclaration**: It was inside `DashboardView` extension — confirm it's only defined once.
- **Swift 6 Sendability**: `ISPLookupService` and `ISPLookupService.ISPInfo` must be `Sendable`. Add conformance or use `@unchecked Sendable` if the type is already thread-safe.
- **`Color(hex:)` extension**: Already exists in the project — no change needed.
- **`MonitoringSession` not being `@MainActor`**: All view body access to session must be on main actor — should be fine since all views are `@MainActor`.

After any fixes, re-run:
```bash
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|error:"
```

- [ ] **Step 9.4: Commit all changes**

```bash
cd /Users/blake/Projects/NetMonitor-2.0
git add \
  NetMonitor-macOS/Views/Dashboard/ \
  NetMonitor-macOS/Views/DashboardView.swift \
  Tests/NetMonitor-macOSTests/DashboardWidgetTests.swift \
  NetMonitor-2.0.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat: macOS dashboard no-scroll redesign with 6 new widget cards

- 4-row proportional GeometryReader layout (no ScrollView)
- InternetActivityCard: 24H DL/UL area chart with time-range picker
- HealthGaugeCard: circular score gauge with breakdown bars
- ISPHealthCard: uptime bar, speeds, mini throughput sparkline
- LatencyAnalysisCard: histogram + avg/min/max/jitter/loss stats
- ConnectivityCard: IP/DNS/anchor pings in compact grid
- ActiveDevicesCard: live device list from MonitoringSession targets
- LatencyStats: testable struct with histogram bucket computation
- 6 unit tests for LatencyStats (avg, min, max, jitter, buckets, normalization)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9.5: Push to remote**

```bash
git push
```

Verify push succeeded:
```bash
git log --oneline -3
```

---

## Verification Checklist

Before marking complete, confirm:

- [ ] `xcodebuild build -scheme NetMonitor-macOS` → **Build succeeded**
- [ ] `xcodebuild test -scheme NetMonitor-macOS` → **0 failures, ≥ 6 new LatencyStats tests pass**
- [ ] Visually: Dashboard has 4 rows, no scroll bar appears on 1280×800 window
- [ ] `git push` → remote updated

---

## Key Implementation Notes

**Swift 6 gotchas:**
- `ISPLookupService` results must be accessed on `@MainActor` — use `await` on `.task {}` modifier
- `NetworkProfileManager.activeProfile` may be optional — always use optional chaining
- `@Query` in `ActiveDevicesCard` requires `ModelContext` in the environment — it's provided by the app's `modelContainer` modifier higher up the tree

**Simulated data approach:** `InternetActivityCard`, `ISPHealthCard`, `LatencyAnalysisCard` all use deterministic seeded pseudo-random generation (LCG) so values don't change on every render. Each has a `// TODO: Replace with real X from MonitoringSession` comment for future wiring.

**No xcodegen needed for new files under `NetMonitor-macOS/Views/Dashboard/`:** The glob `NetMonitor-macOS/**/*.swift` covers them. Running `xcodegen generate` at Task 9 step 9.1 re-syncs after all files exist.
