import Foundation
import SwiftData
import Observation
import NetMonitorCore

/// ViewModel that computes uptime statistics for a given network profile
/// over a configurable rolling time window.
///
/// Query window defaults to 30 days. Results include:
///   - `uptimePct`: overall uptime percentage (nil until loaded or if no transition records exist)
///   - `outageCount`: number of distinct offline→online transitions within the window
///   - `uptimeBar`: array of Booleans representing per-segment online status (for bar rendering)
///   - `latestLatencyMs`: most recent latency sample in milliseconds
@MainActor
@Observable
final class UptimeViewModel {

    // MARK: - Output (observed by views)

    /// Uptime percentage over the query window (0–100). Nil until first load.
    private(set) var uptimePct: Double?
    /// Number of distinct outage events in the window.
    private(set) var outageCount: Int = 0
    /// `barSegments` segments, each true = online for that period. Used by the uptime bar.
    private(set) var uptimeBar: [Bool] = []
    /// Most recent latency sample. Nil if no samples recorded.
    private(set) var latestLatencyMs: Double?
    /// True while the first load is in progress.
    private(set) var isLoading = true

    // MARK: - Config

    let profileID: UUID
    /// How many days of history to compute uptime over (default 30).
    let windowDays: Int
    /// How many segments to split the window into for the bar (default 30).
    let barSegments: Int

    private let modelContext: ModelContext

    init(profileID: UUID, modelContext: ModelContext, windowDays: Int = 30, barSegments: Int = 30) {
        self.profileID = profileID
        self.modelContext = modelContext
        self.windowDays = windowDays
        self.barSegments = barSegments
    }

    // MARK: - Public API

    /// Load/refresh from SwiftData. Call from .task modifier or .onAppear.
    func load() {
        let records = fetchRecords()
        compute(records: records)
        isLoading = false
    }

    // MARK: - Private

    private func fetchRecords() -> [ConnectivityRecord] {
        let since = Date().addingTimeInterval(Double(-windowDays) * 86400)
        let id = profileID
        let descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func compute(records: [ConnectivityRecord]) {
        let windowStart = Date().addingTimeInterval(Double(-windowDays) * 86400)
        let windowEnd = Date()
        let windowDuration = windowEnd.timeIntervalSince(windowStart)

        guard !records.isEmpty else {
            uptimePct = nil
            outageCount = 0
            uptimeBar = []
            latestLatencyMs = nil
            return
        }

        // Latest latency sample
        latestLatencyMs = records.filter { $0.isSample }.last?.latencyMs

        // Build timeline of transition events only
        let transitions = records.filter { !$0.isSample }

        // Compute total online duration using transition pairs.
        // Assume state before first record: if first transition is "came online",
        // we were offline from windowStart. If first transition is "went offline",
        // we were online from windowStart.
        var onlineSeconds: TimeInterval = 0
        var outages = 0
        var lastOnlineStart: Date? = nil

        let firstTransition = transitions.first
        if let first = firstTransition, first.isOnline {
            // Was offline before this — lastOnlineStart stays nil
        } else {
            // Was online before first transition (or no transitions at all)
            lastOnlineStart = windowStart
        }

        for record in transitions {
            if record.isOnline {
                // Came online
                lastOnlineStart = record.timestamp
            } else {
                // Went offline — count as an outage
                outages += 1
                if let start = lastOnlineStart {
                    onlineSeconds += record.timestamp.timeIntervalSince(start)
                    lastOnlineStart = nil
                }
            }
        }

        // Still online at window end
        if let start = lastOnlineStart {
            onlineSeconds += windowEnd.timeIntervalSince(start)
        }

        uptimePct = windowDuration > 0 ? min(100, onlineSeconds / windowDuration * 100) : 100
        outageCount = outages

        // Build bar segments
        let segmentDuration = windowDuration / Double(barSegments)
        var bar: [Bool] = []
        for i in 0..<barSegments {
            let segStart = windowStart.addingTimeInterval(Double(i) * segmentDuration)
            let segEnd = segStart.addingTimeInterval(segmentDuration)
            let onlineInSeg = onlineSecondsInSegment(
                from: segStart, to: segEnd,
                transitions: transitions,
                windowStart: windowStart
            )
            bar.append(onlineInSeg >= segmentDuration * 0.5)
        }
        uptimeBar = bar
    }

    /// Compute online seconds within [segStart, segEnd] using the transition list.
    private func onlineSecondsInSegment(
        from segStart: Date,
        to segEnd: Date,
        transitions: [ConnectivityRecord],
        windowStart: Date
    ) -> TimeInterval {
        // Determine the online state at the start of this segment
        let before = transitions.filter { $0.timestamp <= segStart }
        var isOnlineAtSegStart: Bool
        if let last = before.last {
            isOnlineAtSegStart = last.isOnline
        } else {
            // No transitions before this segment — check first transition to infer initial state
            let firstTransition = transitions.first
            isOnlineAtSegStart = firstTransition.map { !$0.isOnline } ?? true
        }

        let inSeg = transitions.filter { $0.timestamp > segStart && $0.timestamp < segEnd }
        var total: TimeInterval = 0
        var cursor = segStart
        var currentlyOnline = isOnlineAtSegStart

        for t in inSeg {
            if currentlyOnline {
                total += t.timestamp.timeIntervalSince(cursor)
            }
            cursor = t.timestamp
            currentlyOnline = t.isOnline
        }
        if currentlyOnline {
            total += segEnd.timeIntervalSince(cursor)
        }
        return total
    }
}
