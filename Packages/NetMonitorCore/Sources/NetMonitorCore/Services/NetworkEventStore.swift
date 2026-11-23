import Foundation
import os

// MARK: - HistoryFileLocation

/// Where the app's JSON history files live (#491 D2), and whether this launch wipes them first.
///
/// Tests and evidence runs never touch the user's data:
/// - the unit-test host (`XCTestConfigurationFilePath`) and `--in-memory-store` get a
///   per-process temp directory and no legacy events to migrate;
/// - UI tests (`--uitesting`, iOS `--uitesting-reset`) get one fixed temp directory per app
///   that survives relaunch, and read legacy events from their own UserDefaults suite.
///
/// `--reset-history-files`, or iOS `--uitesting-reset`, asks for the files to be deleted before
/// they load; each store does that once with `resetIfRequested(fileNamed:)`.
public struct HistoryFileLocation: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case user, uiTest, perProcess
    }

    public let directory: URL
    public let resetRequested: Bool
    let kind: Kind

    /// The UserDefaults suite UI tests seed legacy events into, instead of the app's own defaults.
    public static let uiTestLegacyDefaultsSuite = "netmonitor.uitest-history"

    /// The location for this process's launch arguments and environment.
    public static let current = HistoryFileLocation(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    init(
        arguments: [String],
        environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        applicationSupportDirectory: URL = URL.applicationSupportDirectory,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        if arguments.contains("--uitesting") || arguments.contains("--uitesting-reset") {
            kind = .uiTest
            directory = temporaryDirectory.appending(path: "netmonitor-uitest-history", directoryHint: .isDirectory)
        } else if environment["XCTestConfigurationFilePath"] != nil || arguments.contains("--in-memory-store") {
            kind = .perProcess
            directory = temporaryDirectory.appending(path: "netmonitor-history-\(processID)", directoryHint: .isDirectory)
        } else {
            kind = .user
            directory = applicationSupportDirectory.appending(path: "NetMonitor", directoryHint: .isDirectory)
        }
        resetRequested = arguments.contains("--reset-history-files") || arguments.contains("--uitesting-reset")
    }

    /// Where builds before #491 kept history, to migrate from: the app's own defaults normally,
    /// the UI-test suite under UI tests, and nothing in a unit-test host or in-memory run.
    public var legacyDefaults: UserDefaults? {
        switch kind {
        case .user: .standard
        case .uiTest: UserDefaults(suiteName: Self.uiTestLegacyDefaultsSuite)
        case .perProcess: nil
        }
    }

    /// The URL of `fileName` in this location. A lookup only; it never deletes.
    public func fileURL(named fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Deletes `fileName` when this launch asked for a reset. Each store calls it once, before its
    /// first load: `NetworkEventService.shared` for the event file, and S5's health store for its own.
    public func resetIfRequested(fileNamed fileName: String) {
        guard resetRequested else { return }
        try? FileManager.default.removeItem(at: fileURL(named: fileName))
    }
}

// MARK: - NetworkEventStore

/// The JSON file behind `NetworkEventService.shared` (#491 D2): a newest-first array of events.
///
/// Reads skip elements that don't decode instead of dropping the whole log. A file that can't be
/// read, or isn't a JSON array, is moved aside to `network-events.corrupt-<time>.json` (only the
/// latest is kept) rather than overwritten. Writes are coalesced: `scheduleWrite` keeps only the
/// latest snapshot and writes it on a private serial queue after `debounce` seconds; `flush()`
/// writes it now. Every write is atomic. A snapshot whose write fails is kept for the next flush
/// unless a newer one replaces it.
///
/// Up to `debounce` (1 s in the app) of events can be lost when the app crashes or is killed
/// before the write; the apps flush when they go to the background or quit (#491, accepted risk).
final class NetworkEventStore: @unchecked Sendable {
    static let fileName = "network-events.json"
    private static let logger = Logger(subsystem: "com.netmonitor", category: "NetworkEventStore")

    let fileURL: URL
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "com.netmonitor.NetworkEventStore", qos: .utility)
    private let lock = NSLock()
    private var pending: [NetworkEvent]?
    private var isWriteScheduled = false

    init(fileURL: URL, debounce: TimeInterval) {
        self.fileURL = fileURL
        self.debounce = debounce
    }

    // MARK: Loading

    /// The saved events. With no file yet, migrates the legacy UserDefaults blob: it is decoded
    /// the same lossy way, written to the file at once, and left in place, so an older build
    /// still finds it and a failed write is retried at the next launch.
    func load(legacyDefaults: UserDefaults?, legacyKey: String) -> [NetworkEvent] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let events = Self.decodeLossily(data) {
                return events
            }
            moveAsideUnreadableFile()
            return []
        }
        guard let legacy = legacyDefaults?.data(forKey: legacyKey) else { return [] }
        let migrated = Self.decodeLossily(legacy) ?? []
        if write(migrated) {
            Self.logger.info("Migrated \(migrated.count) events from UserDefaults")
        }
        return migrated
    }

    /// Decodes a JSON array element by element, skipping the elements that fail. Nil when the
    /// data isn't a JSON array at all.
    static func decodeLossily(_ data: Data) -> [NetworkEvent]? {
        guard let elements = try? JSONDecoder().decode([LossyEvent].self, from: data) else { return nil }
        let unknownTypes = Set(elements.compactMap(\.unknownType))
        if !unknownTypes.isEmpty {
            logger.debug("Skipped events of unknown types: \(unknownTypes.sorted().joined(separator: ", "))")
        }
        return elements.compactMap(\.event)
    }

    /// Keeps an unreadable file for inspection instead of overwriting it at the next write,
    /// replacing any earlier one.
    private func moveAsideUnreadableFile() {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let prefix = fileURL.deletingPathExtension().lastPathComponent + ".corrupt-"
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix(prefix) {
            try? manager.removeItem(at: directory.appending(path: name))
        }
        let aside = directory.appending(path: "\(prefix)\(Int(Date().timeIntervalSince1970)).json")
        do {
            try manager.moveItem(at: fileURL, to: aside)
            Self.logger.error("The event file could not be read; moved it aside and started empty")
        } catch {
            Self.logger.error("The event file could not be read or moved aside: \(error.localizedDescription)")
        }
    }

    // MARK: Writing

    /// Saves `events` after the debounce, replacing any snapshot still waiting.
    func scheduleWrite(_ events: [NetworkEvent]) {
        let shouldSchedule = lock.withLock {
            pending = events
            defer { isWriteScheduled = true }
            return !isWriteScheduled
        }
        guard shouldSchedule else { return }
        queue.asyncAfter(deadline: .now() + debounce) { [weak self] in self?.writePending() }
    }

    /// Writes the waiting snapshot now, on the store's queue, and returns when it is on disk.
    func flush() {
        queue.sync { writePending() }
    }

    private func writePending() {
        let snapshot: [NetworkEvent]? = lock.withLock {
            defer {
                pending = nil
                isWriteScheduled = false
            }
            return pending
        }
        guard let snapshot, !write(snapshot) else { return }
        // Keep it for the next flush, unless a newer change has replaced it meanwhile.
        lock.withLock {
            if pending == nil {
                pending = snapshot
            }
        }
    }

    private func write(_ events: [NetworkEvent]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
            return true
        } catch {
            Self.logger.error("Could not write the event file: \(error.localizedDescription)")
            return false
        }
    }
}

/// One array element: the event, or nil when it doesn't decode.
private struct LossyEvent: Decodable {
    let event: NetworkEvent?
    /// The element's `type` when this build doesn't know it.
    let unknownType: String?

    private struct TypeOnly: Decodable { let type: String }

    init(from decoder: any Decoder) throws {
        event = try? NetworkEvent(from: decoder)
        if event == nil, let raw = try? TypeOnly(from: decoder).type, NetworkEventType(rawValue: raw) == nil {
            unknownType = raw
        } else {
            unknownType = nil
        }
    }
}
