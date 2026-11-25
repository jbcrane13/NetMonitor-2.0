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
    ///   - presence: what each device's saved status means as of the report (#583): online,
    ///     offline or not checked recently, from its network's latest scan.
    ///   - now: the report time, used for the report date.
    ///   - calendar: writes the report date in the reader's time zone.
    /// Devices are counted as devices, not rows: a group of interfaces is one (#594). Pass
    /// complete groups.
    public static func request(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult],
        presence: PresenceSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InsightRequest? {
        guard !devices.isEmpty || !toolResults.isEmpty || !speedTests.isEmpty else { return nil }
        var facts = ["Report date: \(longDay(now, calendar))"]
        var observations: [String] = []
        addDevices(DeviceGroups.project(devices), presence: presence, facts: &facts, observations: &observations)
        addSpeedTests(speedTests, facts: &facts, observations: &observations)
        addToolResults(toolResults, facts: &facts, observations: &observations)
        return InsightRequest(subject: "Network report", facts: facts, observations: observations, kind: .summary)
    }

    // MARK: - Sections

    /// Devices by `PresenceFreshness` (#583). Online and offline are counted only for devices whose
    /// network was checked recently, so an old scan never gives an online count that reads as now.
    /// Past devices are counted apart, never as offline.
    private static func addDevices(
        _ devices: [DeviceProjection], presence: PresenceSnapshot, facts: inout [String], observations: inout [String]
    ) {
        guard !devices.isEmpty else {
            facts.append("Number of devices: 0")
            return
        }
        let past = devices.count { presence.isPast($0) }
        let current = devices.filter { !presence.isPast($0) }
        let states = current.map { presence.freshness(of: $0) }
        let notChecked = states.count(where: { $0 == .notCheckedRecently })
        let offline = states.count(where: { $0 == .offline })
        let latest = Set(devices.flatMap { $0.members.map(\.networkProfileID) }).compactMap { presence.lastScan(for: $0) }.max()
        let latestText = latest.map { PresenceFreshness.relativeText(since: $0, now: presence.now) }

        facts.append("Number of devices: \(current.count)")
        facts.append("Latest device scan: \(latestText ?? "none recorded")")
        if notChecked < current.count {
            facts.append("Devices online: \(states.count(where: { $0 == .online }))")
            facts.append("Devices offline: \(offline)")
        }
        if notChecked > 0 {
            facts.append("Devices not checked recently: \(notChecked)")
        }
        if past > 0 {
            facts.append("Past devices (not seen for \(PresenceFreshness.pastDeviceDays) days): \(past)")
        }
        if offline > 0 {
            observations.append("\(ToolInsightBuilder.plural(offline, "device")) \(offline == 1 ? "is" : "are") offline.")
        }
        if notChecked > 0 {
            let when = latestText.map { "the latest scan was \($0)" } ?? "no scan has been recorded"
            observations.append("\(ToolInsightBuilder.plural(notChecked, "device")) \(notChecked == 1 ? "was" : "were") not checked recently: \(when).")
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
