import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

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
    /// scan runs to the end, so a stopped scan's partial list is never saved.
    func handleScanChange() {
        let isScanning = discoveryService.isScanning
        defer { wasScanning = isScanning }
        guard !isScanning, let scanDate = discoveryService.lastScanDate, scanDate != handledScanDate else { return }
        handledScanDate = scanDate
        let devices = discoveryService.discoveredDevices
        Self.reconcile(devices, scanDate: scanDate, network: currentNetworkProfileID(), with: reconciler, now: clock())
    }

    /// Reconciles `devices` into the rows of the network they were scanned on, else `network`.
    static func reconcile(_ devices: [DiscoveredDevice], scanDate: Date, network: UUID?, with reconciler: ScanReconciler, now: Date) {
        let scanned = devices.first?.networkProfileID ?? network
        reconciler.reconcile(devices, networkProfileID: scanned, scanDate: scanDate, now: now)
    }
}
