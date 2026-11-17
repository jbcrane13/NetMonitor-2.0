import Foundation
import NetMonitorCore
import SwiftData
import os

/// Handles data maintenance tasks like pruning expired records
@MainActor
final class DataMaintenanceService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "DataMaintenanceService")
    private init() {}

    /// Deletes ToolResult and SpeedTestResult records and timeline events older than the
    /// configured retention period (#395 added timeline events)
    static func pruneExpiredData(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        eventService: NetworkEventService = .shared,
        now: Date = Date()
    ) {
        let retentionDays = defaults.object(forKey: AppSettings.Keys.dataRetentionDays) as? Int ?? 30
        guard retentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) ?? now

        do {
            try modelContext.delete(model: ToolResult.self, where: #Predicate { $0.timestamp < cutoff })
        } catch {
            logger.error("Failed to prune old tool results: \(error)")
        }
        do {
            try modelContext.delete(model: SpeedTestResult.self, where: #Predicate { $0.timestamp < cutoff })
        } catch {
            logger.error("Failed to prune old speed test results: \(error)")
        }
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after pruning: \(error)")
        }
        eventService.removeEvents(olderThan: cutoff)
    }
}
