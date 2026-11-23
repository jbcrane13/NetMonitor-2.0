import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
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

// MARK: - SavedDeviceLookup

/// Finds a scanned device's saved row, read only (#491 D9): the device match (`DeviceMatcher`,
/// MAC then IP) against the rows on that network, then against rows saved with no network,
/// the way device detail does. Never inserts or changes a row.
@MainActor
struct SavedDeviceLookup {
    let context: ModelContext

    func row(for device: DiscoveredDevice, networkProfileID: UUID?) -> LocalDevice? {
        let rows = (try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []
        let observation = DeviceMatchCandidate(ipAddress: device.ipAddress, macAddress: device.macAddress, name: device.matchName)
        var pools = [rows.filter { $0.networkProfileID == networkProfileID }]
        if networkProfileID != nil {
            pools.append(rows.filter { $0.networkProfileID == nil })
        }
        for pool in pools {
            var matcher = DeviceMatcher(
                known: pool.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) },
                observed: [observation]
            )
            if let match = matcher.match(observation) {
                return pool[match.index]
            }
        }
        return nil
    }
}

// MARK: - EventListenerService

/// Observes the network monitor and a device discovery service to log connectivity and
/// device-change events for the Timeline. Every event carries its network's ID; a device that
/// matches a saved row is named by its `displayName` and carries the row's ID (#491 D9).
@MainActor
final class EventListenerService {

    // MARK: - Dependencies

    private let eventService: any NetworkEventServiceProtocol
    private let networkMonitor: NetworkMonitorService
    private let discoveryService: any DeviceDiscoveryServiceProtocol
    /// The network events are about when a device doesn't say which it was scanned on.
    private let currentNetworkProfileID: @MainActor () -> UUID?
    private let savedDevices: SavedDeviceLookup?

    // MARK: - Tracking state

    private var lastIsConnected: Bool?
    private var lastConnectionType: ConnectionType?
    private var wasScanning: Bool = false
    /// The last completed scan's devices by IP, so a device that left can still be matched by MAC.
    private var knownDevices: [String: DiscoveredDevice] = [:]

    private var monitorTask: Task<Void, Never>?

    // MARK: - Init

    init(
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        networkMonitor: NetworkMonitorService = NetworkMonitorService.shared,
        discoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        currentNetworkProfileID: @escaping @MainActor () -> UUID? = { nil },
        savedDevices: SavedDeviceLookup? = nil
    ) {
        self.eventService = eventService
        self.networkMonitor = networkMonitor
        self.discoveryService = discoveryService
        self.currentNetworkProfileID = currentNetworkProfileID
        self.savedDevices = savedDevices
    }

    // MARK: - Lifecycle

    func start() {
        monitorTask?.cancel()
        // A scan already running now is logged when it finishes.
        wasScanning = discoveryService.isScanning
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let waiter = ObservationChangeWaiter()
                await waiter.wait { onChange in
                    withObservationTracking {
                        _ = self.networkMonitor.isConnected
                        _ = self.networkMonitor.connectionType
                        _ = self.discoveryService.isScanning
                        _ = self.discoveryService.discoveredDevices
                    } onChange: {
                        onChange()
                    }
                }
                guard !Task.isCancelled else { return }
                self.handleConnectivityChange()
                self.handleScanChange()
            }
        }
    }

    // periphery:ignore
    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
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

        // Detect scan completion: was scanning, now not scanning
        if wasScanning && !isScanning {
            let currentDevices = discoveryService.discoveredDevices
            let current = Dictionary(currentDevices.map { ($0.ipAddress, $0) }, uniquingKeysWith: { first, _ in first })
            let fallbackNetwork = currentNetworkProfileID()

            for ip in Set(current.keys).subtracting(knownDevices.keys).sorted() {
                if let device = current[ip] {
                    logDevice(device, joined: true, fallbackNetwork: fallbackNetwork)
                }
            }
            for ip in Set(knownDevices.keys).subtracting(current.keys).sorted() {
                if let device = knownDevices[ip] {
                    logDevice(device, joined: false, fallbackNetwork: fallbackNetwork)
                }
            }

            let count = currentDevices.count
            eventService.log(
                type: .scanComplete,
                title: "Scan Complete — \(count) \(count == 1 ? "device" : "devices") found",
                details: nil,
                severity: .info,
                networkProfileID: currentDevices.first?.networkProfileID ?? fallbackNetwork
            )

            knownDevices = current
        }

        wasScanning = isScanning
    }

    /// A joined or left device, named by its saved row when it matches one; otherwise a joined
    /// device by its hostname or maker and a left one by its IP, as before #491.
    private func logDevice(_ device: DiscoveredDevice, joined: Bool, fallbackNetwork: UUID?) {
        let network = device.networkProfileID ?? fallbackNetwork
        let row = savedDevices?.row(for: device, networkProfileID: network)
        let ip = device.ipAddress
        let label = row?.displayName ?? (joined ? device.hostname ?? device.maker ?? ip : ip)
        eventService.log(
            type: joined ? .deviceJoined : .deviceLeft,
            title: "\(joined ? "Device Joined" : "Device Left"): \(label)",
            details: label == ip ? nil : ip,
            severity: joined ? .success : .warning,
            deviceID: row?.id,
            networkProfileID: network
        )
    }
}
