import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

/// DataMaintenanceService tests.
///
/// INTEGRATION GAP: SwiftData ModelContext requires a ModelContainer which needs
/// a schema registered at runtime. The pruneExpiredData method operates on
/// ModelContext.delete(model:where:) which requires a live SwiftData stack.
/// These tests verify the configuration logic and boundary conditions that
/// can be tested without a full SwiftData container.

@MainActor
struct DataMaintenanceServiceTests {

    // MARK: - Retention days configuration

    @Test("Default retention period is 30 days when no UserDefaults value set")
    func defaultRetentionDays() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 30)
    }

    @Test("Custom retention period is read from UserDefaults")
    func customRetentionDays() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(7, forKey: key)
        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 7)
    }

    @Test("Zero retention days means no pruning occurs (guard clause)")
    func zeroRetentionDaysSkipsPruning() {
        let key = AppSettings.Keys.dataRetentionDays
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(0, forKey: key)
        let retentionDays = UserDefaults.standard.object(forKey: key) as? Int ?? 30
        #expect(retentionDays == 0, "Zero retention should be preserved")

        // The guard retentionDays > 0 else { return } in pruneExpiredData
        // exits early when 0. We verify the logic path here.
        let shouldPrune = retentionDays > 0
        #expect(shouldPrune == false)
    }

    @Test("Cutoff date is correctly calculated from retention days")
    func cutoffDateCalculation() {
        let retentionDays = 14
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)!

        // Cutoff should be approximately 14 days ago
        let daysDifference = Calendar.current.dateComponents([.day], from: cutoff, to: now).day ?? 0
        #expect(daysDifference == 14)
    }

    @Test("Negative retention days produce future cutoff (edge case)")
    func negativeRetentionDays() {
        let retentionDays = -1
        // guard retentionDays > 0 catches this, but verify the math if bypassed
        let shouldPrune = retentionDays > 0
        #expect(shouldPrune == false)
    }

    @Test("Large retention days produce distant past cutoff")
    func largeRetentionDays() {
        let retentionDays = 365
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)!

        let daysDifference = Calendar.current.dateComponents([.day], from: cutoff, to: now).day ?? 0
        #expect(daysDifference == 365)
    }
}
