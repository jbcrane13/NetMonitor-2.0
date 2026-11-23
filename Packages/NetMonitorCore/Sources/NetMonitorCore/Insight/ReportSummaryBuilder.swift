import Foundation

/// Builds the digest behind a report's executive summary (#453). Pure, like
/// `ToolInsightBuilder`: every figure comes from the records passed in, and every judgement
/// is computed here rather than by the model. It makes no claim about when a device was first
/// discovered: on iOS a `LocalDevice` row is created when its details are first opened, so
/// `firstSeen` is not discovery history.
public enum ReportSummaryBuilder {
    /// The latest download counts as well below normal under this share of the average:
    /// below 70%, a drop a reader would notice rather than everyday variation.
    public static let slowDownloadRatio = 0.7

    /// The summary request for a report of these records, or nil when there is nothing to
    /// summarize. Speed figures use every saved test, as the report's own Summary section
    /// does; the apps save only tests that completed.
    /// - Parameters:
    ///   - now: the report time, used for the report date.
    ///   - calendar: writes the report date in the reader's time zone.
    public static func request(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InsightRequest? {
        guard !devices.isEmpty || !toolResults.isEmpty || !speedTests.isEmpty else { return nil }
        var facts = ["Report date: \(longDay(now, calendar))"]
        var observations: [String] = []
        addDevices(devices, facts: &facts, observations: &observations)
        addSpeedTests(speedTests, facts: &facts, observations: &observations)
        addToolResults(toolResults, facts: &facts, observations: &observations)
        return InsightRequest(subject: "Network report", facts: facts, observations: observations, kind: .summary)
    }

    // MARK: - Sections

    private static func addDevices(_ devices: [LocalDevice], facts: inout [String], observations: inout [String]) {
        let online = devices.count { $0.status == .online }
        let offline = devices.count { $0.status == .offline }
        // Idle devices and ones only left in the ARP cache are neither online nor offline.
        let other = devices.count - online - offline
        facts.append("Number of devices: \(devices.count)")
        facts.append("Devices online: \(online)")
        facts.append("Devices offline: \(offline)")
        if other > 0 {
            facts.append("Devices idle or not answering: \(other)")
        }
        if offline > 0 {
            observations.append("\(ToolInsightBuilder.plural(offline, "device")) \(offline == 1 ? "is" : "are") offline.")
        }
    }

    private static func addSpeedTests(_ tests: [SpeedTestResult], facts: inout [String], observations: inout [String]) {
        facts.append("Number of speed tests: \(tests.count)")
        guard let latest = tests.max(by: { $0.timestamp < $1.timestamp }) else { return }
        let average = tests.map(\.downloadSpeed).reduce(0, +) / Double(tests.count)
        facts.append("Latest download: \(mbps(latest.downloadSpeed))")
        facts.append("Latest upload: \(mbps(latest.uploadSpeed))")
        facts.append("Average download: \(mbps(average))")
        if tests.count >= 2, latest.downloadSpeed < average * slowDownloadRatio {
            observations.append("The latest download speed, \(mbps(latest.downloadSpeed)), is well below the average of \(mbps(average)).")
        }
    }

    private static func addToolResults(_ results: [ToolResult], facts: inout [String], observations: inout [String]) {
        facts.append("Number of tool runs: \(results.count)")
        let failed = results.filter { !$0.success }
        guard !results.isEmpty else { return }
        facts.append("Failed tool runs: \(failed.count)")
        guard !failed.isEmpty else { return }
        let counts: [String: Int] = failed.reduce(into: [:]) { $0[$1.toolType.displayName, default: 0] += 1 }
        let order = counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
        // A count per tool only when more than one tool failed: "1 tool run failed: Ping."
        let byTool = order.count == 1 ? order[0] : order.map { "\($0) (\(counts[$0] ?? 0))" }.joined(separator: ", ")
        observations.append("\(ToolInsightBuilder.plural(failed.count, "tool run")) failed: \(byTool).")
    }

    // MARK: - Formatting

    /// Speeds as the report's tables show them.
    static func mbps(_ value: Double) -> String {
        String(format: "%.1f Mbps", value)
    }

    /// The date the way a reader says it, such as "November 22, 2026".
    static func longDay(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
