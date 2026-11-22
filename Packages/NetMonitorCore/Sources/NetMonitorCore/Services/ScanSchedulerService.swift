import Foundation
import NetworkScanKit

/// Concrete implementation of ScanSchedulerServiceProtocol.
/// Computes diffs against every device seen before, with a grace period, using
/// `DeviceChangeTracker` (#393). Must be called from the MainActor.
@MainActor
public final class ScanSchedulerService: ScanSchedulerServiceProtocol {
    public static let shared = ScanSchedulerService()

    /// The previous-scan baseline used before #393; read once to seed the tracker on upgrade.
    private static let baselineKey = "scanScheduler_baseline"
    /// iOS has one device list, not one per network, so it uses a single scope.
    static let trackerScope = "default"

    /// The most recently computed diff. Nil until the first scan runs.
    public private(set) var cachedDiff: ScanDiff?

    private var scheduledDate: Date?
    private let defaults: UserDefaults
    private let tracker: DeviceChangeTracker

    public init(defaults: UserDefaults = .standard, policy: DeviceGracePolicy = DeviceGracePolicy()) {
        self.defaults = defaults
        tracker = DeviceChangeTracker(defaults: defaults, policy: policy)
    }

    // MARK: - ScanSchedulerServiceProtocol

    public func scheduleNextScan(interval: TimeInterval) {
        scheduledDate = Date(timeIntervalSinceNow: interval)
    }

    public func getLastScanDiff() -> ScanDiff? {
        cachedDiff
    }

    public func computeDiff(current: [DiscoveredDevice]) -> ScanDiff {
        computeDiff(current: current, now: Date())
    }

    /// New = answered for the first time (never on the first scan); removed = unanswered for
    /// the whole grace period; changed = answered with a new IP address or name (#393).
    func computeDiff(current: [DiscoveredDevice], now: Date) -> ScanDiff {
        let observations = current.map {
            DeviceObservation(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName, isCached: $0.isCached)
        }
        let events = tracker.record(scope: Self.trackerScope, observed: observations, now: now) {
            loadBaseline().map {
                KnownDevice(macAddress: $0.macAddress, ipAddress: $0.ipAddress, name: $0.matchName, firstSeen: now, lastSeen: now)
            }
        }

        var newDevices: [DiscoveredDevice] = []
        var removedDevices: [DiscoveredDevice] = []
        var changedDevices: [DiscoveredDevice] = []
        for event in events {
            switch event {
            case let .firstSeen(observation):
                newDevices += current.filter { Self.matches($0, observation) }.prefix(1)
            case let .changed(observation, _):
                changedDevices += current.filter { Self.matches($0, observation) }.prefix(1)
            case let .wentOffline(known):
                removedDevices.append(DiscoveredDevice(
                    ipAddress: known.ipAddress,
                    hostname: known.name,
                    vendor: nil,
                    macAddress: known.macAddress,
                    latency: nil,
                    discoveredAt: known.lastSeen,
                    source: .local
                ))
            case .cameOnline:
                break
            }
        }

        let diff = ScanDiff(
            newDevices: newDevices,
            removedDevices: removedDevices,
            changedDevices: changedDevices,
            scannedAt: now
        )
        cachedDiff = diff
        return diff
    }

    private static func matches(_ device: DiscoveredDevice, _ observation: DeviceObservation) -> Bool {
        device.ipAddress == observation.ipAddress && device.macAddress == observation.macAddress
    }

    // MARK: - Convenience

    /// Whether the next scheduled scan window has been reached.
    public var isScanDue: Bool {
        guard let scheduledDate else { return false }
        return Date() >= scheduledDate
    }

    // MARK: - Persistence

    private func loadBaseline() -> [DiscoveredDevice] {
        guard
            let data = defaults.data(forKey: Self.baselineKey),
            let devices = try? JSONDecoder().decode([DiscoveredDevice].self, from: data)
        else { return [] }
        return devices
    }
}
