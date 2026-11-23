import Foundation
import Observation
import os

// MARK: - HealthScoreHistoryStore

/// Saved health scores per network, for the health-over-time charts (#491 D10).
///
/// `record` keeps at most one sample per network per `throttleInterval` (15 minutes), so the
/// dashboard refreshing and the timers sampling never pile up near-identical points. The newest
/// `sampleCeiling` samples are kept; the retention setting prunes older ones through
/// `removeSamples(olderThan:)`.
///
/// `shared` saves to `health-score-history.json` in `HistoryFileLocation.current`, as a
/// `JSONHistoryFile` like the event log (#491 D2). Call `flush()` before the app is suspended or
/// quits. Other instances are in memory unless built with a file URL.
///
/// `revision` changes with every change and is observable, so a chart reading `samples(for:)`
/// through it redraws when another writer (the macOS timer) records a sample.
@Observable
public final class HealthScoreHistoryStore: @unchecked Sendable {

    /// The app's health history.
    public static let shared: HealthScoreHistoryStore = {
        let location = HistoryFileLocation.current
        location.resetIfRequested(fileNamed: fileName)
        return HealthScoreHistoryStore(fileURL: location.fileURL(named: fileName))
    }()

    public static let fileName = "health-score-history.json"
    /// The most samples kept, across all networks (#491 D3).
    public static let sampleCeiling = 20_000
    /// The shortest gap between two samples of one network.
    public static let throttleInterval: TimeInterval = 15 * 60

    /// Bumped after every change; read it to observe the store. The apps change the store on
    /// the main actor, which is where the views observe it.
    public private(set) var revision = 0

    @ObservationIgnored private let lock = NSLock()
    /// Oldest first.
    @ObservationIgnored private var _samples: [HealthScoreSample] = []
    @ObservationIgnored private let file: JSONHistoryFile<HealthScoreSample>?
    @ObservationIgnored private let ceiling: Int
    private static let logger = Logger(subsystem: "com.netmonitor", category: "HealthScoreHistoryStore")

    /// An empty, in-memory store. Nothing it records is saved.
    public init(ceiling: Int = sampleCeiling) {
        file = nil
        self.ceiling = ceiling
    }

    /// A store saved to `fileURL`, loading what is already there. Changes are written
    /// `debounce` seconds after they happen, or at `flush()`.
    public init(fileURL: URL, debounce: TimeInterval = 1, ceiling: Int = sampleCeiling) {
        let file = JSONHistoryFile<HealthScoreSample>(
            fileURL: fileURL, debounce: debounce, kind: "health history",
            logger: Self.logger, queueLabel: "com.netmonitor.HealthScoreHistoryStore"
        )
        self.file = file
        self.ceiling = ceiling
        let saved = file.exists ? file.read(using: JSONHistoryFile.decodeLossily) : []
        _samples = Array(saved.sorted { $0.timestamp < $1.timestamp }.suffix(ceiling))
    }

    // MARK: - Recording

    /// Saves `score` for the network, unless that network already has a sample less than
    /// `throttleInterval` before or after `date`. Returns whether it was saved.
    @discardableResult
    public func record(_ score: NetworkHealthScore, networkProfileID: UUID, at date: Date = Date()) -> Bool {
        let saved = lock.withLock {
            let tooClose = _samples.contains {
                $0.networkProfileID == networkProfileID && abs($0.timestamp.timeIntervalSince(date)) < Self.throttleInterval
            }
            guard !tooClose else { return false }
            let sample = HealthScoreSample(networkProfileID: networkProfileID, timestamp: date, score: score.score, grade: score.grade)
            let index = _samples.lastIndex { $0.timestamp <= date }.map { $0 + 1 } ?? 0
            _samples.insert(sample, at: index)
            if _samples.count > ceiling {
                _samples.removeFirst(_samples.count - ceiling)
            }
            file?.scheduleWrite(_samples)
            return true
        }
        if saved {
            revision += 1
        }
        return saved
    }

    // MARK: - Reading

    /// The network's samples, oldest first.
    public func samples(for networkProfileID: UUID) -> [HealthScoreSample] {
        _ = revision
        return lock.withLock { _samples.filter { $0.networkProfileID == networkProfileID } }
    }

    // MARK: - Pruning

    /// Removes samples older than `cutoff`, for the history retention setting, and saves at once.
    public func removeSamples(olderThan cutoff: Date) {
        let changed = lock.withLock {
            let before = _samples.count
            _samples.removeAll { $0.timestamp < cutoff }
            guard _samples.count != before else { return false }
            file?.scheduleWrite(_samples)
            return true
        }
        if changed {
            revision += 1
            flush()
        }
    }

    /// Removes every sample and saves at once.
    public func clearAll() {
        lock.withLock {
            _samples.removeAll()
            file?.scheduleWrite(_samples)
        }
        revision += 1
        flush()
    }

    /// Writes any change still waiting for the debounce, and returns when it is saved.
    public func flush() {
        file?.flush()
    }
}

// MARK: - UI-test fixture

public extension HealthScoreHistoryStore {
    /// The scores both apps' UI tests seed, oldest first (#491 S5).
    static let uiTestSeedScores: [(score: Int, grade: String)] = [(72, "C"), (81, "B"), (64, "D"), (88, "B"), (79, "C")]

    /// Replaces the history with `count` samples for `networkProfileID` (scores from
    /// `uiTestSeedScores`, repeated past five), an hour apart. The newest is a minute old, so the
    /// dashboard's own refresh at launch is throttled and the chart shows exactly these points.
    func seedForUITests(count: Int, networkProfileID: UUID, now: Date = Date()) {
        clearAll()
        for index in 0..<count {
            let seed = Self.uiTestSeedScores[index % Self.uiTestSeedScores.count]
            let hoursAgo = Double(count - 1 - index)
            record(
                NetworkHealthScore(score: seed.score, grade: seed.grade),
                networkProfileID: networkProfileID,
                at: now.addingTimeInterval(-60 - hoursAgo * 3600)
            )
        }
        flush()
    }
}
