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
    /// Called after a scan is saved and recorded, with the networks it saved, so presence is read
    /// again (#583) and the saved-device count and widget are published from the saved devices (#594).
    private let onSaved: @MainActor (Set<UUID>) -> Void
    private var wasScanning = false
    /// The last completed scan taken into `pending`.
    private var capturedScanDate: Date?
    /// Completed scans not saved yet, oldest first. Each is copied when it completes, so a retry
    /// after a failed save uses that scan's devices, never a later scan's partial list (Codex
    /// review on #589).
    private var pending: [CompletedScan] = []
    private var task: Task<Void, Never>?

    /// A completed scan as it was when it finished.
    private struct CompletedScan {
        let date: Date
        let devices: [DiscoveredDevice]
        let network: UUID?
        let reconciledAt: Date
        var attempts = 0
    }

    /// Saves tried per scan before it is dropped, so one scan that can't be saved never holds up
    /// the ones after it.
    static let maxAttempts = 3
    /// Completed scans kept waiting at most; the oldest is dropped past this.
    static let maxPending = 5

    init(
        discoveryService: any DeviceDiscoveryServiceProtocol,
        reconciler: ScanReconciler,
        currentNetworkProfileID: @escaping @MainActor () -> UUID?,
        clock: @escaping @MainActor () -> Date = Date.init,
        onSaved: @escaping @MainActor (Set<UUID>) -> Void = { _ in }
    ) {
        self.discoveryService = discoveryService
        self.reconciler = reconciler
        self.currentNetworkProfileID = currentNetworkProfileID
        self.clock = clock
        self.onSaved = onSaved
    }

    func start() {
        task?.cancel()
        wasScanning = discoveryService.isScanning
        // A scan that finished before the app started watching was never reconciled.
        capturedScanDate = nil
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

    /// Takes a scan that finished since the last check, then saves every completed scan not saved
    /// yet, oldest first. `lastScanDate` moves only when a scan runs to the end, and the devices
    /// taken are `completedScanDevices`, that scan's own, never a running or stopped scan's list.
    /// A scan whose rows couldn't be saved stays pending and is tried again at the next change.
    func handleScanChange() {
        let isScanning = discoveryService.isScanning
        defer { wasScanning = isScanning }
        if !isScanning, let scanDate = discoveryService.lastScanDate, scanDate != capturedScanDate {
            capturedScanDate = scanDate
            pending.append(CompletedScan(
                date: scanDate, devices: discoveryService.completedScanDevices, network: currentNetworkProfileID(), reconciledAt: clock()
            ))
            if pending.count > Self.maxPending {
                Logger.data.error("Too many scans waiting to be saved; dropping the oldest")
                pending.removeFirst()
            }
        }
        while !pending.isEmpty {
            let scan = pending[0]
            if Self.reconcile(scan.devices, scanDate: scan.date, network: scan.network, with: reconciler, now: scan.reconciledAt) {
                pending.removeFirst()
                onSaved(Set(scan.devices.compactMap { $0.networkProfileID ?? scan.network }))
                continue
            }
            pending[0].attempts += 1
            guard pending[0].attempts >= Self.maxAttempts else { return }
            Logger.data.error("Dropping a scan whose devices couldn't be saved after \(Self.maxAttempts) tries")
            pending.removeFirst()
        }
    }

    /// Reconciles `devices` into the rows of the network each was scanned on; a device that carries
    /// no network is `network`'s: the live network, read when the scan completed (the foreground
    /// updater) or when it started (the background task). With neither, nothing is reconciled:
    /// devices are never filed under a network the phone may have left.
    /// False when saving failed (logged).
    @discardableResult
    static func reconcile(_ devices: [DiscoveredDevice], scanDate: Date, network: UUID?, with reconciler: ScanReconciler, now: Date) -> Bool {
        var byNetwork: [UUID: [DiscoveredDevice]] = [:]
        for device in devices {
            guard let scanned = device.networkProfileID ?? network else { continue }
            byNetwork[scanned, default: []].append(device)
        }
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
