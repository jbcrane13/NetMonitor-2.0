import Foundation
import Network
import os

// MARK: - Speed Test History (#398)

/// One saved speed test result, used for the 7-day trend.
public struct SpeedTestHistoryEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double

    public init(timestamp: Date, downloadMbps: Double, uploadMbps: Double, pingMs: Double) {
        self.timestamp = timestamp
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
    }
}

public enum SpeedTestTrend {
    /// Entries from the last 7 days before `now`, oldest first.
    public static func lastSevenDays(_ entries: [SpeedTestHistoryEntry], now: Date) -> [SpeedTestHistoryEntry] {
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        return entries
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

/// Saves speed test results as a small JSON file. The Mac uses this instead of
/// SwiftData so the versioned SwiftData schema doesn't change.
public final class SpeedTestHistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/<bundle id>/speed-test-history.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NetMonitor", isDirectory: true)
            .appendingPathComponent("speed-test-history.json")
    }

    public func entries() -> [SpeedTestHistoryEntry] {
        lock.withLock { load() }
    }

    public func append(_ entry: SpeedTestHistoryEntry) {
        lock.withLock {
            var all = load()
            all.append(entry)
            save(all)
        }
    }

    /// Deletes entries older than `cutoff`.
    public func prune(olderThan cutoff: Date) {
        lock.withLock {
            let all = load()
            let kept = all.filter { $0.timestamp >= cutoff }
            if kept.count != all.count {
                save(kept)
            }
        }
    }

    /// A missing file means no history yet. A file that can't be read or decoded is moved
    /// aside as `<name>.corrupt-<date>` so the next save can't overwrite it, and history
    /// starts fresh.
    private func load() -> [SpeedTestHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([SpeedTestHistoryEntry].self, from: data)
        } catch {
            quarantine(error)
            return []
        }
    }

    private func quarantine(_ error: any Error) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = fileURL.appendingPathExtension("corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            Self.logger.error("Speed test history unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
        } catch {
            Self.logger.error("Speed test history unreadable and couldn't be moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "com.netmonitor", category: "SpeedTestHistory")

    private func save(_ entries: [SpeedTestHistoryEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // A failed write only loses trend history; the next run tries again.
        }
    }
}

// MARK: - Network Cost

/// Whether the current path costs the user: cellular or a personal hotspot (expensive),
/// or Low Data Mode (constrained).
public struct NetworkCost: Sendable, Equatable {
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(isExpensive: Bool, isConstrained: Bool) {
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    public var isMetered: Bool { isExpensive || isConstrained }
    public static let free = NetworkCost(isExpensive: false, isConstrained: false)
}

/// Keeps the latest `NWPath` cost flags for the scheduler to read.
public final class NetworkCostMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latest: NetworkCost = .free

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.withLock {
                self?.latest = NetworkCost(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.netmonitor.speedtest.cost", qos: .utility))
    }

    deinit { monitor.cancel() }

    public var current: NetworkCost {
        lock.withLock { latest }
    }
}

// MARK: - Scheduler

/// Runs a speed test every few hours while the app is open (#398). Off by default.
///
/// The schedule is stored in hours under `intervalKey`; 0 means off. The timer wakes
/// every `checkInterval` and runs a test when the last one is at least one interval old,
/// so a schedule carries over app restarts. A test never starts while one is running,
/// or on a metered path unless `allowMeteredKey` is on.
@MainActor
public final class ScheduledSpeedTestRunner {
    nonisolated public static let intervalKey = "netmonitor.speedTest.scheduleHours"
    nonisolated public static let intervalOptions = [0, 1, 3, 6, 12, 24]
    /// "Allow on cellular or hotspot". Off by default: scheduled tests skip metered paths.
    nonisolated public static let allowMeteredKey = "netmonitor.speedTest.allowOnCellular"

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let checkInterval: Duration
    private let lastRunAt: @MainActor () -> Date?
    private let isRunning: @MainActor () -> Bool
    private let runTest: @MainActor () async -> Void
    private let networkCost: @Sendable () -> NetworkCost
    private var loopTask: Task<Void, Never>?
    private var defaultsObserver: (any NSObjectProtocol)?
    /// When this runner last started a test, so a failing test isn't retried every check.
    private var lastAttemptAt: Date?

    /// Hours between tests for the running timer, or nil when off.
    public private(set) var activeIntervalHours: Int?

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        checkInterval: Duration = .seconds(300),
        lastRunAt: @escaping @MainActor () -> Date?,
        isRunning: @escaping @MainActor () -> Bool,
        networkCost: (@Sendable () -> NetworkCost)? = nil,
        runTest: @escaping @MainActor () async -> Void
    ) {
        if let networkCost {
            self.networkCost = networkCost
        } else {
            let monitor = NetworkCostMonitor()
            self.networkCost = { monitor.current }
        }
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.checkInterval = checkInterval
        self.lastRunAt = lastRunAt
        self.isRunning = isRunning
        self.runTest = runTest
    }

    /// Saved schedule in hours; 0 or less means off.
    public var configuredIntervalHours: Int {
        defaults.integer(forKey: Self.intervalKey)
    }

    public func start() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    public func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        loopTask?.cancel()
        loopTask = nil
        activeIntervalHours = nil
    }

    /// Restarts the timer when the saved schedule differs from the running one.
    public func reload() {
        let hours = configuredIntervalHours
        let wanted: Int? = hours > 0 ? hours : nil
        guard wanted != activeIntervalHours else { return }
        loopTask?.cancel()
        loopTask = nil
        activeIntervalHours = wanted
        guard wanted != nil else { return }
        let sleep = sleep
        let checkInterval = checkInterval
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                await sleep(checkInterval)
            }
        }
    }

    /// Whether a scheduled test is due at `now`.
    public func isDue() -> Bool {
        guard let hours = activeIntervalHours else { return false }
        let last = [lastRunAt(), lastAttemptAt].compactMap(\.self).max()
        guard let last else { return true }
        return now().timeIntervalSince(last) >= TimeInterval(hours) * 3600
    }

    /// False on a cellular, hotspot or Low Data Mode path unless the user allowed it.
    /// Manual tests don't check this.
    public func isNetworkAllowed() -> Bool {
        defaults.bool(forKey: Self.allowMeteredKey) || !networkCost().isMetered
    }

    /// Runs a test when one is due, none is running and the network allows it.
    /// Returns true when a test ran. A skipped metered check is retried on the next tick.
    @discardableResult
    public func tick() async -> Bool {
        guard !Task.isCancelled, isDue(), !isRunning(), isNetworkAllowed() else { return false }
        lastAttemptAt = now()
        await runTest()
        return true
    }
}
