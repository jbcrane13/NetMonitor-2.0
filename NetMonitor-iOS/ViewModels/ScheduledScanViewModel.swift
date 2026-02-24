import Foundation
import NetMonitorCore
import NetworkScanKit

// MARK: - ScanInterval

/// Supported scan intervals for automatic background scanning.
enum ScanInterval: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 900
    case oneHour        = 3600
    case sixHours       = 21600
    case daily          = 86400

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .fifteenMinutes: "15 Minutes"
        case .oneHour:        "1 Hour"
        case .sixHours:       "6 Hours"
        case .daily:          "Daily"
        }
    }
}

// MARK: - ScheduledScanViewModel

@MainActor
@Observable
final class ScheduledScanViewModel {

    // MARK: - UserDefaults keys

    private enum Keys {
        static let enabled             = "scheduledScan_enabled"
        static let interval            = "scheduledScan_interval"
        static let notifyNew           = "scheduledScan_notifyNew"
        static let notifyMissing       = "scheduledScan_notifyMissing"
        static let triggerOnWiFiChange = "scheduledScan_wifiTrigger"
    }

    // MARK: - Persisted settings

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    var selectedInterval: ScanInterval {
        didSet { UserDefaults.standard.set(selectedInterval.rawValue, forKey: Keys.interval) }
    }

    var notifyOnNewDevices: Bool {
        didSet { UserDefaults.standard.set(notifyOnNewDevices, forKey: Keys.notifyNew) }
    }

    var notifyOnMissingDevices: Bool {
        didSet { UserDefaults.standard.set(notifyOnMissingDevices, forKey: Keys.notifyMissing) }
    }

    var triggerOnWiFiChange: Bool {
        didSet { UserDefaults.standard.set(triggerOnWiFiChange, forKey: Keys.triggerOnWiFiChange) }
    }

    // MARK: - State

    private(set) var isScanning = false
    private(set) var lastDiff: ScanDiff?
    private(set) var scanHistory: [ScanDiff] = []
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let scheduler: any ScanSchedulerServiceProtocol
    private let discovery: any DeviceDiscoveryServiceProtocol

    // MARK: - Init

    init(
        scheduler: any ScanSchedulerServiceProtocol = ScanSchedulerService.shared,
        discovery: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared
    ) {
        self.scheduler = scheduler
        self.discovery = discovery

        let intervalRaw = UserDefaults.standard.integer(forKey: Keys.interval)
        selectedInterval = ScanInterval(rawValue: intervalRaw) ?? .oneHour
        isEnabled        = (UserDefaults.standard.object(forKey: Keys.enabled) as? Bool) ?? false
        notifyOnNewDevices    = (UserDefaults.standard.object(forKey: Keys.notifyNew) as? Bool) ?? true
        notifyOnMissingDevices = (UserDefaults.standard.object(forKey: Keys.notifyMissing) as? Bool) ?? true
        triggerOnWiFiChange   = (UserDefaults.standard.object(forKey: Keys.triggerOnWiFiChange) as? Bool) ?? false

        lastDiff = scheduler.getLastScanDiff()
    }

    // MARK: - Actions

    func runScanNow() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        await discovery.scanNetwork(subnet: nil)
        let devices = discovery.discoveredDevices
        let diff = scheduler.computeDiff(current: devices)
        lastDiff = diff

        if diff.hasChanges {
            scanHistory.insert(diff, at: 0)
        }

        if isEnabled {
            scheduler.scheduleNextScan(interval: TimeInterval(selectedInterval.rawValue))
        }
    }

    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            scheduler.scheduleNextScan(interval: TimeInterval(selectedInterval.rawValue))
        }
    }

    func clearHistory() {
        scanHistory.removeAll()
    }

    // MARK: - Computed

    var statusText: String {
        guard isEnabled else { return "Scheduled scanning disabled" }
        return "Scanning every \(selectedInterval.displayName.lowercased())"
    }

    var lastScanSummary: String {
        guard let diff = lastDiff else { return "No scan history" }
        let ago = diff.scannedAt.formatted(.relative(presentation: .named))
        return "\(diff.summaryText) • \(ago)"
    }
}
