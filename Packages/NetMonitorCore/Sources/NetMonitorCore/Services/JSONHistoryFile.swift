import Foundation
import os

/// A history saved as one JSON array file (#491 D2): the storage behind `NetworkEventStore` and
/// `HealthScoreHistoryStore`.
///
/// Reads skip elements that don't decode instead of dropping the whole file. A file that can't be
/// read, or isn't a JSON array, is moved aside to `<name>.corrupt-<time>.json` (only the latest is
/// kept) rather than overwritten. Writes are coalesced: `scheduleWrite` keeps only the latest
/// snapshot and writes it on a private serial queue after `debounce` seconds; `flush()` writes it
/// now. Every write is atomic. A snapshot whose write fails is kept for the next flush unless a
/// newer one replaces it.
final class JSONHistoryFile<Element: Codable & Sendable>: @unchecked Sendable {
    let fileURL: URL
    private let debounce: TimeInterval
    /// What the file holds, for log messages ("event" → "The event file …").
    private let kind: String
    private let logger: Logger
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [Element]?
    private var isWriteScheduled = false

    init(fileURL: URL, debounce: TimeInterval, kind: String, logger: Logger, queueLabel: String) {
        self.fileURL = fileURL
        self.debounce = debounce
        self.kind = kind
        self.logger = logger
        queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    // MARK: Reading

    var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// The saved elements, decoded by `decoder` (nil when the data isn't usable). An unreadable
    /// file is moved aside and reads as empty. Call only when `exists`.
    func read(using decoder: (Data) -> [Element]?) -> [Element] {
        if let data = try? Data(contentsOf: fileURL), let elements = decoder(data) {
            return elements
        }
        moveAsideUnreadableFile()
        return []
    }

    /// Decodes a JSON array element by element, skipping the elements that fail. Nil when the
    /// data isn't a JSON array at all.
    static func decodeLossily(_ data: Data) -> [Element]? {
        (try? JSONDecoder().decode([LossyElement<Element>].self, from: data))?.compactMap(\.element)
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
            logger.error("The \(self.kind, privacy: .public) file could not be read; moved it aside and started empty")
        } catch {
            logger.error("The \(self.kind, privacy: .public) file could not be read or moved aside: \(error.localizedDescription)")
        }
    }

    // MARK: Writing

    /// Saves `elements` after the debounce, replacing any snapshot still waiting.
    func scheduleWrite(_ elements: [Element]) {
        let shouldSchedule = lock.withLock {
            pending = elements
            defer { isWriteScheduled = true }
            return !isWriteScheduled
        }
        guard shouldSchedule else { return }
        queue.asyncAfter(deadline: .now() + debounce) { [weak self] in self?.writePending() }
    }

    /// Writes the waiting snapshot now, on the file's queue, and returns when it is on disk.
    func flush() {
        queue.sync { writePending() }
    }

    private func writePending() {
        let snapshot: [Element]? = lock.withLock {
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

    /// Writes `elements` now, on the caller's thread. Returns whether it worked.
    func write(_ elements: [Element]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(elements).write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Could not write the \(self.kind, privacy: .public) file: \(error.localizedDescription)")
            return false
        }
    }
}

/// One array element: the element, or nil when it doesn't decode.
private struct LossyElement<Element: Decodable>: Decodable {
    let element: Element?

    init(from decoder: any Decoder) throws {
        element = try? Element(from: decoder)
    }
}
