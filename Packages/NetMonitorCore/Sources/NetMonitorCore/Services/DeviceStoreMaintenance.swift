import Foundation
import SwiftData
import os

/// The device-store passes both apps run once the store is open (#561, #594): device groups made
/// consistent (`DeviceGroupWriter.repair()`), then serial notes lines moved into the serial field
/// (`SerialNotesMigration`). Each runs in its own context; a failure is logged and retried at the
/// next launch, leaving the rows as they were.
///
/// The serial pass runs **once per store**: when it succeeds a marker is saved for the store's file,
/// so a `Serial:` line the user types into notes later stays in the notes. An in-memory store has
/// nothing to protect and runs it every time.
@MainActor
public enum DeviceStoreMaintenance {
    private static let logger = Logger(subsystem: "com.netmonitor", category: "DeviceStoreMaintenance")
    static let serialMarkerPrefix = "serialNotesMigrated:"

    public static func runAtLaunch(on container: ModelContainer, defaults: UserDefaults = .standard) {
        do {
            try DeviceGroupWriter(container: container).repair()
        } catch {
            logger.error("Repairing device groups failed: \(error.localizedDescription, privacy: .public)")
        }
        let marker = serialMarker(for: container)
        guard marker.map({ !defaults.bool(forKey: $0) }) ?? true else { return }
        do {
            try SerialNotesMigration.run(in: ModelContext(container))
            if let marker {
                defaults.set(true, forKey: marker)
            }
        } catch {
            logger.error("Moving serial notes lines failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The defaults key marking `container`'s store done; nil for an in-memory store.
    static func serialMarker(for container: ModelContainer) -> String? {
        guard let configuration = container.configurations.first, !configuration.isStoredInMemoryOnly else { return nil }
        return serialMarkerPrefix + configuration.url.standardizedFileURL.path
    }
}
