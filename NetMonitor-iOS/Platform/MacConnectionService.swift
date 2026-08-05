import Foundation
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
    private var frameDecoder = CompanionFrameDecoder()
    private var connectionGeneration = UUID()
    private var pendingEndpoint: NWEndpoint?
    private var pendingMacName: String?
    private var lastConnectedEndpoint: NWEndpoint?
    private var lastConnectedMacName: String?
    private var shouldAutoReconnect = false
    private var reconnectAttempt = 0
    private let networkProfileManager: NetworkProfileManager

    // MARK: - Constants

    private static let serviceType = "_netmon._tcp"
    private static let heartbeatInterval: TimeInterval = 15
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
        connectionGeneration = UUID()
        shouldAutoReconnect = false
        reconnectAttempt = 0
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
        connectedMacName = nil
        frameDecoder = CompanionFrameDecoder()
        lastStatusUpdate = nil
        lastTargetList = nil
        lastDeviceList = nil
    }

    private func setupConnection(_ conn: NWConnection, macName: String) {
        let generation = UUID()
        connectionGeneration = generation
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.connectionGeneration == generation else { return }
                self.handleConnectionState(state, connection: conn, macName: macName, generation: generation)
            }
        }

        conn.start(queue: queue)
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        connection: NWConnection,
        macName: String,
        generation: UUID
    ) {
        switch state {
        case .ready:
            reconnectAttempt = 0
            connectionState = .connected
            connectedMacName = macName
            lastConnectedEndpoint = pendingEndpoint
            lastConnectedMacName = pendingMacName
            frameDecoder = CompanionFrameDecoder()
            // Delay slightly to let UI settle before starting I/O
            Task { @MainActor [weak self] in
                guard let self, self.connectionGeneration == generation else { return }
                try? await Task.sleep(for: .milliseconds(100))
                guard self.connectionGeneration == generation else { return }
                self.startHeartbeat()
                self.scheduleReceive(connection: connection, generation: generation)
                await self.sendLocalNetworkProfile()
            }

        case .failed(let error):
            self.connection = nil
            connectionState = .error(error.localizedDescription)
            connectedMacName = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            scheduleReconnect(generation: generation)

        case .cancelled:
            if shouldAutoReconnect {
                self.connection = nil
                connectionState = .disconnected
                scheduleReconnect(generation: generation)
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

    private func scheduleReceive(connection: NWConnection, generation: UUID) {
        let decoder = frameDecoder
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                let batch: CompanionFrameBatch
                if let content, !content.isEmpty {
                    batch = await decoder.append(content)
                } else {
                    batch = CompanionFrameBatch(messages: [], errors: [])
                }

                await MainActor.run {
                    guard let self, self.connectionGeneration == generation else { return }
                    for message in batch.messages {
                        self.handleMessage(message)
                    }
                    if !batch.errors.isEmpty {
                        Self.logger.error("Rejected \(batch.errors.count) companion frame(s)")
                    }

                    if isComplete || error != nil {
                        self.handleReceiveTermination(error: error, generation: generation)
                    } else {
                        self.scheduleReceive(connection: connection, generation: generation)
                    }
                }
            }
        }
    }

    private func handleReceiveTermination(error: NWError?, generation: UUID) {
        guard connectionGeneration == generation else { return }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connection = nil
        connectedMacName = nil
        if let error {
            connectionState = .error(error.localizedDescription)
        } else {
            connectionState = .disconnected
        }
        if shouldAutoReconnect {
            scheduleReconnect(generation: generation)
        }
    }

    private func handleMessage(_ message: CompanionMessage) {
        Self.logger.debug("Received companion message: \(message.logName, privacy: .public)")
        switch message {
        case .statusUpdate(let payload):
            lastStatusUpdate = payload
        case .targetList(let payload):
            lastTargetList = payload
        case .deviceList(let payload):
            lastDeviceList = payload
        case .networkProfile(let payload):
            Self.logger.info("Received network profile from Mac")
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
            Self.logger.error("Error from Mac: code=\(payload.code, privacy: .public)")
        case .heartbeat:
            Self.logger.debug("Heartbeat received")
        case .command:
            // Commands are outbound only from iOS; ignore if received
            break
        }
    }

    // MARK: - Testing Support

    func processIncomingDataForTesting(_ data: Data) async {
        let batch = await frameDecoder.append(data)
        for message in batch.messages {
            handleMessage(message)
        }
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

    static func reconnectDelay(attempt: Int, jitterFraction: Double) -> TimeInterval {
        let exponent = Double(max(attempt - 1, 0))
        let base = min(60, pow(2, exponent))
        let jitter = base * 0.25 * min(max(jitterFraction, 0), 1)
        return min(60, base + jitter)
    }

    private func scheduleReconnect(generation: UUID) {
        guard shouldAutoReconnect,
              connectionGeneration == generation,
              reconnectTask == nil,
              let endpoint = lastConnectedEndpoint ?? pendingEndpoint else { return }

        reconnectAttempt += 1
        let delay = Self.reconnectDelay(attempt: reconnectAttempt, jitterFraction: Double.random(in: 0...1))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            await MainActor.run {
                self.reconnectTask = nil
                guard self.shouldAutoReconnect,
                      self.connectionGeneration == generation else { return }
                self.connectionState = .connecting

                let parameters = NWParameters.tcp
                let conn = NWConnection(to: endpoint, using: parameters)
                self.setupConnection(conn, macName: self.lastConnectedMacName ?? "Mac")
            }
        }
    }
}

private extension CompanionMessage {
    var logName: String {
        switch self {
        case .statusUpdate: "statusUpdate"
        case .targetList: "targetList"
        case .deviceList: "deviceList"
        case .networkProfile: "networkProfile"
        case .command: "command"
        case .toolResult: "toolResult"
        case .error: "error"
        case .heartbeat: "heartbeat"
        }
    }
}
