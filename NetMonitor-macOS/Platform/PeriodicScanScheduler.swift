import Foundation
import os

/// Rescans devices at the "Scan frequency" chosen in Monitoring settings while the app runs (#392).
///
/// A frequency of 0 or less means off: no timer runs. Changing the setting restarts the
/// timer at once instead of waiting out the old interval. Each tick asks for a `.periodic`
/// rescan; the coordinator's policy decides whether it runs (#484).
@MainActor
final class PeriodicScanScheduler {
    static let frequencyKey = "netmonitor.monitoring.scanFrequency"
    static let defaultFrequency = 300

    private let defaults: UserDefaults
    private let rescan: @MainActor () -> Bool
    private let sleep: @Sendable (Duration) async -> Void
    private var loopTask: Task<Void, Never>?
    private var defaultsObserver: (any NSObjectProtocol)?

    /// The interval the running timer uses, in seconds, or nil when no timer runs.
    private(set) var activeInterval: Int?

    init(
        defaults: UserDefaults = .standard,
        rescan: @escaping @MainActor () -> Bool,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.defaults = defaults
        self.rescan = rescan
        self.sleep = sleep
    }

    /// The saved scan frequency in seconds; 0 or less means off.
    var configuredInterval: Int {
        defaults.object(forKey: Self.frequencyKey) as? Int ?? Self.defaultFrequency
    }

    func start() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        loopTask?.cancel()
        loopTask = nil
        activeInterval = nil
    }

    /// Restarts the timer when the saved frequency differs from the running one.
    func reload() {
        let interval = configuredInterval
        let wanted: Int? = interval > 0 ? interval : nil
        guard wanted != activeInterval else { return }
        loopTask?.cancel()
        loopTask = nil
        activeInterval = wanted
        guard let wanted else {
            Logger.discovery.notice("Periodic scan off")
            return
        }
        Logger.discovery.notice("Periodic scan every \(wanted, privacy: .public)s")
        let sleep = sleep
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await sleep(.seconds(wanted))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    /// Asks for a rescan. Returns true when a scan was started.
    @discardableResult
    func tick() -> Bool {
        rescan()
    }
}

extension PeriodicScanScheduler {
    /// A scheduler that rescans through `discovery`. Automatic rescans aren't
    /// user-started, so they don't count toward the review prompt (#337).
    static func rescanning(
        _ discovery: DeviceDiscoveryCoordinator,
        defaults: UserDefaults = .standard
    ) -> PeriodicScanScheduler {
        PeriodicScanScheduler(
            defaults: defaults,
            rescan: { [weak discovery] in discovery?.rescan(.periodic) ?? false }
        )
    }
}
