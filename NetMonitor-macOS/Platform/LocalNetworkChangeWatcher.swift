import Foundation
import Network
import NetMonitorCore
import os

/// Rescans when the Mac moves to a different network while the app is open (#359).
///
/// Path updates arrive in bursts while an interface comes up, so each one restarts a
/// short debounce; only a settled, satisfied path re-runs local-network detection.
@MainActor
final class LocalNetworkChangeWatcher {
    private let profileManager: NetworkProfileManager
    private let discovery: DeviceDiscoveryCoordinator
    private let pathEvents: AsyncStream<Bool>
    private let debounce: Duration
    private var watchTask: Task<Void, Never>?

    init(
        profileManager: NetworkProfileManager,
        discovery: DeviceDiscoveryCoordinator,
        pathEvents: AsyncStream<Bool> = LocalNetworkChangeWatcher.systemPathEvents(),
        debounce: Duration = .seconds(3)
    ) {
        self.profileManager = profileManager
        self.discovery = discovery
        self.pathEvents = pathEvents
        self.debounce = debounce
    }

    func start() {}

    func stop() {}

    /// Re-detects the local network after the path settles. Returns true when it changed
    /// and a scan of the new network was started.
    @discardableResult
    func handlePathSettled(satisfied: Bool) -> Bool {
        false
    }

    /// Satisfied/unsatisfied updates from the system path monitor.
    nonisolated static func systemPathEvents() -> AsyncStream<Bool> {
        AsyncStream { _ in }
    }
}
