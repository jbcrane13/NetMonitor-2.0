import AppKit
import NetMonitorCore

@MainActor
extension NetMonitorApp {
    /// Starts the join clock at launch (#579). Waking from sleep may land on another LAN with the
    /// same path, so it counts as a join.
    static func startJoinClock() {
        _ = NetworkJoinClock.shared
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NetworkJoinClock.shared.noteResume() }
        }
    }
}
