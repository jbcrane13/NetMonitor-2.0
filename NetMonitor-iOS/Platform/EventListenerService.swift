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

/// Finds scanned devices' saved rows, read only (#491 D9). Never inserts or changes a row.
@MainActor
struct SavedDeviceLookup {
    let context: ModelContext

    /// The saved rows a scan of `networkProfileID` can match, fetched once for the whole scan.
    func snapshot(networkProfileID: UUID?) -> SavedDevices {
        let network = fetch(#Predicate<LocalDevice> { $0.networkProfileID == networkProfileID })
        // Rows saved before devices carried a network; only a scan of a known network falls back to them.
        let unassigned = networkProfileID == nil ? [] : fetch(#Predicate<LocalDevice> { $0.networkProfileID == nil })
        return SavedDevices(network: network, unassigned: unassigned)
    }

    private func fetch(_ predicate: Predicate<LocalDevice>) -> [LocalDevice] {
        do {
            return try context.fetch(FetchDescriptor(predicate: predicate))
        } catch {
            Logger.data.error("Saved-device lookup fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

/// One network's saved rows, for naming a scan's devices.
@MainActor
struct SavedDevices {
    let network: [LocalDevice]
    let unassigned: [LocalDevice]

    /// Each device's row by IP, from one device match (`DeviceMatcher`, MAC then IP) over the
    /// whole scan, the way device detail matches: devices with a MAC claim their rows first, so a
    /// newcomer without one can't take the row of a device that moved to another IP in the same
    /// scan. A row saved with no network matches only by an identical MAC: an IP means nothing
    /// across networks.
    func rows(for scan: [DiscoveredDevice]) -> [String: LocalDevice] {
        let candidates = scan.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) }
        var matcher = DeviceMatcher(
            known: network.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) },
            observed: candidates
        )
        let order = scan.indices.sorted { lhs, rhs in
            let lhsHasMAC = !(scan[lhs].macAddress ?? "").isEmpty
            let rhsHasMAC = !(scan[rhs].macAddress ?? "").isEmpty
            return lhsHasMAC != rhsHasMAC ? lhsHasMAC : lhs < rhs
        }
        var rows: [String: LocalDevice] = [:]
        for index in order {
            let device = scan[index]
            if let match = matcher.match(candidates[index]) {
                rows[device.ipAddress] = network[match.index]
            } else if let mac = device.macAddress, !mac.isEmpty,
                      let row = unassigned.first(where: { $0.macAddress.caseInsensitiveCompare(mac) == .orderedSame }) {
                rows[device.ipAddress] = row
            }
        }
        return rows
    }

    /// One device's row, matched on its own (a device that left has no scan to compete in).
    func row(for device: DiscoveredDevice) -> LocalDevice? {
        rows(for: [device])[device.ipAddress]
    }

    /// The name of the device `row` is an interface of (#594): its group's primary's, else its own.
    /// Both fetches hold whole networks, so every group is complete.
    func name(of row: LocalDevice) -> String {
        DeviceGroupResolver(rows: network + unassigned).device(for: row.id)?.displayName ?? row.displayName
    }
}

// MARK: - EventListenerService

/// Observes the network monitor and a device discovery service to log connectivity and
/// device-change events for the Timeline. Every event carries its network's ID; a device that
/// matches a saved row is named by its device's `displayName` (a group's primary's, #594) and
/// carries the row's ID (#491 D9). Each row still logs its own event; PR2 of #594 gives a group one.
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
    /// The last scan finish handled, so a scan that finished unobserved is still logged.
    private var handledScanDate: Date?
    /// Each network's last completed scan, by IP, so a scan is compared only with the same
    /// network's previous one and a device that left can still be matched by MAC.
    private var knownDevices: [UUID?: [String: DiscoveredDevice]] = [:]

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
            // An empty scan (offline, or a network that didn't answer) says nothing about who left.
            if !currentDevices.isEmpty {
                logDeviceChanges(currentDevices, network: network)
            }

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

    /// Joined and left devices against `network`'s previous scan, named from the saved rows.
    private func logDeviceChanges(_ devices: [DiscoveredDevice], network: UUID?) {
        let current = Dictionary(devices.map { ($0.ipAddress, $0) }, uniquingKeysWith: { first, _ in first })
        let previous = knownDevices[network] ?? [:]
        let saved = savedDevices?.snapshot(networkProfileID: network)
        let rows = saved?.rows(for: devices) ?? [:]
        for ip in Set(current.keys).subtracting(previous.keys).sorted() {
            if let device = current[ip] {
                logDevice(device, joined: true, network: network, row: rows[ip], name: rows[ip].flatMap { saved?.name(of: $0) })
            }
        }
        for ip in Set(previous.keys).subtracting(current.keys).sorted() {
            if let device = previous[ip] {
                let row = saved?.row(for: device)
                logDevice(device, joined: false, network: network, row: row, name: row.flatMap { saved?.name(of: $0) })
            }
        }
        knownDevices[network] = current
    }

    /// A joined or left device, named (`name`) by its saved row's device when it matches one;
    /// otherwise a joined device by its hostname or maker and a left one by its IP, as before #491.
    private func logDevice(_ device: DiscoveredDevice, joined: Bool, network: UUID?, row: LocalDevice?, name: String?) {
        let ip = device.ipAddress
        let label = name ?? (joined ? device.hostname ?? device.maker ?? ip : ip)
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
