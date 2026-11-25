import Foundation
import NetMonitorCore
import Network
import Synchronization

/// A Mac end of the companion link for UI tests and unit tests (#590), on 127.0.0.1 only. It
/// uses the real `CompanionTLS` and `CompanionTrustGate`, opens a pairing window with a known
/// code, and confirms (or refuses) pairing by itself after a pause, standing in for the user's
/// click on the Mac.
final class FakeCompanionMac: Sendable {
    enum Confirmation: Sendable {
        case accept
        case reject
    }

    let identity = CompanionIdentity()
    let macID = UUID()
    let name: String
    let window: CompanionPairingWindow
    let gate: CompanionTrustGate
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.netmonitor.fakemac")
    private let confirmation: Confirmation
    private let confirmDelay: Duration
    private let state = Mutex(State())

    private struct State {
        var connections: [NWConnection] = []
        var received: [String] = []
        var connectionCount = 0
    }

    init(
        name: String = "Test Mac",
        port: UInt16 = 0,
        code: CompanionPairingCode = .random(),
        confirmation: Confirmation = .accept,
        confirmDelay: Duration = .milliseconds(200),
        pairedPins: [Data] = []
    ) throws {
        self.name = name
        self.confirmation = confirmation
        self.confirmDelay = confirmDelay
        gate = CompanionTrustGate(paired: pairedPins)
        window = gate.openWindow(code: code)
        guard let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: { [gate] in gate.acceptsAtHandshake($0) }),
              let listenPort = NWEndpoint.Port(rawValue: port) else { throw FakeMacError.noIdentity }
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: listenPort)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    enum FakeMacError: Error { case noIdentity, notReady }

    /// Starts listening; returns the bound port.
    func start() async throws -> UInt16 {
        let ready = Mutex(false)
        listener.stateUpdateHandler = {
            if case .ready = $0 {
                ready.withLock { $0 = true }
            }
        }
        listener.start(queue: queue)
        for _ in 0..<250 {
            if ready.withLock({ $0 }), let port = listener.port?.rawValue {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw FakeMacError.notReady
    }

    func stop() {
        listener.cancel()
        state.withLock { $0.connections.forEach { $0.cancel() } }
    }

    /// The QR this Mac would show.
    func invitation(port: UInt16) -> CompanionPairingInvitation {
        CompanionPairingInvitation(
            macID: macID, macName: name, macPin: identity.pin, secret: window.secret(for: .qr), host: "127.0.0.1", port: port
        )
    }

    /// Message types received on authorised links, in order.
    var received: [String] { state.withLock { $0.received } }
    /// TCP connections accepted so far.
    var connectionCount: Int { state.withLock { $0.connectionCount } }

    // MARK: - Links

    private func accept(_ connection: NWConnection) {
        state.withLock {
            $0.connections.append(connection)
            $0.connectionCount += 1
        }
        let decoder = CompanionFrameDecoder()
        let link = UUID()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            guard let session = CompanionTLS.sessionFacts(of: connection).verified,
                  let role = gate.classify(session.peerPin) else {
                connection.cancel()
                return
            }
            let mode: ServerHelloPayload.Mode = if case .paired = role {
                .paired
            } else {
                .pairing
            }
            send(.serverHello(ServerHelloPayload(macID: macID, macName: name, mode: mode)), on: connection)
            if mode == .paired {
                send(.heartbeat(HeartbeatPayload()), on: connection)
            }
            receive(on: connection, link: link, decoder: decoder, role: role, session: session)
        }
        connection.start(queue: queue)
    }

    private func receive(
        on connection: NWConnection,
        link: UUID,
        decoder: CompanionFrameDecoder,
        role: CompanionLinkRole,
        session: CompanionVerifiedSession
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    for message in await decoder.append(data).messages {
                        self.handle(message, on: connection, link: link, role: role, session: session)
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, link: link, decoder: decoder, role: role, session: session)
                }
            }
        }
    }

    private func handle(
        _ message: CompanionMessage,
        on connection: NWConnection,
        link: UUID,
        role: CompanionLinkRole,
        session: CompanionVerifiedSession
    ) {
        guard gate.isAuthorized(role, link: link) else {
            connection.cancel()
            return
        }
        switch CompanionLinkAuthorizer.decide(message, role: role) {
        case .refuse:
            connection.cancel()
        case .ignore:
            break
        case .unpair:
            state.withLock { $0.received.append(message.logName) }
            if case .paired(let pin, _) = role {
                gate.revoke(pin)
            }
            connection.cancel()
        case .dispatch:
            state.withLock { $0.received.append(message.logName) }
            if case .heartbeat = message {
                send(.heartbeat(HeartbeatPayload()), on: connection)
            }
        case .pairRequest:
            guard case .pairRequest(let request) = message,
                  let step = gate.beginPairing(link: link, role: role, request: request, session: session, macPin: identity.pin) else {
                connection.cancel()
                return
            }
            send(.pairChallenge(PairChallengePayload(proof: step.challenge)), on: connection)
            let confirmation = confirmation, delay = confirmDelay, gate = gate
            Task {
                try? await Task.sleep(for: delay)
                switch confirmation {
                case .accept:
                    gate.trust(step.phonePin)
                    self.send(.pairResult(PairResultPayload(accepted: true)), on: connection)
                case .reject:
                    self.send(.pairResult(PairResultPayload(accepted: false, reason: "Cancelled on the Mac.")), on: connection)
                }
            }
        }
    }

    private func send(_ message: CompanionMessage, on connection: NWConnection) {
        guard let data = try? message.encodeLengthPrefixed() else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}

/// The pairing UI tests' seam (#590): with `--uitesting --fake-mac-pairing`, Bonjour is replaced
/// by one fake Mac on loopback whose typed code is `UITEST_PAIRING_CODE`.
@MainActor
enum UITestFakeMacPairing {
    /// The phone's Keychain stand-in for every `--uitesting` launch.
    static let store = InMemoryCompanionSecretStore()

    static let port: UInt16 = 48849

    private static let fake: FakeCompanionMac? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--fake-mac-pairing") else { return nil }
        let code = ProcessInfo.processInfo.environment["UITEST_PAIRING_CODE"].flatMap(CompanionPairingCode.init(typed:)) ?? .random()
        guard let fake = try? FakeCompanionMac(port: port, code: code, confirmDelay: .seconds(3)) else { return nil }
        Task { _ = try? await fake.start() }
        return fake
    }()

    /// The fake Mac as the browser would list it.
    static var discovered: (mac: DiscoveredMac, endpoint: NWEndpoint)? {
        guard let fake, let port = NWEndpoint.Port(rawValue: port) else { return nil }
        let mac = DiscoveredMac(id: "fake-mac", name: fake.name, macID: fake.macID, protocolVersion: CompanionMessage.currentProtocolVersion)
        return (mac, .hostPort(host: .ipv4(.loopback), port: port))
    }

    /// What the fake Mac's QR holds, for the scan stand-in (the simulator has no camera).
    static var invitation: CompanionPairingInvitation? {
        fake?.invitation(port: port)
    }
}
