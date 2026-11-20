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
    /// The local network last scanned for. Kept here rather than read before each detection:
    /// companion sync and the views also run `detectLocalNetwork()`, and reading "before"
    /// after one of them had already switched the profile hid the change from the watcher.
    private var lastNetworkKey: String?

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
        self.lastNetworkKey = Self.localNetworkKey(in: profileManager)
    }

    func start() {
        guard watchTask == nil else { return }
        let events = pathEvents
        let debounce = debounce
        watchTask = Task { [weak self] in
            var settle: Task<Void, Never>?
            for await satisfied in events {
                settle?.cancel()
                settle = Task { [weak self] in
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { return }
                    self?.handlePathSettled(satisfied: satisfied)
                }
            }
            settle?.cancel()
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Re-detects the local network after the path settles. Returns true when it changed
    /// and a scan of the new network was started.
    @discardableResult
    func handlePathSettled(satisfied: Bool) -> Bool {
        guard satisfied else { return false }
        profileManager.detectLocalNetwork()
        let after = Self.localNetworkKey(in: profileManager)
        guard after != nil, after != lastNetworkKey else {
            Logger.discovery.notice("Network path settled: same local network")
            return false
        }
        lastNetworkKey = after
        Logger.discovery.notice("Local network changed: rescanning")
        NotificationCenter.default.post(name: .networkProfilesDidChange, object: nil)
        // A scan of the old network would only probe addresses that aren't there any more.
        if discovery.isScanning {
            discovery.stopScan()
        }
        discovery.startLaunchScan()
        return true
    }

    private static func localNetworkKey(in profileManager: NetworkProfileManager) -> String? {
        profileManager.profiles.first(where: { $0.isLocal }).map { "\($0.id)|\($0.subnet)|\($0.gatewayIP)" }
    }

    /// Satisfied/unsatisfied updates from the system path monitor.
    nonisolated static func systemPathEvents() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            // NWPathMonitor.start(queue:) is an Apple API that requires a DispatchQueue.
            monitor.start(queue: DispatchQueue(label: "com.netmonitor.localNetworkChange"))
        }
    }
}
