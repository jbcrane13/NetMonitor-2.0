import Foundation
import NetMonitorCore
import NetworkScanKit
import os

// MARK: - ObservationChangeWaiter

/// Bridges Observation's callback API into async code without leaving a
/// continuation suspended when its task is cancelled.
final class ObservationChangeWaiter: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var isResolved = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    @MainActor
    func wait(_ registerObservation: (@escaping @Sendable () -> Void) -> Void) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResumeImmediately = state.withLock { state in
                    guard !state.isResolved else { return true }
                    state.continuation = continuation
                    return false
                }

                guard !shouldResumeImmediately else {
                    continuation.resume()
                    return
                }

                registerObservation { [weak self] in
                    self?.resume()
                }
            }
        } onCancel: {
            resume()
        }
    }

    private func resume() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.isResolved else { return nil }
            state.isResolved = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}

// MARK: - EventListenerService

/// Logs connectivity and scan events for the Timeline from the network monitor and a device
/// discovery service, and device events from the `DeviceEventDispatcher` (#603): only the
/// reconcile that applied a scan delivers them, so the Timeline agrees with the saved rows. Each
/// device event is named by its device (a group's primary's name, #594), carries the primary row's
/// ID and its network's ID, and a group of interfaces logs at most one per scan.
@MainActor
final class EventListenerService {

    // MARK: - Dependencies

    private let eventService: any NetworkEventServiceProtocol
    private let networkMonitor: NetworkMonitorService
    private let discoveryService: any DeviceDiscoveryServiceProtocol
    /// The network events are about when a device doesn't say which it was scanned on.
    private let currentNetworkProfileID: @MainActor () -> UUID?
    private let dispatcher: any DeviceEventDispatching

    // MARK: - Tracking state

    private var lastIsConnected: Bool?
    private var lastConnectionType: ConnectionType?
    private var wasScanning: Bool = false
    /// The last scan finish handled, so a scan that finished unobserved is still logged.
    private var handledScanDate: Date?

    private var monitorTask: Task<Void, Never>?
    private var subscription: UUID?

    // MARK: - Init

    init(
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        networkMonitor: NetworkMonitorService = NetworkMonitorService.shared,
        discoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        currentNetworkProfileID: @escaping @MainActor () -> UUID? = { nil },
        dispatcher: any DeviceEventDispatching = DeviceEventDispatcher.shared
    ) {
        self.eventService = eventService
        self.networkMonitor = networkMonitor
        self.discoveryService = discoveryService
        self.currentNetworkProfileID = currentNetworkProfileID
        self.dispatcher = dispatcher
        // From creation, not from `start()`: the app makes the listener at launch, so a scan a
        // background launch reconciles before any view appears still reaches the Timeline.
        subscribeToDeviceEvents()
    }

    isolated deinit {
        monitorTask?.cancel()
        if let subscription {
            dispatcher.unsubscribe(subscription)
        }
    }

    /// Whether `start()` is watching connectivity and scans.
    var isRunning: Bool {
        monitorTask != nil
    }

    // MARK: - Lifecycle

    /// Watches connectivity and scan completion; device events are logged from creation (and again
    /// after `stop()`).
    func start() {
        monitorTask?.cancel()
        subscribeToDeviceEvents()
        // The baseline: a scan running now, or finishing before the first check, is still logged.
        wasScanning = discoveryService.isScanning
        handledScanDate = discoveryService.lastScanDate
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Check, then register for the next change, in one main-actor turn, so no change
                // falls between them.
                self.handleConnectivityChange()
                self.handleScanChange()
                let waiter = ObservationChangeWaiter()
                await waiter.wait { onChange in
                    withObservationTracking {
                        _ = self.networkMonitor.isConnected
                        _ = self.networkMonitor.connectionType
                        _ = self.discoveryService.isScanning
                        _ = self.discoveryService.discoveredDevices
                        _ = self.discoveryService.lastScanDate
                    } onChange: {
                        onChange()
                    }
                }
            }
        }
    }

    // periphery:ignore
    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        if let subscription {
            dispatcher.unsubscribe(subscription)
        }
        subscription = nil
    }

    private func subscribeToDeviceEvents() {
        guard subscription == nil else { return }
        subscription = dispatcher.subscribe { [weak self] batch in
            self?.logDeviceEvents(batch)
        }
    }

    // MARK: - Private handlers

    private func handleConnectivityChange() {
        let isConnected = networkMonitor.isConnected
        let connectionType = networkMonitor.connectionType

        // Skip first observation — just capture baseline
        guard lastIsConnected != nil else {
            lastIsConnected = isConnected
            lastConnectionType = connectionType
            return
        }

        guard isConnected != lastIsConnected || connectionType != lastConnectionType else { return }

        let title: String
        let severity: NetworkEventSeverity
        if isConnected {
            title = "Connected via \(connectionType.displayName)"
            severity = .success
        } else {
            title = "Network Disconnected"
            severity = .warning
        }

        eventService.log(
            type: .connectivityChange, title: title, details: nil, severity: severity, networkProfileID: currentNetworkProfileID()
        )
        lastIsConnected = isConnected
        lastConnectionType = connectionType
    }

    private func handleScanChange() {
        let isScanning = discoveryService.isScanning

        // A scan finished: seen going from scanning to not, or a new finish time while unobserved.
        let lastScanDate = discoveryService.lastScanDate
        if !isScanning, wasScanning || lastScanDate != handledScanDate {
            handledScanDate = lastScanDate
            let currentDevices = discoveryService.discoveredDevices
            // A scan's devices carry the network it scanned; the current network is the fallback.
            let network = currentDevices.first?.networkProfileID ?? currentNetworkProfileID()

            let count = currentDevices.count
            eventService.log(
                type: .scanComplete,
                title: "Scan Complete — \(count) \(count == 1 ? "device" : "devices") found",
                details: nil,
                severity: .info,
                networkProfileID: network
            )
        }

        wasScanning = isScanning
    }

    /// An applied scan's device events: a device that joined, came back online, or went offline
    /// under grace. An address change or a rename is no Timeline entry, as on the Mac.
    private func logDeviceEvents(_ batch: DeviceEventBatch) {
        for event in batch.events {
            let type: NetworkEventType
            switch event.kind {
            case .joined, .cameOnline: type = .deviceJoined
            case .wentOffline: type = .deviceLeft
            case .addressChanged, .renamed: continue
            }
            // "Device Back Online" is the Mac's wording, which the change digest and Ask read as a return.
            guard let prefix = DeviceTimelineTitle.prefix(for: event.kind) else { continue }
            eventService.log(
                type: type,
                title: DeviceTimelineTitle.title(prefix, name: event.name),
                details: event.name == event.ipAddress ? nil : event.ipAddress,
                severity: type == .deviceJoined ? .success : .warning,
                deviceID: event.rowID,
                networkProfileID: event.networkProfileID ?? batch.networkProfileID
            )
        }
    }
}
