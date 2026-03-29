zimport Foundation
import NetMonitorCore
import Network
import os

// MARK: - MacConnectionState Display Extension

extension MacConnectionState {
    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .browsing: "Browsing…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }
}

// MARK: - MacConnectionService

@MainActor
@Observable
final class MacConnectionService: MacConnectionServiceProtocol {

    // MARK: - Shared Instance

    static let shared = MacConnectionService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "MacConnectionService")

    // MARK: - Public State

    private(set) var connectionState: MacConnectionState = .disconnected
    private(set) var discoveredMacs: [DiscoveredMac] = []
    private(set) var isBrowsing: Bool = false
    private(set) var connectedMacName: String?
    private(set) var lastStatusUpdate: StatusUpdatePayload?
    private(set) var lastTargetList: TargetListPayload?
    private(set) var lastDeviceList: DeviceListPayload?

    // MARK: - Private

    /// Maps DiscoveredMac.id → NWEndpoint for connection lookups
    private var endpointCache: [String: NWEndpoint] = [:]
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.netmonitor.macconnection", qos: .userInitiated)
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var receiveBuffer = Data()
    private var pendingEndpoint: NWEndpoint?
    private var pendingMacName: String?
    private var lastConnectedEndpoint: NWEndpoint?
    private var lastConnectedMacName: String?
    private var shouldAutoReconnect = false
    private let networkProfileManager: NetworkProfileManager

    // MARK: - Constants

    private static let serviceType = "_netmon._tcp"
    private static let heartbeatInterval: TimeInterval = 15
    private static let reconnectDelay: TimeInterval = 5
    private static let heartbeatVersion = "1.0"

    private init(networkProfileManager: NetworkProfileManager = NetworkProfileManager()) {
        self.networkProfileManager = networkProfileManager
    }

    // Note: cleanup is handled by disconnect() and stopBrowsing() which
    // should be called before the service is released.

    // MARK: - Browsing

    func startBrowsing() {
        stopBrowsing()

        isBrowsing = true
        connectionState = .browsing
        discoveredMacs = []

        let descriptor = NWBrowser.Descriptor.bonjour(type: Self.serviceType, domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    Self.logger.info("NWBrowser ready — scanning for \(Self.serviceType, privacy: .public)")
                case .failed(let error):
                    Self.logger.error("NWBrowser failed: \(error, privacy: .public)")
                    self.isBrowsing = false
                    self.connectionState = .error("Bonjour browser failed: \(error.localizedDescription)")
                case .cancelled:
                    Self.logger.info("NWBrowser cancelled")
                    self.isBrowsing = false
                case .waiting(let error):
                    Self.logger.warning("NWBrowser waiting: \(error, privacy: .public)")
                default:
                    break
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleBrowseResults(results)
            }
        }

        newBrowser.start(queue: queue)
        browser = newBrowser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        if case .browsing = connectionState {
            connectionState = .disconnected
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var macs: [NetMonitorCore.DiscoveredMac] = []
        var cache: [String: NWEndpoint] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let id = "\(name)-\(result.endpoint.debugDescription)"
                let mac = NetMonitorCore.DiscoveredMac(id: id, name: name)
                macs.append(mac)
                cache[id] = result.endpoint
            }
        }
        endpointCache = cache
        discoveredMacs = macs
    }

    // MARK: - Connection

    func connect(to mac: NetMonitorCore.DiscoveredMac) {
        guard let endpoint = endpointCache[mac.id] else { return }
        disconnect()

        connectionState = .connecting
        pendingEndpoint = endpoint
        pendingMacName = mac.name
        shouldAutoReconnect = true

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: parameters)
        setupConnection(conn, macName: mac.name)
    }

    func connectDirect(host: String, port: UInt16) {
        disconnect()

        connectionState = .connecting
        shouldAutoReconnect = true

        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
        pendingEndpoint = endpoint
        pendingMacName = host

        let parameters = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: parameters)
        setupConnection(conn, macName: host)
    }

    func disconnect() {
        shouldAutoReconnect = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
        connectedMacName = nil
        receiveBuffer = Data()
        lastStatusUpdate = nil
        lastTargetList = nil
        lastDeviceList = nil
    }

    private func setupConnection(_ conn: NWConnection, macName: String) {
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleConnectionState(state, macName: macName)
            }
        }

        conn.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State, macName: String) {
        switch state {
        case .ready:
            connectionState = .connected
            connectedMacName = macName
            lastConnectedEndpoint = pendingEndpoint
            lastConnectedMacName = pendingMacName
            receiveBuffer = Data()
            // Delay slightly to let UI settle before starting I/O
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(100))
                self.startHeartbeat()
                self.scheduleReceive()
                await self.sendLocalNetworkProfile()
            }

        case .failed(let error):
            connectionState = .error(error.localizedDescription)
            connectedMacName = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            scheduleReconnect()

        case .cancelled:
            if shouldAutoReconnect {
                connectionState = .disconnected
                scheduleReconnect()
            }

        case .waiting(let error):
            connectionState = .error("Waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    // MARK: - Send

    func send(command: CommandPayload) async {
        let message = CompanionMessage.command(command)
        await sendMessage(message)
    }

    /// Send a CompanionMessage with 4-byte big-endian length prefix + JSON payload.
    /// Matches the macOS CompanionService wire format.
    private func sendMessage(_ message: CompanionMessage) async {
        do {
            let data = try message.encodeLengthPrefixed()
            guard let conn = connection else { return }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } catch {
            Self.logger.error("Send error: \(error)")
        }
    }

    // MARK: - Receive

    private func scheduleReceive() {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let data = content, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.processReceiveBuffer()
                }

                if isComplete || error != nil {
                    // Connection ended
                    return
                }

                self.scheduleReceive()
            }
        }
    }

    private func processReceiveBuffer() {
        // Process all complete frames in the buffer
        while receiveBuffer.count >= 4 {
            // Read 4 bytes explicitly to avoid UnsafeRawBufferPointer slice issues
            let b0 = receiveBuffer[receiveBuffer.startIndex]
            let b1 = receiveBuffer[receiveBuffer.startIndex + 1]
            let b2 = receiveBuffer[receiveBuffer.startIndex + 2]
            let b3 = receiveBuffer[receiveBuffer.startIndex + 3]
            let length = UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)

            // Sanity check — reject absurdly large frames (max 10 MB)
            guard length > 0, length <= 10_000_000 else {
                Self.logger.error("Invalid frame length \(length), clearing buffer")
                receiveBuffer.removeAll()
                break
            }

            let totalFrameSize = 4 + Int(length)
            guard receiveBuffer.count >= totalFrameSize else {
                // Need more data
                break
            }

            let startIndex = receiveBuffer.startIndex
            let payloadStartIndex = startIndex + 4
            let payloadEndIndex = startIndex + totalFrameSize
            let jsonData = receiveBuffer.subdata(in: payloadStartIndex..<payloadEndIndex)
            receiveBuffer.removeSubrange(startIndex..<payloadEndIndex)

            do {
                let message = try CompanionMessage.decode(from: jsonData)
                handleMessage(message)
            } catch {
                Self.logger.error("Decode error: \(error)")
            }
        }
    }

    private func handleMessage(_ message: CompanionMessage) {
        Self.logger.info("handleMessage: received \(String(describing: message))")
        switch message {
        case .statusUpdate(let payload):
            lastStatusUpdate = payload
        case .targetList(let payload):
            lastTargetList = payload
        case .deviceList(let payload):
            lastDeviceList = payload
        case .networkProfile(let payload):
            Self.logger.info("Received network profile from Mac: \(payload.name)")
            let companionName = payload.sourceDeviceName.map { "\($0) Network" } ?? payload.name
            if networkProfileManager.upsertCompanionProfile(
                gateway: payload.gatewayIP,
                subnet: payload.subnet,
                name: companionName,
                interfaceName: payload.interfaceName
            ) != nil {
                Self.logger.info("Upserted companion profile, posting notification")
                NotificationCenter.default.post(name: .networkProfilesDidChange, object: nil)
            }
        case .toolResult(let payload):
            Self.logger.info("Tool result: \(payload.tool) - \(payload.success)")
        case .error(let payload):
            Self.logger.error("Error from Mac: \(payload.message)")
        case .heartbeat:
            Self.logger.debug("Heartbeat received")
        case .command:
            // Commands are outbound only from iOS; ignore if received
            break
        }
    }

    // MARK: - Testing Support

    func processIncomingDataForTesting(_ data: Data) {
        receiveBuffer.append(data)
        processReceiveBuffer()
    }

    private func sendLocalNetworkProfile() async {
        networkProfileManager.detectLocalNetwork()
        guard let profile = networkProfileManager.profiles.first(where: { $0.isLocal })
                ?? networkProfileManager.activeProfile else {
            return
        }

        let payload = NetworkProfilePayload(
            name: profile.displayName,
            gatewayIP: profile.gatewayIP,
            subnet: profile.subnet,
            interfaceName: profile.interfaceName,
            sourceDeviceName: ProcessInfo.processInfo.hostName
        )
        await sendMessage(.networkProfile(payload))
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled else { break }
                await self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() async {
        let message = CompanionMessage.heartbeat(HeartbeatPayload(
            timestamp: Date(),
            version: Self.heartbeatVersion
        ))
        await sendMessage(message)
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard shouldAutoReconnect, let endpoint = lastConnectedEndpoint else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.reconnectDelay))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            await MainActor.run {
                guard self.shouldAutoReconnect else { return }
                self.connectionState = .connecting

                let parameters = NWParameters.tcp
                let conn = NWConnection(to: endpoint, using: parameters)
                self.setupConnection(conn, macName: self.lastConnectedMacName ?? "Mac")
            }
        }
    }
}
