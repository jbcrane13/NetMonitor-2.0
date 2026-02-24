import Foundation
import NetworkScanKit

/// Concrete implementation of ScanSchedulerServiceProtocol.
/// Persists the most recent device baseline to UserDefaults (as JSON) and computes
/// diffs by MAC address. Must be called from the MainActor.
@MainActor
public final class ScanSchedulerService: ScanSchedulerServiceProtocol {
    public static let shared = ScanSchedulerService()

    private static let baselineKey = "scanScheduler_baseline"

    /// The most recently computed diff. Nil until the first scan runs.
    public private(set) var cachedDiff: ScanDiff?

    private var scheduledDate: Date?

    public init() {}

    // MARK: - ScanSchedulerServiceProtocol

    public func scheduleNextScan(interval: TimeInterval) {
        scheduledDate = Date(timeIntervalSinceNow: interval)
    }

    public func getLastScanDiff() -> ScanDiff? {
        cachedDiff
    }

    public func computeDiff(current: [DiscoveredDevice]) -> ScanDiff {
        let baseline = loadBaseline()

        let baselineMACs = Set(baseline.compactMap(\.macAddress).filter { !$0.isEmpty })
        let currentMACs  = Set(current.compactMap(\.macAddress).filter { !$0.isEmpty })

        // Devices seen now but not in previous baseline.
        let newDevices = current.filter {
            guard let mac = $0.macAddress, !mac.isEmpty else { return false }
            return !baselineMACs.contains(mac)
        }

        // Devices that were in baseline but are now missing (went offline).
        let removedDevices = baseline.filter {
            guard let mac = $0.macAddress, !mac.isEmpty else { return false }
            return !currentMACs.contains(mac)
        }

        let diff = ScanDiff(
            newDevices: newDevices,
            removedDevices: removedDevices,
            changedDevices: [],
            scannedAt: Date()
        )

        cachedDiff = diff
        saveBaseline(current)
        return diff
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
            let data = UserDefaults.standard.data(forKey: Self.baselineKey),
            let devices = try? JSONDecoder().decode([DiscoveredDevice].self, from: data)
        else { return [] }
        return devices
    }

    private func saveBaseline(_ devices: [DiscoveredDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: Self.baselineKey)
    }
}
