import Foundation
import NetMonitorCore

// MARK: - Health samples (#491 D10)

extension BackgroundTaskService {
    /// Measures the health score of this device's network and saves it to the health history,
    /// flushed to disk before returning, so the refresh task can complete (and iOS suspend the
    /// app) without losing it. With no local network, or once the task is cancelled, nothing is
    /// saved: the expiration handler may already have completed the task.
    func recordHealthSample(
        probe: HealthSampleProbe = HealthSampleProbe(),
        store: HealthScoreHistoryStore = .shared,
        networkProfileID: UUID? = HealthSampleProbe.localNetworkProfileID(),
        isCancelled: () -> Bool
    ) async {
        guard let networkProfileID, !isCancelled() else { return }
        let reading = await probe.measure()
        guard !isCancelled() else { return }
        store.record(reading.score, networkProfileID: networkProfileID)
        store.flush()
    }
}
