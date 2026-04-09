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

    private(set) var isRunning = false
    private(set) var connectedClients: [UUID: NWConnection] = [:]
    private var clientInfos: [UUID: ConnectedClientInfo] = [:]

    /// Returns info about all currently connected companion clients.
    func getConnectedClientInfos() -> [ConnectedClientInfo] {
        Array(clientInfos.values)
    }

    private var listener: NWListener?
    private var messageHandler: ((CompanionMessage, UUID) async -> CompanionMessage?)?

    /// Per-client receive buffers for length-prefixed frame reassembly
    private var receiveBuffers: [UUID: Data] = [:]

    /// Start the Bonjour service
    func start(messageHandler: @escaping (CompanionMessage, UUID) async -> CompanionMessage?) throws {
        guard !isRunning else { return }

        self.messageHandler = messageHandler

        // Create listener — plain TCP, no custom framer
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        // swiftlint:disable:next force_unwrapping
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

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

        listener?.start(queue: .global())
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
        receiveBuffers.removeAll()
        clientInfos.removeAll()

        isRunning = false
    }

    // periphery:ignore
    /// Send a message to all connected clients
    func broadcast(_ message: CompanionMessage) async {
        guard let data = try? JSONEncoder().encode(message) else { return }

        for (id, connection) in connectedClients {
            await send(data: data, to: connection, clientID: id)
        }
    }

    /// Send a message to a specific client
    func send(_ message: CompanionMessage, to clientID: UUID) async {
        guard let connection = connectedClients[clientID],
              let data = try? JSONEncoder().encode(message) else { return }

        await send(data: data, to: connection, clientID: clientID)
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
        receiveBuffers[clientID] = Data()
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

        connection.start(queue: .global())
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
            receiveBuffers.removeValue(forKey: clientID)
            clientInfos.removeValue(forKey: clientID)
        case .cancelled:
            Logger.companion.info("Client \(clientID) disconnected")
            connectedClients.removeValue(forKey: clientID)
            receiveBuffers.removeValue(forKey: clientID)
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

    /// Append received data to the client's buffer and process complete frames.
    /// Wire format: 4-byte big-endian length prefix + JSON payload.
    private func appendAndProcess(_ data: Data, clientID: UUID) async {
        receiveBuffers[clientID, default: Data()].append(data)

        while var buffer = receiveBuffers[clientID], buffer.count >= 4 {
            // Read 4 bytes explicitly to avoid UnsafeRawBufferPointer slice issues
            let b0 = buffer[buffer.startIndex]
            let b1 = buffer[buffer.startIndex + 1]
            let b2 = buffer[buffer.startIndex + 2]
            let b3 = buffer[buffer.startIndex + 3]
            let length = UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)

            // Sanity check — reject absurdly large frames (max 10 MB)
            guard length > 0, length <= 10_000_000 else {
                Logger.companion.error("Invalid frame length \(length), clearing buffer for \(clientID)")
                receiveBuffers[clientID] = Data()
                break
            }

            let totalFrameSize = 4 + Int(length)

            guard buffer.count >= totalFrameSize else {
                break  // Need more data
            }

            let start = buffer.startIndex
            let jsonData = buffer.subdata(in: (start + 4)..<(start + totalFrameSize))
            buffer.removeFirst(totalFrameSize)
            receiveBuffers[clientID] = buffer

            do {
                let message = try CompanionMessage.decode(from: jsonData)
                Logger.companion.debug("Received \(String(describing: message)) from \(clientID)")

                if let response = await messageHandler?(message, clientID) {
                    await send(response, to: clientID)
                }
            } catch {
                Logger.companion.error("Failed to decode message: \(error, privacy: .public)")
                await send(
                    .error(ErrorPayload(
                        code: "DECODE_ERROR",
                        message: "Failed to decode message: \(error.localizedDescription)"
                    )),
                    to: clientID
                )
            }
        }
    }

    /// Send length-prefixed JSON data to a client.
    nonisolated private func send(data: Data, to connection: NWConnection, clientID: UUID) async {
        let capturedClientID = clientID

        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                Logger.companion.error("Send error to \(capturedClientID): \(error, privacy: .public)")
            }
        })
    }
}
