import Foundation
import NetworkScanKit
import SwiftData
import os

/// Moves serials that label capture kept as `Serial:` notes lines (#456) into the serial field
/// (#561, design v3.1 §10). It runs after launch in a normal context, not as a schema migration
/// stage, and is safe to rerun:
///
/// 1. ``adoptSerials(in:save:)``: a row without a serial takes the value of its first
///    `Serial: ` line that has one, as ``IdentitySource/userConfirmed``. Saved.
/// 2. ``removeAdoptedLines(in:save:)``: from each row's *current* notes, every `Serial: ` line
///    whose trimmed value is its saved serial goes (identical duplicates are redundant with the field). A line
///    naming a different serial stays. Saved.
///
/// A line is removed only after the field it moved into was saved, so a crash between the two
/// steps leaves the line, and the next run removes it. A failed save rolls the context back and
/// throws.
@MainActor
public enum SerialNotesMigration {
    static let prefix = LabelCapture.serialPrefix
    private static let logger = Logger(subsystem: "com.netmonitor", category: "SerialNotesMigration")

    /// The launch pass, in its own context on the app's container. A failure is logged and retried
    /// at the next launch; the notes are left as they were.
    public static func runAtLaunch(on container: ModelContainer) {
        do {
            try run(in: ModelContext(container))
        } catch {
            logger.error("Moving serial notes lines failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func run(in context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try adoptSerials(in: context, save: save)
        try removeAdoptedLines(in: context, save: save)
    }

    static func adoptSerials(in context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try applying(in: context, save: save) { rows in
            for row in rows where row.serialNumber?.isEmpty ?? true {
                guard let serial = firstSerial(in: row.notes) else { continue }
                row.serialNumber = serial
                row.serialSource = IdentitySource.userConfirmed.rawValue
            }
        }
    }

    static func removeAdoptedLines(in context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try applying(in: context, save: save) { rows in
            for row in rows {
                guard let serial = row.serialNumber, !serial.isEmpty, let notes = row.notes else { continue }
                let lines = notes.components(separatedBy: "\n")
                let kept = lines.filter { serialValue(of: $0) != serial }
                guard kept.count != lines.count else { continue }
                let joined = kept.joined(separator: "\n")
                row.notes = joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
            }
        }
    }

    /// The trimmed value of the first `Serial: ` line that has one.
    static func firstSerial(in notes: String?) -> String? {
        (notes ?? "").components(separatedBy: "\n").lazy.compactMap(serialValue(of:)).first
    }

    /// The trimmed value of a `Serial: ` line; nil for any other line or an empty value.
    static func serialValue(of line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Fetches every row freshly, applies `change`, and saves only when something changed.
    private static func applying(
        in context: ModelContext, save: (ModelContext) throws -> Void, _ change: ([LocalDevice]) -> Void
    ) throws {
        do {
            try change(context.fetch(FetchDescriptor<LocalDevice>()))
            if context.hasChanges {
                try save(context)
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
