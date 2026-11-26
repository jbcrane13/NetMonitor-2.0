import Foundation
import NetMonitorCore
import Network
import os
import UIKit

// MARK: - MacConnectionService

/// The phone end of the companion link (#590): TLS 1.3 with this phone's identity, pinning the
/// paired Mac's key. Nothing is sent on a link before the Mac's `serverHello`. Only the Mac's
/// explicit refusal ends a paired link for good; every other failure retries with backoff.
@MainActor
@Observable
final class MacConnectionService: MacConnectionServiceProtocol {

    // MARK: - Shared Instance

    static let shared: MacConnectionService = .init(
        insightClient: PhoneInsight.linkClient, macStore: defaultMacStore(), defaults: defaultDefaults()
    )
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "MacConnectionService")

    // MARK: - Public State

    private(set) var connectionState: MacConnectionState = .disconnected
    var discoveredMacs: [DiscoveredMac] { browser.discoveredMacs }
    var isBrowsing: Bool { browser.isBrowsing }
    private(set) var connectedMacName: String?
    private(set) var lastStatusUpdate: StatusUpdatePayload?
    private(set) var lastTargetList: TargetListPayload?
    private(set) var lastDeviceList: DeviceListPayload?
    /// When `lastDeviceList` arrived over the current link; nil once the link drops (#598).
    private(set) var lastDeviceListReceivedAt: Date?
    /// The link's inventory offer and path (#585), reset with the link.
    private(set) var inventoryLink = CompanionInventoryLink()
    /// The Mac this phone is paired with (#590).
    private(set) var pairedMac: PairedMacRecord?
    private(set) var linkProblem: MacLinkProblem?
    /// Set when Forget This Mac couldn't delete the key; the key is blocked from use meanwhile.
    private(set) var forgetError: String?
    var pairingState: PhonePairingState { pairing.state }

    // MARK: - Private

    /// What the current link is for.
    private enum LinkMode {
        case paired(PairedMacRecord, identity: CompanionIdentity)
        case pairing
    }

    private let browser = MacBrowser()
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
    private let defaults: UserDefaults
    /// How long an attempt may take to reach the Mac's serverHello before it counts as failed.
    private let helloTimeout: Duration
    private let pairing = PhonePairingController()
    private var linkMode: LinkMode?
    private var session: CompanionVerifiedSession?
    /// True from `.ready` until the Mac's `serverHello` authorises the link.
    private var awaitingHello = false

    // MARK: - Constants

    private static let heartbeatInterval: TimeInterval = 15
    /// Forget This Mac couldn't delete the key: it must not be loaded or used until it is.
    static let pendingForgetKey = "netmonitor.companion.pendingForget"

    /// Fed with the Mac's heartbeats and insight replies, and told when the link ends (#457).
    private let insightClient: CompanionInsightClient

    /// Tests make their own; the app uses `shared`.
    init(
        insightClient: CompanionInsightClient,
        networkProfileManager: NetworkProfileManager = NetworkProfileManager(),
        macStore: PairedMacStore,
        defaults: UserDefaults = .standard,
        helloTimeout: Duration = .seconds(15)
    ) {
        self.insightClient = insightClient
        self.networkProfileManager = networkProfileManager
        self.macStore = macStore
        self.defaults = defaults
        self.helloTimeout = helloTimeout
        reloadPairedMacIfNeeded()
    }

    /// Reads the paired Mac if it isn't loaded yet. A launch while the phone is locked can't read
    /// the Keychain item (WhenUnlocked), so browsing and connecting try again. A key left behind
    /// by a failed Forget is deleted first and never loaded.
    private func reloadPairedMacIfNeeded() {
        guard pairedMac == nil else { return }
        if defaults.bool(forKey: Self.pendingForgetKey) {
            if (try? macStore.forget()) != nil {
                defaults.removeObject(forKey: Self.pendingForgetKey)
                forgetError = nil
            }
            return
        }
        do {
            pairedMac = try macStore.load()
        } catch {
            Self.logger.error("Couldn't read the paired Mac: \(String(describing: error), privacy: .public)")
        }
    }

    /// The Keychain, or memory for `--uitesting` launches of Debug builds.
    private static func defaultMacStore() -> PairedMacStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return PairedMacStore(backing: UITestFakeMacPairing.store)
        }
        #endif
        return PairedMacStore(backing: CompanionKeychain(service: "com.netmonitor.companion.mac", accessibility: .whenUnlocked))
    }

    private static func defaultDefaults() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           let suite = UserDefaults(suiteName: UITestFakeMacPairing.defaultsSuite) {
            return suite
        }
        #endif
        return .standard
    }

    // Note: cleanup is handled by disconnect() and stopBrowsing() which
    // should be called before the service is released.
}

// MARK: - Browsing

extension MacConnectionService {
    func startBrowsing() {
        reloadPairedMacIfNeeded()
        // Browsing doesn't change a link that is up or coming up.
        if !connectionState.isConnected, connectionState != .connecting {
            connectionState = .browsing
        }
        browser.onFailure = { [weak self] message in
            self?.connectionState = .error(message)
        }
        browser.start()
    }

    func stopBrowsing() {
        browser.stop()
        if case .browsing = connectionState {
            connectionState = .disconnected
        }
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
        guard let endpoint = browser.endpoint(for: mac) else { return }
        reloadPairedMacIfNeeded()
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
        reloadPairedMacIfNeeded()
        guard let record = pairedMac, let port = NWEndpoint.Port(rawValue: port) else {
            linkProblem = .notPaired
            return
        }
        connectPaired(record, endpoint: .hostPort(host: .init(host), port: port), macName: record.macName)
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
        inventoryLink = CompanionInventoryLink()
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
                self.handleConnectionState(state, connection: conn, generation: generation)
            }
        }

        conn.start(queue: queue)
        // An attempt that hangs (a reset the stack keeps retrying, a Mac that never answers) ends
        // here and goes through the same backoff as any other failure.
        Task { [weak self, helloTimeout] in
            try? await Task.sleep(for: helloTimeout)
            guard let self, self.connectionGeneration == generation else { return }
            if self.connectionState == .connecting || self.awaitingHello {
                self.linkFailed(generation: generation, reason: "The Mac didn't answer in time.")
            }
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection, generation: UUID) {
        switch state {
        case .ready:
            // Nothing is sent until the Mac's serverHello says what it made of this phone.
            guard let verified = CompanionTLS.sessionFacts(of: connection).verified else {
                linkFailed(generation: generation, reason: "The Mac's connection couldn't be verified.")
                return
            }
            session = verified
            inventoryLink.path = CompanionLinkPath(connection.currentPath)
            awaitingHello = true
            frameDecoder = CompanionFrameDecoder()
            scheduleReceive(connection: connection, generation: generation)
        case .failed(let error):
            linkFailed(generation: generation, reason: error.localizedDescription)
        case .cancelled:
            if shouldAutoReconnect {
                linkFailed(generation: generation, reason: nil)
            } else {
                tearDownLink()
            }
        case .waiting(let error):
            // A reset mid-handshake (a Mac at capacity) lands here, and Network.framework would only
            // retry on a path change: treat it as a failed attempt and use the backoff.
            linkFailed(generation: generation, reason: error.localizedDescription)
        default:
            break
        }
    }

    /// A link ended without the Mac refusing this phone: a TLS error, an early close, a deadline
    /// or full slots. A paired link retries with backoff; a pairing attempt fails for the user.
    private func linkFailed(generation: UUID, reason: String?) {
        guard connectionGeneration == generation else { return }
        connection?.cancel()
        connection = nil
        tearDownLink()
        if case .pairing? = linkMode {
            linkMode = nil
            pairing.linkEnded()
            connectionState = .disconnected
            return
        }
        connectionState = reason.map { .error("Can't reach the Mac: \($0)") } ?? .disconnected
        scheduleReconnect(generation: generation)
    }

    /// The Mac said it doesn't trust this phone's key: a definite answer, so stop retrying.
    private func refusedByMac() {
        shouldAutoReconnect = false
        connection?.cancel()
        connection = nil
        tearDownLink()
        linkProblem = .notRecognized
        connectionState = .error(MacLinkProblem.notRecognized.message)
        linkMode = nil
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

                    // A bad frame length leaves the stream out of step: end the link, which ends the Mac's
                    // inventory too. A malformed payload was consumed whole and is only skipped (#624).
                    if isComplete || error != nil || batch.errors.contains(where: \.desyncsStream) {
                        self.linkFailed(generation: generation, reason: error?.localizedDescription)
                    } else if self.connectionGeneration == generation {
                        self.scheduleReceive(connection: connection, generation: generation)
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: CompanionMessage) {
        // Any inbound message proves the link is alive, not just heartbeats.
        linkSession.recordReceived(at: Date())
        Self.logger.debug("Received companion message: \(message.logName, privacy: .public)")
        switch message {
        case .serverHello(let payload):
            handleServerHello(payload)
        case .pairChallenge(let payload):
            guard !awaitingHello, case .pairing? = linkMode, let session else { return }
            if !pairing.challenge(payload, session: session) {
                endPairingLink()
            }
        case .pairResult(let payload):
            handlePairResult(payload)
        default:
            // Everything else only on a paired, authorised link.
            guard !awaitingHello, case .paired? = linkMode else { return }
            handleLinkMessage(message)
        }
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
            inventoryLink.received(payload) { Task { await send(command: CommandPayload(action: .refreshDevices)) } }
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
            version: "1.0"
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
        guard awaitingHello, let mode = linkMode, let session else { return }
        awaitingHello = false
        switch (mode, payload.mode) {
        case (.paired, .paired):
            linkSession.recordConnected(at: Date())
            linkProblem = nil
            connectionState = .connected
            connectedMacName = pendingMacName ?? payload.macName
            lastConnectedEndpoint = pendingEndpoint
            lastConnectedMacName = pendingMacName
            startHeartbeat(generation: connectionGeneration)
            Task { await sendLocalNetworkProfile() }
        case (.paired, .pairing), (.paired, .refused):
            // The Mac doesn't trust this phone's key: removed there, or another Mac.
            refusedByMac()
        case (.pairing, _):
            guard let request = pairing.hello(payload, session: session, phoneName: UIDevice.current.name) else {
                endPairingLink()
                return
            }
            Task { await sendMessage(request) }
        }
    }

    private func handlePairResult(_ payload: PairResultPayload) {
        guard case .pairing? = linkMode, let session else { return }
        guard let record = pairing.result(payload, session: session) else {
            endPairingLink()
            return
        }
        let endpoint = pendingEndpoint
        endPairingLink()
        do {
            try macStore.save(record)
        } catch {
            pairing.fail("This iPhone couldn't save the pairing. Remove it on the Mac and pair again.")
            return
        }
        // A new pairing replaced any key a failed Forget left behind.
        defaults.removeObject(forKey: Self.pendingForgetKey)
        forgetError = nil
        pairedMac = record
        linkProblem = nil
        pairing.saved(record)
        if let endpoint {
            connectPaired(record, endpoint: endpoint, macName: record.macName)
        }
    }

    /// The user's answer on the phone. The verdict goes to the Mac either way; the Mac saves this
    /// phone only after it, and the phone saves the Mac only after the Mac accepts.
    func confirmComparison(_ match: Bool) {
        guard let verdict = pairing.confirm(match) else { return }
        Task {
            await sendMessage(verdict)
            if !match {
                endPairingLink()
            }
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
        if let cached = browser.endpoint(forMacID: invitation.macID) {
            endpoint = cached
        } else if let host = invitation.host, let port = NWEndpoint.Port(rawValue: invitation.port) {
            endpoint = .hostPort(host: .init(host), port: port)
        } else {
            pairing.fail("Couldn't find that Mac on this network.")
            return
        }
        let attempt = PhonePairingAttempt(
            kind: .qr, secret: invitation.secret, identity: CompanionIdentity(),
            host: invitation.host, port: invitation.port, macName: invitation.macName
        )
        startPairing(attempt, endpoint: endpoint, acceptsMac: { [pin = invitation.macPin] in $0 == pin })
    }

    /// Pairs with `mac` using the code typed from its screen. The Mac's key isn't known in
    /// advance, so the Mac must prove the same code before anything is trusted.
    func pair(code: CompanionPairingCode, with mac: DiscoveredMac) {
        guard let endpoint = browser.endpoint(for: mac) else {
            pairing.fail("Couldn't find that Mac on this network.")
            return
        }
        guard mac.isCurrent else {
            pairing.fail(MacLinkProblem.macNeedsUpdate.message)
            return
        }
        let attempt = PhonePairingAttempt(
            kind: .code, secret: code.secret, identity: CompanionIdentity(),
            host: nil, port: CompanionLink.defaultPort, macName: mac.name
        )
        startPairing(attempt, endpoint: endpoint, acceptsMac: { _ in true })
    }

    /// Opens a pairing link with the attempt's fresh identity: nothing ties it to an earlier one.
    private func startPairing(_ attempt: PhonePairingAttempt, endpoint: NWEndpoint, acceptsMac: @escaping @Sendable (Data) -> Bool) {
        guard let parameters = CompanionTLS.parameters(identity: attempt.identity, acceptsPeer: acceptsMac) else {
            pairing.fail("Couldn't create this iPhone's key.")
            return
        }
        disconnect()
        linkProblem = nil
        connectionState = .connecting
        pendingEndpoint = endpoint
        pendingMacName = attempt.macName
        pairing.begin(attempt)
        linkMode = .pairing
        setupConnection(NWConnection(to: endpoint, using: parameters), macName: attempt.macName)
    }

    func resetPairingState() {
        switch pairing.state {
        case .connecting, .comparing, .waitingForMac:
            endPairingLink()
        case .idle, .paired, .failed:
            break
        }
        pairing.reset()
    }

    /// Forgets the paired Mac: tells it (if connected) to drop this phone, then deletes the key.
    /// If the delete fails, the key is marked and never loaded or used, and deleting is retried.
    func forgetMac() async {
        if connectionState.isConnected {
            await sendMessage(.unpair(UnpairPayload()))
        }
        disconnect()
        pairedMac = nil
        linkProblem = nil
        pairing.reset()
        do {
            try macStore.forget()
            defaults.removeObject(forKey: Self.pendingForgetKey)
            forgetError = nil
        } catch {
            Self.logger.error("Couldn't delete the paired Mac: \(String(describing: error), privacy: .public)")
            defaults.set(true, forKey: Self.pendingForgetKey)
            forgetError = "This iPhone couldn't delete the Mac's key. It won't be used, and NetMonitor will try again."
        }
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
    /// link the Mac has greeted. A pairing link carries only the pairing request and the verdict.
    @discardableResult
    private func sendMessage(_ message: CompanionMessage) async -> Bool {
        guard let conn = connection, !awaitingHello, let linkMode else { return false }
        if case .pairing = linkMode {
            switch message {
            case .pairRequest, .pairResult: break
            default: return false
            }
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
        browser.endpoint(for: mac)
    }

    /// A Mac at `endpoint`, as if Bonjour had found it.
    func addDiscoveredMacForTesting(_ mac: DiscoveredMac, endpoint: NWEndpoint) {
        browser.add(mac, endpoint: endpoint)
    }
}
