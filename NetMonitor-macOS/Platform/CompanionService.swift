//
//  CompanionService.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import Foundation
import Network
import NetMonitorCore
import os

/// Metadata for a connected, paired companion phone
struct ConnectedClientInfo {
    let id: UUID
    let endpoint: String
    let connectedSince: Date
    /// The paired phone's pin.
    let phonePin: Data
}

/// What the pairing sheet hears from the service (#590).
enum CompanionPairingEvent: Sendable, Equatable {
    /// A phone proved the one-time secret; the user must compare `code` and confirm.
    case awaitingConfirmation(link: UUID, phoneName: String, code: String)
    case paired(PairedPhone)
    case failed(String)
    /// A phone that isn't paired tried to connect.
    case refusedAttempt(Date)
}

/// What the pairing sheet shows: the QR invitation, the typed code, and when both expire.
struct CompanionPairingOffer: Sendable {
    let invitation: CompanionPairingInvitation
    let code: CompanionPairingCode
    let expiresAt: Date
}

/// The Mac end of the companion link (#590): a TLS 1.3 listener with mutually pinned identities,
/// advertised over Bonjour. Each connection gets a role when its session is verified, and every
/// frame is checked against the role and the live trust gate before it is handled.
actor CompanionService {

    let port: UInt16
    let serviceType = "_netmon._tcp"
    let serviceName = "NetMonitor"

    // MARK: Limits (#590)

    struct Limits: Sendable {
        /// Links of any kind.
        var maximumLinks = 16
        /// Links not yet paired: in the handshake, or pairing.
        var maximumPreAuthLinks = 4
        /// From accept to a paired link.
        var authDeadline: Duration = .seconds(10)
        /// From accept to the end of pairing, which waits for the user's confirmation.
        var pairingDeadline: Duration = .seconds(120)
    }

    /// Largest frame accepted on a link that isn't paired, before JSON decoding.
    static let pairingFrameLimit = 4096
    private let limits: Limits
    private let advertises: Bool

    /// Dedicated callback queue for NWListener.
    /// `NWListener.start(queue:)` requires a `DispatchQueue` (Apple API);
    /// using a named queue instead of `.global()` keeps thread dumps
    /// attributable and pins callbacks to a known QoS.
    let listenerQueue = DispatchQueue(
        label: "com.netmonitor.companion.listener",
        qos: .userInitiated
    )

    /// Shared callback queue for accepted `NWConnection`s.
    /// Concurrent so per-client receive/send callbacks don't serialize behind
    /// each other; named so thread attribution survives into client work.
    let connectionQueue = DispatchQueue(
        label: "com.netmonitor.companion.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private struct Link {
        let connection: NWConnection
        let acceptedAt: Date
        var role: CompanionLinkRole?
        var session: CompanionVerifiedSession?
        var decoder: CompanionFrameDecoder?
        var pendingPairing: PendingPairing?
    }

    private struct PendingPairing {
        let step: CompanionPairingStep
        let phoneName: String
    }

    private(set) var isRunning = false
    private var links: [UUID: Link] = [:]
    private var listener: NWListener?
    /// Bumped on every start and stop; callbacks from an older listener are dropped.
    private var listenerGeneration = 0
    private let credentials: CompanionCredentials?
    private var messageHandler: ((CompanionMessage, UUID) async -> CompanionMessage?)?
    /// The heartbeat sent when a phone's link is authorised, carrying this Mac's capabilities (#457).
    private var heartbeat: @Sendable () async -> HeartbeatPayload = { HeartbeatPayload() }
    private var eventHandler: (@Sendable (CompanionPairingEvent) -> Void)?
    /// Per-client decoders for the `processIncomingDataForTesting` seam only.
    private var testDecoders: [UUID: CompanionFrameDecoder] = [:]

    /// `credentials` nil makes a service that can't start, for tests of its static surface.
    /// Tests pass port 0 for any free port, `advertises: false`, and short `limits`.
    init(credentials: CompanionCredentials? = nil, port: UInt16 = 8849, limits: Limits = Limits(), advertises: Bool = true) {
        self.credentials = credentials
        self.port = port
        self.limits = limits
        self.advertises = advertises
    }

    /// The port the listener is bound to, once it is ready.
    var listeningPort: UInt16? {
        listener?.port?.rawValue
    }

    /// Paired phones with an authorised link.
    var connectedClients: [UUID: NWConnection] {
        authorizedLinks().reduce(into: [:]) { $0[$1.id] = $1.link.connection }
    }

    /// Returns info about the paired phones connected now.
    func getConnectedClientInfos() -> [ConnectedClientInfo] {
        authorizedLinks().compactMap { id, link in
            guard case .paired(let pin, _)? = link.role else { return nil }
            return ConnectedClientInfo(id: id, endpoint: "\(link.connection.endpoint)", connectedSince: link.acceptedAt, phonePin: pin)
        }
    }

    func setEventHandler(_ handler: @escaping @Sendable (CompanionPairingEvent) -> Void) {
        eventHandler = handler
    }

    // MARK: - Lifecycle

    /// Start the TLS listener and advertise it.
    func start(
        heartbeat: @escaping @Sendable () async -> HeartbeatPayload = { HeartbeatPayload() },
        messageHandler: @escaping (CompanionMessage, UUID) async -> CompanionMessage?
    ) throws {
        guard !isRunning else { return }
        guard let credentials,
              let listenPort = NWEndpoint.Port(rawValue: port),
              let parameters = CompanionTLS.parameters(identity: credentials.identity, acceptsPeer: { [gate = credentials.gate] in
                  gate.acceptsAtHandshake($0)
              }) else {
            throw CompanionServiceError.noIdentity
        }
        // Construct *before* storing `messageHandler` so a thrown error doesn't
        // leak the captured closure into the actor.
        let newListener = try NWListener(using: parameters, on: listenPort)

        self.messageHandler = messageHandler
        self.heartbeat = heartbeat
        listenerGeneration += 1
        let generation = listenerGeneration
        listener = newListener

        // Advertise via Bonjour. `pv` tells a newer phone this Mac speaks v2; it is a hint for
        // the phone's screen only, never a reason to drop security.
        if advertises {
            newListener.service = NWListener.Service(
                name: serviceName,
                type: serviceType,
                domain: "local.",
                txtRecord: Self.txtRecord(macID: credentials.macID)
            )
        }
        newListener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerState(state, generation: generation)
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }
        newListener.start(queue: listenerQueue)
        isRunning = true
    }

    static func txtRecord(macID: UUID) -> NWTXTRecord {
        var record = NWTXTRecord()
        record["pv"] = String(CompanionMessage.currentProtocolVersion)
        record["mac"] = macID.uuidString
        return record
    }

    // periphery:ignore
    /// Stop the service. Safe to call before `start()` or after a failed start.
    func stop() {
        listenerGeneration += 1
        listener?.cancel()
        listener = nil
        messageHandler = nil
        for id in Array(links.keys) {
            close(id)
        }
        isRunning = false
    }

    // MARK: - Sending

    /// Send a message to every authorised phone.
    func broadcast(_ message: CompanionMessage) async {
        guard let framedData = try? message.encodeLengthPrefixed() else { return }
        for (id, link) in authorizedLinks() {
            Self.send(data: framedData, to: link.connection, clientID: id)
        }
    }

    /// Send a message to one phone, if its link is still authorised.
    func send(_ message: CompanionMessage, to clientID: UUID) async {
        guard let link = links[clientID], let role = link.role,
              credentials?.gate.isAuthorized(role, link: clientID) == true,
              let framedData = try? message.encodeLengthPrefixed() else { return }
        Self.send(data: framedData, to: link.connection, clientID: clientID)
    }
}

// MARK: - Pairing (#590)

extension CompanionService {
    /// Opens a pairing window, shutting any earlier one and its connections.
    func openPairingWindow() -> CompanionPairingOffer? {
        guard let credentials else { return nil }
        closePairingLinks()
        let window = credentials.gate.openWindow()
        let invitation = CompanionPairingInvitation(
            macID: credentials.macID,
            macName: credentials.macName,
            macPin: credentials.identity.pin,
            secret: window.secret(for: .qr),
            host: credentials.host,
            port: port
        )
        let remaining = window.deadline - ProcessInfo.processInfo.systemUptime
        return CompanionPairingOffer(invitation: invitation, code: window.code, expiresAt: Date().addingTimeInterval(remaining))
    }

    /// Closes the window and every pairing connection, including one awaiting confirmation.
    func closePairingWindow() {
        credentials?.gate.closeWindow()
        closePairingLinks()
    }

    /// The user's answer to `awaitingConfirmation`. Pairing succeeds only if the Keychain saves
    /// the phone; otherwise nothing is pinned on either side.
    func confirmPairing(link id: UUID, accepted: Bool) {
        guard let credentials, let link = links[id], let role = link.role, let pending = link.pendingPairing,
              credentials.gate.isAuthorized(role, link: id) else {
            emit(.failed("The iPhone disconnected before pairing finished."))
            return
        }
        guard accepted else {
            finishPairing(id, result: PairResultPayload(accepted: false, reason: "Cancelled on the Mac."))
            return
        }
        let phone = PairedPhone(pin: pending.step.phonePin, name: pending.phoneName, pairedAt: Date())
        do {
            try credentials.phones.add(phone)
        } catch {
            Logger.companion.error("Couldn't save a paired phone: \(String(describing: error), privacy: .public)")
            finishPairing(id, result: PairResultPayload(accepted: false, reason: "The Mac couldn't save the pairing."))
            emit(.failed("This Mac couldn't save the pairing to its Keychain."))
            return
        }
        credentials.gate.trust(phone.pin)
        credentials.gate.closeWindow()
        finishPairing(id, result: PairResultPayload(accepted: true))
        emit(.paired(phone))
    }

    func pairedPhones() -> [PairedPhone] {
        credentials?.pairedPhones() ?? []
    }

    /// Removes a phone: denied at once, its links closed, then its Keychain item deleted.
    /// False when the delete failed; the phone stays denied anyway.
    @discardableResult
    func revoke(_ pin: Data) -> Bool {
        guard let credentials else { return false }
        credentials.gate.revoke(pin)
        for (id, link) in links {
            if case .paired(let linkPin, _)? = link.role, linkPin == pin {
                close(id)
            }
        }
        return credentials.revoke(pin)
    }
}

// MARK: - Listener and connections

extension CompanionService {
    private func handleListenerState(_ state: NWListener.State, generation: Int) {
        guard generation == listenerGeneration else { return }
        switch state {
        case .ready:
            Logger.companion.info("Listening on port \(self.port)")
        case .waiting(let error):
            // Port may be in use, or network path temporarily unavailable.
            // NWListener will retry; surface for diagnostics rather than swallowing.
            Logger.companion.warning("Listener waiting: \(error, privacy: .public)")
        case .failed(let error):
            Logger.companion.error("Failed to start: \(error, privacy: .public)")
            listener?.cancel()
            listener = nil
            messageHandler = nil
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let preAuth = links.values.filter { !Self.isPaired($0.role) }.count
        guard links.count < limits.maximumLinks, preAuth < limits.maximumPreAuthLinks else {
            Logger.companion.warning("Refused a connection: at capacity")
            connection.cancel()
            return
        }
        let clientID = UUID()
        links[clientID] = Link(connection: connection, acceptedAt: Date())
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionState(state, clientID: clientID)
            }
        }
        connection.start(queue: connectionQueue)
        let limits = limits
        Task { [weak self] in
            try? await Task.sleep(for: limits.authDeadline)
            await self?.enforceDeadline(clientID, pairingLimit: false)
        }
        Task { [weak self] in
            try? await Task.sleep(for: limits.pairingDeadline)
            await self?.enforceDeadline(clientID, pairingLimit: true)
        }
    }

    /// Closes a link that isn't paired by `authDeadline`, or still pairing at `pairingDeadline`.
    private func enforceDeadline(_ id: UUID, pairingLimit: Bool) {
        guard let link = links[id] else { return }
        switch link.role {
        case .paired?:
            return
        case .pairing?:
            if pairingLimit {
                close(id)
            }
        case nil:
            close(id)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, clientID: UUID) {
        switch state {
        case .ready:
            authorize(clientID)
        case .waiting(let error):
            Logger.companion.warning("Client \(clientID) waiting: \(error, privacy: .public)")
        case .failed(let error):
            if let link = links[clientID], link.role == nil {
                // The handshake failed: most often a phone this Mac doesn't trust.
                emit(.refusedAttempt(Date()))
            }
            Logger.companion.info("Client \(clientID) failed: \(error, privacy: .public)")
            close(clientID)
        case .cancelled:
            links.removeValue(forKey: clientID)
        default:
            break
        }
    }

    /// The `.ready` gate: verify the session, give the link its role, and greet the phone. Until
    /// this succeeds nothing is sent and nothing is read.
    private func authorize(_ id: UUID) {
        guard let credentials, var link = links[id], link.role == nil else { return }
        guard let session = CompanionTLS.sessionFacts(of: link.connection).verified,
              let role = credentials.gate.classify(session.peerPin) else {
            close(id)
            return
        }
        link.role = role
        link.session = session
        let isPaired = Self.isPaired(role)
        link.decoder = CompanionFrameDecoder(
            maximumFrameSize: isPaired ? CompanionFrameDecoder.defaultMaximumFrameSize : Self.pairingFrameLimit
        )
        links[id] = link
        Logger.companion.info("Client \(id) authorised as \(isPaired ? "paired" : "pairing", privacy: .public)")
        let hello = CompanionMessage.serverHello(ServerHelloPayload(
            macID: credentials.macID,
            macName: credentials.macName,
            mode: isPaired ? .paired : .pairing
        ))
        sendRaw(hello, to: id)
        if isPaired {
            Task { [heartbeat] in
                await self.send(.heartbeat(heartbeat()), to: id)
            }
        }
        receive(on: link.connection, clientID: id)
    }

    /// One receive at a time per link: the next is asked for only after this chunk is handled,
    /// so a link never queues more than one chunk.
    nonisolated private func receive(on connection: NWConnection, clientID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    await self.appendAndProcess(data, clientID: clientID)
                }
                if let error {
                    Logger.companion.error("Receive error: \(error, privacy: .public)")
                    await self.close(clientID)
                } else if isComplete {
                    await self.close(clientID)
                } else if await self.isOpen(clientID) {
                    self.receive(on: connection, clientID: clientID)
                }
            }
        }
    }

    private func isOpen(_ id: UUID) -> Bool {
        links[id] != nil
    }

    private static func decodeErrorMessage() -> CompanionMessage {
        .error(ErrorPayload(code: "DECODE_ERROR", message: "Failed to decode message: malformed payload"))
    }

    /// Feed received bytes to the link's decoder and handle each message its role allows. A
    /// closed or unknown link is never recreated by a late receive.
    private func appendAndProcess(_ data: Data, clientID: UUID) async {
        guard let decoder = links[clientID]?.decoder else { return }
        let batch = await decoder.append(data)

        for message in batch.messages {
            guard let credentials, let link = links[clientID], let role = link.role,
                  credentials.gate.isAuthorized(role, link: clientID) else {
                close(clientID)
                return
            }
            // The type only: payloads carry addresses, hostnames and insight prompts.
            Logger.companion.debug("Received \(message.logName, privacy: .public) from \(clientID)")
            switch CompanionLinkAuthorizer.decide(message, role: role) {
            case .refuse:
                close(clientID)
                return
            case .ignore:
                continue
            case .unpair:
                if case .paired(let pin, _) = role {
                    revoke(pin)
                }
                return
            case .pairRequest:
                if case .pairRequest(let payload) = message {
                    beginPairing(clientID, request: payload)
                }
            case .dispatch:
                await dispatch(message, from: clientID)
            }
        }

        guard !batch.errors.isEmpty, let role = links[clientID]?.role else { return }
        guard Self.isPaired(role) else {
            close(clientID)
            return
        }
        for error in batch.errors {
            switch error {
            case .malformedPayload:
                Logger.companion.error("Failed to decode message from \(clientID): malformed payload")
                await send(Self.decodeErrorMessage(), to: clientID)
            case .invalidLength(let length):
                Logger.companion.error("Invalid frame length \(length) from \(clientID), buffer cleared")
            }
        }
    }

    /// Hands `message` to the handler. A reply goes out only if the link is still authorised
    /// when it is ready: `send(_:to:)` checks again.
    private func dispatch(_ message: CompanionMessage, from clientID: UUID) async {
        let handler = messageHandler
        // A model request can take 20 s: answer it on its own, so the frames behind it, such
        // as heartbeats, are handled meanwhile (#457).
        if Self.answersOffBatch(message) {
            Task {
                if let response = await handler?(message, clientID) {
                    await send(response, to: clientID)
                }
            }
            return
        }
        if let response = await handler?(message, clientID) {
            await send(response, to: clientID)
        }
    }

    private func beginPairing(_ id: UUID, request: PairRequestPayload) {
        guard let credentials, var link = links[id], let role = link.role, let session = link.session,
              link.pendingPairing == nil,
              let step = credentials.gate.beginPairing(
                  link: id, role: role, request: request, session: session, macPin: credentials.identity.pin
              ) else {
            close(id)
            return
        }
        // The window burned: every other connection of it goes now.
        for (otherID, other) in links where otherID != id && other.role == role {
            close(otherID)
        }
        let name = Self.displayName(request.phoneName)
        link.pendingPairing = PendingPairing(step: step, phoneName: name)
        links[id] = link
        sendRaw(.pairChallenge(PairChallengePayload(proof: step.challenge)), to: id)
        emit(.awaitingConfirmation(link: id, phoneName: name, code: step.comparisonCode))
    }

    private func finishPairing(_ id: UUID, result: PairResultPayload) {
        guard let link = links[id], let data = try? CompanionMessage.pairResult(result).encodeLengthPrefixed() else {
            close(id)
            return
        }
        links[id]?.pendingPairing = nil
        link.connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            Task { await self?.close(id) }
        })
    }

    private func closePairingLinks() {
        for (id, link) in links {
            if case .pairing? = link.role {
                close(id)
            }
        }
    }

    private func close(_ id: UUID) {
        guard let link = links.removeValue(forKey: id) else { return }
        link.connection.cancel()
    }

    private func authorizedLinks() -> [(id: UUID, link: Link)] {
        guard let gate = credentials?.gate else { return [] }
        return links.compactMap { id, link in
            guard let role = link.role, Self.isPaired(role), gate.isAuthorized(role, link: id) else { return nil }
            return (id, link)
        }
    }

    /// Sends one of the session's own frames (hello, challenge) without the paired-only check.
    private func sendRaw(_ message: CompanionMessage, to id: UUID) {
        guard let link = links[id], let data = try? message.encodeLengthPrefixed() else { return }
        Self.send(data: data, to: link.connection, clientID: id)
    }

    nonisolated private static func send(data: Data, to connection: NWConnection, clientID: UUID) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Logger.companion.error("Send error to \(clientID): \(error, privacy: .public)")
            }
        })
    }

    private func emit(_ event: CompanionPairingEvent) {
        eventHandler?(event)
    }

    private static func isPaired(_ role: CompanionLinkRole?) -> Bool {
        if case .paired? = role {
            return true
        }
        return false
    }

    /// The phone's name for display: printable, at most 40 characters.
    static func displayName(_ raw: String) -> String {
        let printable = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "iPhone" : String(name.prefix(40))
    }

    /// Whether `message` is handled on its own instead of in its batch's order.
    static func answersOffBatch(_ message: CompanionMessage) -> Bool {
        if case .insightRequest = message {
            return true
        }
        return false
    }
}

// MARK: - Testing Support

extension CompanionService {
    /// Feed raw bytes into a test-only frame decoder. Returns decoded messages in the order the
    /// decoder produced them, with a synthesized `DECODE_ERROR` message appended for each
    /// malformed payload. `.invalidLength` frames yield no message (the decoder has already
    /// cleared its buffer). Nothing is dispatched: this exercises framing only.
    func processIncomingDataForTesting(_ data: Data, clientID: UUID) async -> [CompanionMessage] {
        let decoder = testDecoders[clientID] ?? CompanionFrameDecoder()
        testDecoders[clientID] = decoder
        let batch = await decoder.append(data)

        var results = batch.messages
        for error in batch.errors where error == .malformedPayload {
            results.append(Self.decodeErrorMessage())
        }
        return results
    }
}

enum CompanionServiceError: Error {
    /// The companion identity couldn't be loaded, so the service doesn't start.
    case noIdentity
}
