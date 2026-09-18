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

/// Metadata for a connected companion client
struct ConnectedClientInfo {
    let id: UUID
    let endpoint: String
    let connectedSince: Date
}

/// Bonjour service for companion app communication
actor CompanionService {

    let port: UInt16 = 8849
    let serviceType = "_netmon._tcp"
    let serviceName = "NetMonitor"

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

    private(set) var isRunning = false
    private(set) var connectedClients: [UUID: NWConnection] = [:]
    private var clientInfos: [UUID: ConnectedClientInfo] = [:]

    /// Returns info about all currently connected companion clients.
    func getConnectedClientInfos() -> [ConnectedClientInfo] {
        Array(clientInfos.values)
    }

    private var listener: NWListener?
    private var messageHandler: ((CompanionMessage, UUID) async -> CompanionMessage?)?

    /// Per-client frame decoders for length-prefixed reassembly.
    /// Framing itself (4-byte big-endian length prefix + JSON payload, 1 MiB cap)
    /// is owned by `CompanionFrameDecoder` in NetMonitorCore.
    private var decoders: [UUID: CompanionFrameDecoder] = [:]

    /// Start the Bonjour service
    func start(messageHandler: @escaping (CompanionMessage, UUID) async -> CompanionMessage?) throws {
        guard !isRunning else { return }

        // Create listener — plain TCP, no custom framer.
        // Construct *before* storing `messageHandler` so a thrown error doesn't
        // leak the captured closure into the actor.
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        // swiftlint:disable:next force_unwrapping
        let newListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        self.messageHandler = messageHandler
        listener = newListener

        // Advertise via Bonjour
        let txtRecord = NWTXTRecord()
        listener?.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: "local.",
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerState(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: listenerQueue)
        isRunning = true
    }

    // periphery:ignore
    /// Stop the service
    func stop() {
        listener?.cancel()
        listener = nil

        for (_, connection) in connectedClients {
            connection.cancel()
        }
        connectedClients.removeAll()
        decoders.removeAll()
        clientInfos.removeAll()

        isRunning = false
    }

    // periphery:ignore
    /// Send a message to all connected clients
    func broadcast(_ message: CompanionMessage) async {
        guard let framedData = try? message.encodeLengthPrefixed() else { return }

        for (id, connection) in connectedClients {
            await send(data: framedData, to: connection, clientID: id)
        }
    }

    /// Send a message to a specific client
    func send(_ message: CompanionMessage, to clientID: UUID) async {
        guard let connection = connectedClients[clientID],
              let framedData = try? message.encodeLengthPrefixed() else { return }

        await send(data: framedData, to: connection, clientID: clientID)
    }

    // MARK: - Private Methods

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Logger.companion.info("Listening on port \(self.port)")
        case .failed(let error):
            Logger.companion.error("Failed to start: \(error, privacy: .public)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let clientID = UUID()
        connectedClients[clientID] = connection
        decoders[clientID] = CompanionFrameDecoder()
        clientInfos[clientID] = ConnectedClientInfo(
            id: clientID,
            endpoint: "\(connection.endpoint)",
            connectedSince: Date()
        )

        Logger.companion.info("New connection from client \(clientID)")

        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionState(state, clientID: clientID)
            }
        }

        connection.start(queue: connectionQueue)
        receiveMessage(from: connection, clientID: clientID)
    }

    private func handleConnectionState(_ state: NWConnection.State, clientID: UUID) {
        switch state {
        case .ready:
            Logger.companion.info("Client \(clientID) connected")
            // Send initial heartbeat
            Task {
                await send(
                    .heartbeat(HeartbeatPayload()),
                    to: clientID
                )
            }
        case .failed(let error):
            Logger.companion.error("Client \(clientID) failed: \(error, privacy: .public)")
            connectedClients.removeValue(forKey: clientID)
            decoders.removeValue(forKey: clientID)
            clientInfos.removeValue(forKey: clientID)
        case .cancelled:
            Logger.companion.info("Client \(clientID) disconnected")
            connectedClients.removeValue(forKey: clientID)
            decoders.removeValue(forKey: clientID)
            clientInfos.removeValue(forKey: clientID)
        default:
            break
        }
    }

    nonisolated private func receiveMessage(from connection: NWConnection, clientID: UUID) {
        let capturedClientID = clientID
        let capturedConnection = connection

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { [weak self] in
                    await self?.appendAndProcess(data, clientID: capturedClientID)
                }
            }

            if let error = error {
                Logger.companion.error("Receive error: \(error, privacy: .public)")
                return
            }

            if !isComplete {
                Task { [weak self] in
                    self?.receiveMessage(from: capturedConnection, clientID: capturedClientID)
                }
            }
        }
    }

    /// Returns the client's frame decoder, creating one if it doesn't exist yet
    /// (normally it's created on accept, in `handleNewConnection`).
    private func decoder(for clientID: UUID) -> CompanionFrameDecoder {
        if let existing = decoders[clientID] {
            return existing
        }
        let created = CompanionFrameDecoder()
        decoders[clientID] = created
        return created
    }

    private static func decodeErrorMessage() -> CompanionMessage {
        .error(ErrorPayload(code: "DECODE_ERROR", message: "Failed to decode message: malformed payload"))
    }

    /// Feed received bytes to the client's `CompanionFrameDecoder` and dispatch
    /// any complete messages it yields. Framing (4-byte big-endian length prefix
    /// + JSON payload, capped at `CompanionFrameDecoder.defaultMaximumFrameSize`)
    /// is owned by NetMonitorCore; this actor performs no length arithmetic.
    private func appendAndProcess(_ data: Data, clientID: UUID) async {
        let batch = await decoder(for: clientID).append(data)

        for message in batch.messages {
            Logger.companion.debug("Received \(String(describing: message)) from \(clientID)")

            if let response = await messageHandler?(message, clientID) {
                await send(response, to: clientID)
            }
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

    /// Send already length-prefixed data to a client's connection.
    nonisolated private func send(data: Data, to connection: NWConnection, clientID: UUID) async {
        let capturedClientID = clientID

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                Logger.companion.error("Send error to \(capturedClientID): \(error, privacy: .public)")
            }
        })
    }

    // MARK: - Testing Support

    /// Feed raw bytes into a client's frame decoder for testing, mirroring the
    /// iOS companion service's testing seam. Returns decoded messages in the
    /// order the decoder produced them, with a synthesized `DECODE_ERROR`
    /// message appended for each malformed payload — matching what
    /// `appendAndProcess` sends over the wire. `.invalidLength` frames yield no
    /// message, matching production behaviour (the decoder has already cleared
    /// its buffer).
    func processIncomingDataForTesting(_ data: Data, clientID: UUID) async -> [CompanionMessage] {
        let batch = await decoder(for: clientID).append(data)

        var results = batch.messages
        for error in batch.errors where error == .malformedPayload {
            results.append(Self.decodeErrorMessage())
        }
        return results
    }
}
