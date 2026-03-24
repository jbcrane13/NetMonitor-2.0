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

/// Bonjour service for companion app communication
actor CompanionService {

    let port: UInt16 = 8849
    let serviceType = "_netmon._tcp"
    let serviceName = "NetMonitor"

    private(set) var isRunning = false
    private(set) var connectedClients: [UUID: NWConnection] = [:]

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

    /// Stop the service
    // periphery:ignore
    func stop() {
        listener?.cancel()
        listener = nil

        for (_, connection) in connectedClients {
            connection.cancel()
        }
        connectedClients.removeAll()
        receiveBuffers.removeAll()

        isRunning = false
    }

    /// Send a message to all connected clients
    // periphery:ignore
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
        case .cancelled:
            Logger.companion.info("Client \(clientID) disconnected")
            connectedClients.removeValue(forKey: clientID)
            receiveBuffers.removeValue(forKey: clientID)
        default:
            break
        }
    }

    private nonisolated func receiveMessage(from connection: NWConnection, clientID: UUID) {
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
            let length = buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            let totalFrameSize = 4 + Int(length)

            guard buffer.count >= totalFrameSize else {
                break  // Need more data
            }

            let jsonData = buffer.subdata(in: 4..<totalFrameSize)
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
    private nonisolated func send(data: Data, to connection: NWConnection, clientID: UUID) async {
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
