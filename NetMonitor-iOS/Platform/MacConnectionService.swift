// The link's state stays private to this type (#590); splitting it across files would widen that
// access to the whole module, so the file is longer than the usual limit instead.
// swiftlint:disable file_length
import Foundation
import NetMonitorCore
import Network
import os
import UIKit

// MARK: - MacConnectionService

/// The phone end of the companion link (#590): TLS 1.3 with this phone's identity, pinning the
/// paired Mac's key. Nothing is sent on a link before the Mac's `serverHello`.
@MainActor
@Observable
final class MacConnectionService: MacConnectionServiceProtocol {

    // MARK: - Shared Instance

    static let shared: MacConnectionService = .init(insightClient: PhoneInsight.linkClient, macStore: defaultMacStore())
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "MacConnectionService")

    // MARK: - Public State

    private(set) var connectionState: MacConnectionState = .disconnected
    private(set) var discoveredMacs: [DiscoveredMac] = []
    private(set) var isBrowsing: Bool = false
    private(set) var connectedMacName: String?
    private(set) var lastStatusUpdate: StatusUpdatePayload?
    private(set) var lastTargetList: TargetListPayload?
    private(set) var lastDeviceList: DeviceListPayload?
    /// When `lastDeviceList` arrived over the current link; nil once the link drops (#598).
    private(set) var lastDeviceListReceivedAt: Date?
    /// The Mac this phone is paired with (#590).
    private(set) var pairedMac: PairedMacRecord?
    private(set) var linkProblem: MacLinkProblem?
    private(set) var pairingState: PhonePairingState = .idle

    // MARK: - Private

    /// What the current link is for.
    private enum LinkMode {
        case paired(PairedMacRecord, identity: CompanionIdentity)
        case pairing(PhonePairingAttempt)
    }

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
    private var linkSession = CompanionLinkSession(heartbeatInterval: MacConnectionService.heartbeatInterval)
    private let networkProfileManager: NetworkProfileManager
    private let macStore: PairedMacStore
    private var linkMode: LinkMode?
    private var session: CompanionVerifiedSession?
    /// True from `.ready` until the Mac's `serverHello` authorises the link.
    private var awaitingHello = false

    // MARK: - Constants

    private static let serviceType = "_netmon._tcp"
    private static let heartbeatInterval: TimeInterval = 15
    private static let heartbeatVersion = "1.0"

    /// Fed with the Mac's heartbeats and insight replies, and told when the link ends (#457).
    private let insightClient: CompanionInsightClient

    /// Tests make their own; the app uses `shared`.
    init(
        insightClient: CompanionInsightClient,
        networkProfileManager: NetworkProfileManager = NetworkProfileManager(),
        macStore: PairedMacStore
    ) {
        self.insightClient = insightClient
        self.networkProfileManager = networkProfileManager
        self.macStore = macStore
        do {
            pairedMac = try macStore.load()
        } catch {
            Self.logger.error("Couldn't read the paired Mac: \(String(describing: error), privacy: .public)")
        }
    }

    /// The Keychain, or memory for `--uitesting` launches.
    private static func defaultMacStore() -> PairedMacStore {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return PairedMacStore(backing: UITestFakeMacPairing.store)
        }
        return PairedMacStore(backing: CompanionKeychain(service: "com.netmonitor.companion.mac", accessibility: .whenUnlocked))
    }

    // Note: cleanup is handled by disconnect() and stopBrowsing() which
    // should be called before the service is released.

}

// MARK: - Browsing

extension MacConnectionService {
    func startBrowsing() {
        stopBrowsing()

        isBrowsing = true
        // Browsing doesn't change a link that is up or coming up.
        if !connectionState.isConnected, connectionState != .connecting {
            connectionState = .browsing
        }
        discoveredMacs = []
        if let fake = UITestFakeMacPairing.discovered {
            discoveredMacs = [fake.mac]
            endpointCache = [fake.mac.id: fake.endpoint]
            return
        }

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: Self.serviceType, domain: nil)
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
                var macID: UUID?
                var version: Int?
                if case .bonjour(let txt) = result.metadata {
                    macID = txt["mac"].flatMap(UUID.init(uuidString:))
                    version = txt["pv"].flatMap { Int($0) }
                }
                macs.append(NetMonitorCore.DiscoveredMac(id: id, name: name, macID: macID, protocolVersion: version))
                cache[id] = result.endpoint
            }
        }
        endpointCache = cache
        discoveredMacs = macs
    }

    /// Whether `mac` is the one this phone is paired with.
    func isPaired(with mac: DiscoveredMac) -> Bool {
        guard let pairedMac, let macID = mac.macID else { return false }
        return pairedMac.macID == macID
    }

}

// MARK: - Connection

extension MacConnectionService {
    /// Connects to `mac` if this phone is paired with it; otherwise says why not.
    func connect(to mac: NetMonitorCore.DiscoveredMac) {
        guard let endpoint = endpointCache[mac.id] else { return }
        guard mac.isCurrent else {
            linkProblem = .macNeedsUpdate
            return
        }
        guard let record = pairedMac, isPaired(with: mac) else {
            linkProblem = .notPaired
            return
        }
        connectPaired(record, endpoint: endpoint, macName: mac.name)
    }

    /// Connects to the paired Mac at a typed address.
    func connectDirect(host: String, port: UInt16) {
        guard let record = pairedMac else {
            linkProblem = .notPaired
            return
        }
        // swiftlint:disable:next force_unwrapping
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
        connectPaired(record, endpoint: endpoint, macName: record.macName)
    }

    private func connectPaired(_ record: PairedMacRecord, endpoint: NWEndpoint, macName: String) {
        disconnect()
        linkProblem = nil
        pendingEndpoint = endpoint
        pendingMacName = macName
        shouldAutoReconnect = true
        openPairedLink(record, endpoint: endpoint, macName: macName)
    }

    /// A TLS link with this phone's pairing identity, pinning the paired Mac's key. Keeps the
    /// reconnect backoff, so the reconnect path uses it directly.
    private func openPairedLink(_ record: PairedMacRecord, endpoint: NWEndpoint, macName: String) {
        guard let identity = try? CompanionIdentity(rawRepresentation: record.phoneIdentity),
              let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: { [pin = record.macPin] in $0 == pin }) else {
            linkProblem = .notRecognized
            shouldAutoReconnect = false
            return
        }
        connectionState = .connecting
        linkMode = .paired(record, identity: identity)
        setupConnection(NWConnection(to: endpoint, using: parameters), macName: macName)
    }

    func disconnect() {
        connectionGeneration = UUID()
        shouldAutoReconnect = false
        linkSession.reset()
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
        tearDownLink()
        frameDecoder = CompanionFrameDecoder()
        lastStatusUpdate = nil
        lastTargetList = nil
        lastDeviceList = nil
        linkMode = nil
    }

    /// Ends what a link carried: its heartbeat, the Mac's name, the freshness of its device list
    /// (#598), and the Mac's model, whose requests in flight fail (#457). Every path that drops or replaces a link calls it.
    private func tearDownLink() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectedMacName = nil
        // The Mac's device list stays for display, but is no longer evidence of presence (#598).
        lastDeviceListReceivedAt = nil
        session = nil
        awaitingHello = false
        insightClient.disconnected()
    }

    private func setupConnection(_ conn: NWConnection, macName: String) {
        let generation = UUID()
        connectionGeneration = generation
        connection = conn
        // A new link: the Mac advertises insight again in its first heartbeat.
        tearDownLink()

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
            // TLS 1.3: the client is ready before the Mac has judged its certificate, so the link
            // is only usable once the Mac's serverHello arrives.
            guard let verified = CompanionTLS.sessionFacts(of: connection).verified else {
                failAuthentication()
                return
            }
            session = verified
            awaitingHello = true
            frameDecoder = CompanionFrameDecoder()
            scheduleReceive(connection: connection, generation: generation)

        case .failed(let error):
            self.connection = nil
            if case .tls = error {
                failAuthentication()
                return
            }
            connectionState = .error(error.localizedDescription)
            tearDownLink()
            failPairingIfNeeded("The connection to the Mac failed.")
            scheduleReconnect(generation: generation)

        case .cancelled:
            tearDownLink()
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

    /// The handshake or the Mac's verdict refused this phone: say so and stop retrying.
    private func failAuthentication() {
        let wasPairing = if case .pairing? = linkMode {
            true
        } else {
            false
        }
        shouldAutoReconnect = false
        connection?.cancel()
        connection = nil
        tearDownLink()
        if wasPairing {
            pairingState = .failed("Couldn't verify the Mac. Check the code and try again.")
            connectionState = .disconnected
        } else {
            linkProblem = .notRecognized
            connectionState = .error(MacLinkProblem.notRecognized.message)
        }
        linkMode = nil
    }

    private func failPairingIfNeeded(_ message: String) {
        if case .pairing? = linkMode {
            pairingState = .failed(message)
            shouldAutoReconnect = false
            linkMode = nil
        }
    }

}

// MARK: - Receive

extension MacConnectionService {
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
                    } else if self.connectionGeneration == generation {
                        self.scheduleReceive(connection: connection, generation: generation)
                    }
                }
            }
        }
    }

    private func handleReceiveTermination(error: NWError?, generation: UUID) {
        guard connectionGeneration == generation else { return }
        // Closed before the Mac said hello: the Mac refused this phone's certificate.
        if awaitingHello {
            failAuthentication()
            return
        }
        if case .pairing? = linkMode {
            connection = nil
            tearDownLink()
            switch pairingState {
            case .comparing:
                pairingState = .failed("The Mac closed the pairing.")
            case .connecting:
                pairingState = .failed("The Mac didn't accept the code. Check it and try again.")
            case .idle, .paired, .failed:
                break
            }
            linkMode = nil
            connectionState = .disconnected
            return
        }
        connection = nil
        tearDownLink()
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
        // Any inbound message proves the link is alive, not just heartbeats.
        linkSession.recordReceived(at: Date())
        Self.logger.debug("Received companion message: \(message.logName, privacy: .public)")
        switch message {
        case .serverHello(let payload):
            handleServerHello(payload)
            return
        case .pairChallenge(let payload):
            handlePairChallenge(payload)
            return
        case .pairResult(let payload):
            handlePairResult(payload)
            return
        default:
            break
        }
        // Everything else only on a paired, authorised link.
        guard !awaitingHello, case .paired? = linkMode else { return }
        handleLinkMessage(message)
    }

    private func handleLinkMessage(_ message: CompanionMessage) {
        switch message {
        case .statusUpdate(let payload):
            lastStatusUpdate = payload
        case .targetList(let payload):
            lastTargetList = payload
        case .deviceList(let payload):
            lastDeviceList = payload
            lastDeviceListReceivedAt = Date()
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
        case .heartbeat(let payload):
            Self.logger.debug("Heartbeat received")
            insightClient.received(heartbeat: payload)
        case .insightResponse(let payload):
            insightClient.received(payload)
        case .command, .insightRequest, .pairRequest, .unpair, .serverHello, .pairChallenge, .pairResult:
            // Outbound only from iOS, or handled above; ignore if received
            break
        case .unknown:
            // A newer Mac's message type: ignored, and the link stays up.
            break
        }
    }

    private func sendLocalNetworkProfile() async {
        networkProfileManager.detectLocalNetwork()
        guard let profile = networkProfileManager.localProfile
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

}

// MARK: - Heartbeat and reconnect

extension MacConnectionService {
    private func startHeartbeat(generation: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled, let self else { break }
                await self.sendHeartbeat()
                let stillAlive = self.checkLinkLiveness(generation: generation)
                if !stillAlive {
                    break
                }
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

    /// Checks whether the companion link is still alive after a heartbeat send. If it has gone
    /// stale (no inbound message within `heartbeatInterval * missedBeatsBeforeStale`), tears down
    /// the connection so the existing `scheduleReconnect` path takes over. Returns whether the
    /// heartbeat loop should keep running.
    private func checkLinkLiveness(generation: UUID) -> Bool {
        guard connectionGeneration == generation else { return false }
        guard linkSession.isAlive(now: Date()) else {
            Self.logger.warning("Companion link stale — no messages received recently, reconnecting")
            connection?.cancel()
            return false
        }
        return true
    }

    // MARK: - Reconnect

    private func scheduleReconnect(generation: UUID) {
        guard shouldAutoReconnect,
              connectionGeneration == generation,
              reconnectTask == nil,
              case .paired(let record, _)? = linkMode,
              let endpoint = lastConnectedEndpoint ?? pendingEndpoint else { return }

        let delay = linkSession.nextReconnectDelay(jitterFraction: Double.random(in: 0...1))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }

            await MainActor.run {
                self.reconnectTask = nil
                guard self.shouldAutoReconnect,
                      self.connectionGeneration == generation else { return }
                self.openPairedLink(record, endpoint: endpoint, macName: self.lastConnectedMacName ?? record.macName)
            }
        }
    }
}

// MARK: - Session start and pairing (#590)

extension MacConnectionService {
    private func handleServerHello(_ payload: ServerHelloPayload) {
        guard awaitingHello, let mode = linkMode else { return }
        awaitingHello = false
        switch (mode, payload.mode) {
        case (.paired, .paired):
            linkSession.recordConnected(at: Date())
            linkProblem = nil
            connectionState = .connected
            connectedMacName = pendingMacName ?? payload.macName
            lastConnectedEndpoint = pendingEndpoint
            lastConnectedMacName = pendingMacName
            let generation = connectionGeneration
            startHeartbeat(generation: generation)
            Task { await sendLocalNetworkProfile() }
        case (.paired, .pairing):
            // The Mac doesn't know this phone's key any more.
            failAuthentication()
        case (.pairing(var attempt), .pairing):
            guard let session else { return }
            let request = PhonePairingFlow.pairRequest(for: &attempt, hello: payload, session: session, phoneName: UIDevice.current.name)
            linkMode = .pairing(attempt)
            Task { await sendMessage(request) }
        case (.pairing, .paired):
            failAuthentication()
        }
    }

    private func handlePairChallenge(_ payload: PairChallengePayload) {
        guard !awaitingHello, case .pairing(var attempt)? = linkMode, !attempt.challengeVerified, let session else { return }
        pairingState = PhonePairingFlow.check(payload, attempt: &attempt, session: session)
        linkMode = .pairing(attempt)
        if case .failed = pairingState {
            endPairingLink()
        }
    }

    private func handlePairResult(_ payload: PairResultPayload) {
        guard case .pairing(let attempt)? = linkMode, attempt.challengeVerified, let session else { return }
        let record: PairedMacRecord
        do {
            record = try PhonePairingFlow.record(for: payload, attempt: attempt, session: session).get()
            try macStore.save(record)
        } catch let failure as PhonePairingFlow.Failure {
            pairingState = .failed(failure.message)
            endPairingLink()
            return
        } catch {
            pairingState = .failed("This iPhone couldn't save the pairing. Remove it on the Mac and pair again.")
            endPairingLink()
            return
        }
        pairedMac = record
        linkProblem = nil
        pairingState = .paired(macName: record.macName)
        let endpoint = pendingEndpoint
        endPairingLink()
        if let endpoint {
            connectPaired(record, endpoint: endpoint, macName: record.macName)
        }
    }

    private func endPairingLink() {
        connectionGeneration = UUID()
        shouldAutoReconnect = false
        connection?.cancel()
        connection = nil
        tearDownLink()
        linkMode = nil
        connectionState = .disconnected
    }

    /// Pairs with the Mac in a scanned QR invitation, pinning the Mac's key from the QR.
    func pair(with invitation: CompanionPairingInvitation) {
        let endpoint: NWEndpoint
        if let mac = discoveredMacs.first(where: { $0.macID == invitation.macID }), let cached = endpointCache[mac.id] {
            endpoint = cached
        } else if let host = invitation.host, let port = NWEndpoint.Port(rawValue: invitation.port) {
            endpoint = .hostPort(host: .init(host), port: port)
        } else {
            pairingState = .failed("Couldn't find that Mac on this network.")
            return
        }
        startPairing(
            kind: .qr, secret: invitation.secret, endpoint: endpoint, macName: invitation.macName,
            host: invitation.host, port: invitation.port, acceptsMac: { [pin = invitation.macPin] in $0 == pin }
        )
    }

    /// Pairs with `mac` using the code typed from its screen. The Mac's key isn't known in
    /// advance, so the Mac must prove the same code before anything is trusted.
    func pair(code: CompanionPairingCode, with mac: DiscoveredMac) {
        guard let endpoint = endpointCache[mac.id] else {
            pairingState = .failed("Couldn't find that Mac on this network.")
            return
        }
        guard mac.isCurrent else {
            pairingState = .failed(MacLinkProblem.macNeedsUpdate.message)
            return
        }
        startPairing(kind: .code, secret: code.secret, endpoint: endpoint, macName: mac.name, host: nil, port: 8849, acceptsMac: { _ in true })
    }

    // swiftlint:disable:next function_parameter_count
    private func startPairing(
        kind: CompanionPairingProof.Kind,
        secret: Data,
        endpoint: NWEndpoint,
        macName: String,
        host: String?,
        port: UInt16,
        acceptsMac: @escaping @Sendable (Data) -> Bool
    ) {
        // A fresh identity for every pairing: nothing ties it to an earlier one.
        let identity = CompanionIdentity()
        guard let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: acceptsMac) else {
            pairingState = .failed("Couldn't create this iPhone's key.")
            return
        }
        disconnect()
        linkProblem = nil
        pairingState = .connecting
        connectionState = .connecting
        pendingEndpoint = endpoint
        pendingMacName = macName
        linkMode = .pairing(PhonePairingAttempt(kind: kind, secret: secret, identity: identity, host: host, port: port, macName: macName))
        setupConnection(NWConnection(to: endpoint, using: parameters), macName: macName)
    }

    func resetPairingState() {
        if case .comparing = pairingState {
            endPairingLink()
        }
        pairingState = .idle
    }

    /// Forgets the paired Mac: tells it (if connected) to drop this phone, then deletes the key.
    func forgetMac() async {
        if connectionState.isConnected {
            await sendMessage(.unpair(UnpairPayload()))
        }
        disconnect()
        do {
            try macStore.forget()
        } catch {
            Self.logger.error("Couldn't delete the paired Mac: \(String(describing: error), privacy: .public)")
        }
        pairedMac = nil
        linkProblem = nil
        pairingState = .idle
    }
}

// MARK: - Send

extension MacConnectionService {

    func send(command: CommandPayload) async {
        let message = CompanionMessage.command(command)
        await sendMessage(message)
    }

    /// Sends an insight request for the injected insight client; false when there is no link (#457).
    func sendInsight(_ message: CompanionMessage) async -> Bool {
        await sendMessage(message)
    }

    /// Send a CompanionMessage with 4-byte big-endian length prefix + JSON payload, only on a
    /// link the Mac has greeted, and app data only on a paired one. Returns whether it was sent.
    @discardableResult
    private func sendMessage(_ message: CompanionMessage) async -> Bool {
        guard let conn = connection, !awaitingHello, let linkMode else { return false }
        if case .pairing = linkMode {
            guard case .pairRequest = message else { return false }
        }
        do {
            let data = try message.encodeLengthPrefixed()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
            return true
        } catch {
            Self.logger.error("Send error: \(error)")
            return false
        }
    }
}

// MARK: - Testing Support

extension MacConnectionService {
    /// Exposes the delegated link session state for tests, proving MacConnectionService keeps
    /// no parallel copy of liveness/reconnect state.
    var linkSessionForTesting: CompanionLinkSession { linkSession }

    /// Drops the link as every disconnect path does (a failure, the Mac closing it, a cancel, the
    /// user disconnecting), without a real connection.
    func dropLinkForTesting() {
        tearDownLink()
    }

    /// Feeds frames as if from an authorised, paired link.
    func processIncomingDataForTesting(_ data: Data) async {
        let batch = await frameDecoder.append(data)
        for message in batch.messages {
            handleLinkMessage(message)
            linkSession.recordReceived(at: Date())
        }
    }

    func endpointForTesting(_ mac: DiscoveredMac) -> NWEndpoint? {
        endpointCache[mac.id]
    }

    /// A Mac at `endpoint`, as if Bonjour had found it.
    func addDiscoveredMacForTesting(_ mac: DiscoveredMac, endpoint: NWEndpoint) {
        discoveredMacs.append(mac)
        endpointCache[mac.id] = endpoint
    }
}
