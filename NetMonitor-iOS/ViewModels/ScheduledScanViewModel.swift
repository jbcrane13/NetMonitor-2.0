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
    /// The network a scan started here is about (#582).
    private let currentNetwork: @MainActor () -> NetworkProfile?
    private let discovery: any DeviceDiscoveryServiceProtocol
    private let dispatcher: any DeviceEventDispatching
    private var subscription: UUID?

    // MARK: - Init

    init(
        scheduler: any ScanSchedulerServiceProtocol = ScanSchedulerService.shared,
        discovery: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        currentNetwork: @escaping @MainActor () -> NetworkProfile? = { CurrentNetwork.detected() },
        dispatcher: any DeviceEventDispatching = DeviceEventDispatcher.shared
    ) {
        self.scheduler = scheduler
        self.discovery = discovery
        self.currentNetwork = currentNetwork
        self.dispatcher = dispatcher

        let intervalRaw = UserDefaults.standard.integer(forKey: Keys.interval)
        selectedInterval = ScanInterval(rawValue: intervalRaw) ?? .oneHour
        isEnabled        = (UserDefaults.standard.object(forKey: Keys.enabled) as? Bool) ?? false
        notifyOnNewDevices    = (UserDefaults.standard.object(forKey: Keys.notifyNew) as? Bool) ?? true
        notifyOnMissingDevices = (UserDefaults.standard.object(forKey: Keys.notifyMissing) as? Bool) ?? true
        triggerOnWiFiChange   = (UserDefaults.standard.object(forKey: Keys.triggerOnWiFiChange) as? Bool) ?? false

        lastDiff = scheduler.getLastScanDiff()
        // Each applied scan's device events, foreground or background (#603), as the scheduler's
        // diff is built: the reconcile, not this view model, decides what changed.
        subscription = dispatcher.subscribe { [weak self] batch in
            self?.record(ScanDiff(batch))
        }
    }

    isolated deinit {
        if let subscription {
            dispatcher.unsubscribe(subscription)
        }
    }

    // MARK: - Actions

    func runScanNow() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        // The current network, so the devices are saved and listed under its ID (#582).
        await discovery.scanNetwork(profile: currentNetwork())
        // The scan's diff arrives when its reconcile applies it, before or after this; a scan
        // with no device events delivers nothing, so until then it shows as no changes.
        if let scanDate = discovery.lastScanDate, lastDiff?.scannedAt != scanDate {
            lastDiff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [], scannedAt: scanDate)
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

    /// One applied scan's diff; a scan of several networks delivers one per network, kept as one.
    private func record(_ diff: ScanDiff) {
        var diff = diff
        if let last = lastDiff, last.scannedAt == diff.scannedAt {
            diff = ScanDiff(
                newDevices: last.newDevices + diff.newDevices, removedDevices: last.removedDevices + diff.removedDevices,
                changedDevices: last.changedDevices + diff.changedDevices, scannedAt: diff.scannedAt
            )
        }
        lastDiff = diff
        guard diff.hasChanges else { return }
        if let index = scanHistory.firstIndex(where: { $0.scannedAt == diff.scannedAt }) {
            scanHistory[index] = diff
        } else {
            scanHistory.insert(diff, at: 0)
        }
    }

    // MARK: - Computed

    var statusText: String {
        guard isEnabled else { return "Scheduled scanning disabled" }
        return "Scanning every \(selectedInterval.displayName.lowercased())"
    }

    // periphery:ignore
    var lastScanSummary: String {
        guard let diff = lastDiff else { return "No scan history" }
        let ago = diff.scannedAt.formatted(.relative(presentation: .named))
        return "\(diff.summaryText) • \(ago)"
    }
}
