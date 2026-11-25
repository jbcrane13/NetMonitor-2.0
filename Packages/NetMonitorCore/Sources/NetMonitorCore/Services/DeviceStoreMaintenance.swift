import Foundation
import SwiftData
import os

/// The device-store passes both apps run once the store is open (#561, #594): device groups made
/// consistent (`DeviceGroupWriter.repair()`), then serial notes lines moved into the serial field
/// (`SerialNotesMigration`). Each runs in its own context; a failure is logged and retried at the
/// next launch, leaving the rows as they were.
@MainActor
public enum DeviceStoreMaintenance {
    private static let logger = Logger(subsystem: "com.netmonitor", category: "DeviceStoreMaintenance")

    public static func runAtLaunch(on container: ModelContainer) {
        do {
            try DeviceGroupWriter(context: ModelContext(container)).repair()
        } catch {
            logger.error("Repairing device groups failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try SerialNotesMigration.run(in: ModelContext(container))
        } catch {
            logger.error("Moving serial notes lines failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
