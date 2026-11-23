import Foundation
import os

// MARK: - HistoryFileLocation

/// Where the app's JSON history files live (#491 D2), and whether this launch wipes them first.
///
/// Tests and evidence runs never touch the user's files: the unit-test host
/// (`XCTestConfigurationFilePath`) and `--in-memory-store` get a per-process temp directory, and
/// UI tests (`--uitesting`, iOS `--uitesting-reset`) get one fixed temp directory per app that
/// survives relaunch. `--reset-history-files`, or iOS `--uitesting-reset`, deletes the files
/// before they are loaded.
public struct HistoryFileLocation: Sendable, Equatable {
    public let directory: URL
    public let resetRequested: Bool

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
        let isUITest = arguments.contains("--uitesting") || arguments.contains("--uitesting-reset")
        let isPerProcess = environment["XCTestConfigurationFilePath"] != nil || arguments.contains("--in-memory-store")
        if isUITest {
            directory = temporaryDirectory.appending(path: "netmonitor-uitest-history", directoryHint: .isDirectory)
        } else if isPerProcess {
            directory = temporaryDirectory.appending(path: "netmonitor-history-\(processID)", directoryHint: .isDirectory)
        } else {
            directory = applicationSupportDirectory.appending(path: "NetMonitor", directoryHint: .isDirectory)
        }
        resetRequested = arguments.contains("--reset-history-files") || arguments.contains("--uitesting-reset")
    }

    /// The URL of `fileName` in this location, deleted first when this launch asked for a reset.
    public func fileURL(named fileName: String) -> URL {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        if resetRequested {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

// MARK: - NetworkEventStore

/// The JSON file behind `NetworkEventService.shared` (#491 D2): a newest-first array of events.
///
/// Reads skip elements that don't decode instead of dropping the whole log. Writes are
/// coalesced: `scheduleWrite` keeps only the latest snapshot and writes it on a private
/// serial queue after `debounce` seconds; `flush()` writes it now. Every write is atomic.
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
            do {
                return try Self.decodeLossily(Data(contentsOf: fileURL))
            } catch {
                Self.logger.error("Could not read the event file: \(error.localizedDescription)")
                return []
            }
        }
        guard let legacy = legacyDefaults?.data(forKey: legacyKey) else { return [] }
        let migrated = Self.decodeLossily(legacy)
        if write(migrated) {
            Self.logger.info("Migrated \(migrated.count) events from UserDefaults")
        }
        return migrated
    }

    /// Decodes a JSON array element by element, skipping the elements that fail.
    static func decodeLossily(_ data: Data) -> [NetworkEvent] {
        guard let elements = try? JSONDecoder().decode([LossyEvent].self, from: data) else {
            logger.error("The event file is not a JSON array; starting empty")
            return []
        }
        let unknownTypes = Set(elements.compactMap(\.unknownType))
        if !unknownTypes.isEmpty {
            logger.debug("Skipped events of unknown types: \(unknownTypes.sorted().joined(separator: ", "))")
        }
        return elements.compactMap(\.event)
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
        if let snapshot {
            write(snapshot)
        }
    }

    @discardableResult
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
