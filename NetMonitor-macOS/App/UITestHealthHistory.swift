import Foundation
import NetMonitorCore

/// Health-history fixtures for macOS UI tests and AX evidence runs (#491 S5).
enum UITestHealthHistory {
    /// With `--seed-health-samples`, replaces the health history with five samples for the Mac's
    /// network (`HealthScoreHistoryStore.seedForUITests`).
    @MainActor
    static func seedIfRequested(
        networkProfileID: UUID?,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        store: HealthScoreHistoryStore = .shared
    ) {
        guard arguments.contains("--seed-health-samples"), let networkProfileID else { return }
        store.seedForUITests(count: HealthScoreHistoryStore.uiTestSeedScores.count, networkProfileID: networkProfileID)
    }
}
