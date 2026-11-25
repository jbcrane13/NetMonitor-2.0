import Foundation
import NetMonitorCore
import Observation

/// What every saved device's status means now on iPhone and iPad (#583): each network's last scan,
/// read once per refresh, as of the presence clock. Views read `snapshot` from the environment.
/// It refreshes when `DeviceRecordUpdater` saves a scan, so rows never read "Not checked
/// recently" after a fresh scan, and every minute, so an open list goes stale without one.
@MainActor
@Observable
final class DevicePresenceModel {
    private(set) var snapshot: PresenceSnapshot
    @ObservationIgnored private let history: ScanHistory
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// A snapshot with no scans: nothing reads online. For previews and views shown without the app.
    static let noScans = PresenceSnapshot(lastScans: [:], now: .distantPast)

    init(history: ScanHistory = ScanHistory(), clock: @escaping @MainActor () -> Date = UITestBootstrap.presenceNow) {
        self.history = history
        self.clock = clock
        snapshot = history.presenceSnapshot(now: clock())
    }

    /// Reads the scan history again, as of now.
    func refresh() {
        snapshot = history.presenceSnapshot(now: clock())
    }

    /// Refreshes every minute until stopped.
    func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refresh()
            }
        }
    }
}
