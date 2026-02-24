import Foundation
import NetworkScanKit

// ScanDiff is declared in ServiceProtocols.swift.
// This file adds convenience helpers used by ScheduledScanViewModel and ScanChangeAlertView.

extension ScanDiff {
    /// Whether any device changes were detected.
    public var hasChanges: Bool {
        !newDevices.isEmpty || !removedDevices.isEmpty || !changedDevices.isEmpty
    }

    /// Total count of all changed entries.
    public var totalChanges: Int {
        newDevices.count + removedDevices.count + changedDevices.count
    }

    /// Short human-readable description suitable for notifications and UI summaries.
    public var summaryText: String {
        var parts: [String] = []
        if !newDevices.isEmpty     { parts.append("\(newDevices.count) new") }
        if !removedDevices.isEmpty { parts.append("\(removedDevices.count) offline") }
        if !changedDevices.isEmpty { parts.append("\(changedDevices.count) changed") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}
