import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import os

/// Keeps the saved device rows current on iPhone and iPad (#582): after every scan the app's
/// discovery service finishes, the results go into the scanned network's `LocalDevice` rows
/// (`ScanReconciler`), so device detail, the PDF report, data export and Ask read the latest
/// presence. Background scans reconcile through `BackgroundTaskService`; a scan both see is
/// reconciled once.
@MainActor
final class DeviceRecordUpdater {
    private let discoveryService: any DeviceDiscoveryServiceProtocol
    private let reconciler: ScanReconciler
    /// The network a scan is about when its devices don't say.
    private let currentNetworkProfileID: @MainActor () -> UUID?
    private let clock: @MainActor () -> Date
    private var wasScanning = false
    private var handledScanDate: Date?
    private var task: Task<Void, Never>?

    init(
        discoveryService: any DeviceDiscoveryServiceProtocol,
        reconciler: ScanReconciler,
        currentNetworkProfileID: @escaping @MainActor () -> UUID?,
        clock: @escaping @MainActor () -> Date = Date.init
    ) {
        self.discoveryService = discoveryService
        self.reconciler = reconciler
        self.currentNetworkProfileID = currentNetworkProfileID
        self.clock = clock
    }

    func start() {
        task?.cancel()
        wasScanning = discoveryService.isScanning
        // A scan that finished before the app started watching was never reconciled.
        handledScanDate = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.handleScanChange()
                let waiter = ObservationChangeWaiter()
                await waiter.wait { onChange in
                    withObservationTracking {
                        _ = self.discoveryService.isScanning
                        _ = self.discoveryService.lastScanDate
                    } onChange: {
                        onChange()
                    }
                }
            }
        }
    }

    /// Reconciles a scan that finished since the last check. `lastScanDate` moves only when a
    /// scan runs to the end, so a stopped scan's partial list is never saved. A scan whose rows
    /// couldn't be saved is tried again at the next change.
    func handleScanChange() {
        let isScanning = discoveryService.isScanning
        defer { wasScanning = isScanning }
        guard !isScanning, let scanDate = discoveryService.lastScanDate, scanDate != handledScanDate else { return }
        let devices = discoveryService.discoveredDevices
        if Self.reconcile(devices, scanDate: scanDate, network: currentNetworkProfileID(), with: reconciler, now: clock()) {
            handledScanDate = scanDate
        }
    }

    /// Reconciles `devices` into the rows of the network each was scanned on; a device that carries
    /// no network is the current network's (`network`). False when saving failed (logged).
    @discardableResult
    static func reconcile(_ devices: [DiscoveredDevice], scanDate: Date, network: UUID?, with reconciler: ScanReconciler, now: Date) -> Bool {
        let byNetwork = Dictionary(grouping: devices) { $0.networkProfileID ?? network }
        var succeeded = true
        for (scanned, devices) in byNetwork {
            do {
                try reconciler.reconcile(devices, networkProfileID: scanned, scanDate: scanDate, now: now)
            } catch {
                Logger.data.error("Saving scanned devices failed: \(error.localizedDescription, privacy: .public)")
                succeeded = false
            }
        }
        return succeeded
    }
}
