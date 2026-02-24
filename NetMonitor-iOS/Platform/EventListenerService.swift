import Foundation
import NetMonitorCore

// MARK: - EventListenerService

/// Observes NetworkMonitorService and DeviceDiscoveryService to log connectivity
/// and device-change events into NetworkEventService for the Timeline tab.
@MainActor
final class EventListenerService {

    static let shared = EventListenerService()

    // MARK: - Dependencies

    private let eventService: any NetworkEventServiceProtocol
    private let networkMonitor: NetworkMonitorService
    private let discoveryService: DeviceDiscoveryService

    // MARK: - Tracking state

    private var lastIsConnected: Bool?
    private var lastConnectionType: ConnectionType?
    private var wasScanning: Bool = false
    private var knownDeviceIPs: Set<String> = []

    private var monitorTask: Task<Void, Never>?

    // MARK: - Init

    init(
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        networkMonitor: NetworkMonitorService = NetworkMonitorService.shared,
        discoveryService: DeviceDiscoveryService = DeviceDiscoveryService.shared
    ) {
        self.eventService = eventService
        self.networkMonitor = networkMonitor
        self.discoveryService = discoveryService
    }

    // MARK: - Lifecycle

    func start() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Suspend until any tracked @Observable property changes
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.networkMonitor.isConnected
                        _ = self.networkMonitor.connectionType
                        _ = self.discoveryService.isScanning
                        _ = self.discoveryService.discoveredDevices
                    } onChange: {
                        continuation.resume()
                    }
                }
                self.handleConnectivityChange()
                self.handleScanChange()
            }
        }
    }

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

        eventService.log(type: .connectivityChange, title: title, details: nil, severity: severity)
        lastIsConnected = isConnected
        lastConnectionType = connectionType
    }

    private func handleScanChange() {
        let isScanning = discoveryService.isScanning

        // Detect scan completion: was scanning, now not scanning
        if wasScanning && !isScanning {
            let currentDevices = discoveryService.discoveredDevices
            let currentIPs = Set(currentDevices.map { $0.ipAddress })

            let joined = currentIPs.subtracting(knownDeviceIPs)
            let left = knownDeviceIPs.subtracting(currentIPs)

            for ip in joined.sorted() {
                let device = currentDevices.first { $0.ipAddress == ip }
                let label = device?.hostname ?? device?.vendor ?? ip
                eventService.log(
                    type: .deviceJoined,
                    title: "Device Joined: \(label)",
                    details: ip == label ? nil : ip,
                    severity: .success
                )
            }

            for ip in left.sorted() {
                eventService.log(
                    type: .deviceLeft,
                    title: "Device Left: \(ip)",
                    details: nil,
                    severity: .warning
                )
            }

            let count = currentDevices.count
            eventService.log(
                type: .scanComplete,
                title: "Scan Complete — \(count) \(count == 1 ? "device" : "devices") found",
                details: nil,
                severity: .info
            )

            knownDeviceIPs = currentIPs
        }

        wasScanning = isScanning
    }
}
