import Foundation
import Network

/// Tells the app when the device has joined a different local network, so it can drop the
/// old network's devices and scan the new one. iOS uses this; the Mac has its own
/// `LocalNetworkChangeWatcher` (#359) built on the same rule.
///
/// Path updates arrive in bursts while an interface comes up, so each one restarts a short
/// debounce; only a settled, satisfied path re-runs local-network detection. Apps that can
/// be suspended (iOS) also call `checkNow()` when they come back to the foreground, because
/// a path change that happened while suspended may never be delivered.
@MainActor
public final class LocalNetworkChangeMonitor {
    private let profileManager: NetworkProfileManager
    private let pathEvents: AsyncStream<Bool>
    private let debounce: Duration
    private let onChange: @MainActor (NetworkProfile) -> Void
    private var watchTask: Task<Void, Never>?
    /// The local network this monitor last reported or started on. Kept here rather than
    /// read before each detection, because other callers (view models, companion sync) also
    /// run `detectLocalNetwork()` and would otherwise hide a change from the monitor.
    private var lastNetworkKey: String?

    public init(
        profileManager: NetworkProfileManager,
        pathEvents: AsyncStream<Bool> = LocalNetworkChangeMonitor.systemPathEvents(),
        debounce: Duration = .seconds(2),
        onChange: @escaping @MainActor (NetworkProfile) -> Void
    ) {
        self.profileManager = profileManager
        self.pathEvents = pathEvents
        self.debounce = debounce
        self.onChange = onChange
        self.lastNetworkKey = Self.localNetworkKey(in: profileManager)
    }

    public func start() {
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

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Re-detects the local network now, as if a satisfied path had just settled.
    @discardableResult
    public func checkNow() -> Bool {
        handlePathSettled(satisfied: true)
    }

    /// Re-detects the local network. Returns true when it is a different network than the
    /// last one seen, after announcing it and calling `onChange` with the new local profile.
    @discardableResult
    public func handlePathSettled(satisfied: Bool) -> Bool {
        guard satisfied else { return false }
        profileManager.detectLocalNetwork()
        guard let local = profileManager.profiles.first(where: { $0.isLocal }) else { return false }
        let key = Self.networkKey(of: local)
        guard key != lastNetworkKey else { return false }
        lastNetworkKey = key
        NotificationCenter.default.post(name: .networkProfilesDidChange, object: nil)
        onChange(local)
        return true
    }

    private static func localNetworkKey(in manager: NetworkProfileManager) -> String? {
        guard let local = manager.profiles.first(where: { $0.isLocal }) else { return nil }
        return networkKey(of: local)
    }

    private static func networkKey(of profile: NetworkProfile) -> String {
        "\(profile.id)|\(profile.subnet)|\(profile.gatewayIP)"
    }

    /// Satisfied/unsatisfied updates from the system path monitor.
    nonisolated public static func systemPathEvents() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            // NWPathMonitor.start(queue:) is an Apple API that requires a DispatchQueue.
            monitor.start(queue: DispatchQueue(label: "com.netmonitor.localNetworkChangeMonitor"))
        }
    }
}
