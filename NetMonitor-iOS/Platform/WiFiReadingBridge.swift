import Foundation

/// In-process bridge that hands a ``ShortcutsWiFiReading`` from the
/// ``SaveWiFiReadingIntent`` perform() call to any waiting
/// ``ShortcutsWiFiProvider`` continuation.
///
/// The intent runs on `@MainActor` (via `openAppWhenRun`), so `publish(_:)`
/// is always called on the main actor. All mutation is therefore safe without
/// additional locks.
@MainActor
final class WiFiReadingBridge {

    // MARK: - Singleton

    static let shared = WiFiReadingBridge()

    private init() {}

    #if DEBUG
    /// Test-only initializer. Unit tests need isolated instances; production
    /// code must continue to use ``shared``.
    static func makeForTesting() -> WiFiReadingBridge { WiFiReadingBridge() }
    #endif

    // MARK: - Storage

    private var pendingContinuations: [UUID: CheckedContinuation<ShortcutsWiFiReading?, Never>] = [:]

    // MARK: - Internal constants (shared with ShortcutsWiFiProvider)

    static let appGroupID = "group.com.blakemiller.netmonitor"
    static let readingFilename = "wifi-reading.json"

    // MARK: - Public API

    /// Suspends until an intent delivers a reading or `timeout` elapses.
    ///
    /// - Parameter timeout: Maximum seconds to wait. Defaults to provider's default.
    /// - Returns: The reading, or `nil` on timeout.
    func waitForReading(timeout: TimeInterval) async -> ShortcutsWiFiReading? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pendingContinuations[id] = continuation

            // Timeout task — resumes nil if the continuation is still pending.
            Task<Void, Never> {
                try? await Task.sleep(for: .seconds(timeout))
                // Only resume if it hasn't been claimed by publish().
                if let c = pendingContinuations.removeValue(forKey: id) {
                    c.resume(returning: nil)
                }
            }
        }
    }

    /// Called from ``SaveWiFiReadingIntent.perform()`` with the parsed reading.
    /// Resolves all pending continuations immediately.
    func publish(_ reading: ShortcutsWiFiReading) {
        let snapshot = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in snapshot.values {
            continuation.resume(returning: reading)
        }
    }

    /// Writes the reading as JSON to the App Group shared container.
    /// Belt-and-suspenders backup for the cold-launch / in-process-miss edge case.
    static func writeBackup(_ reading: ShortcutsWiFiReading) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let fileURL = containerURL.appendingPathComponent(readingFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(reading) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
