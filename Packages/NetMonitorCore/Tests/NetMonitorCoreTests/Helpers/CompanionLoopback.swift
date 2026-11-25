import Foundation
import Network
@testable import NetMonitorCore

/// A thread-safe box for test state written from Network.framework callbacks.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func with<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// The Mac's live set of pinned phones, read by the verify block on every handshake.
final class PinSet: Sendable {
    private let pins: Locked<Set<Data>>
    init(_ pins: Set<Data>) { self.pins = Locked(pins) }
    func contains(_ pin: Data) -> Bool { pins.with { $0.contains(pin) } }
    func removeAll() { pins.with { $0.removeAll() } }
}

struct ClientOutcome {
    let session: CompanionVerifiedSession?
}

/// Polls `read` until it returns a value or `timeout` passes.
func poll<T>(timeout: Duration, _ read: () -> T?) async -> T? {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = read() {
            return value
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return read()
}

/// A TLS listener on 127.0.0.1 built from `CompanionTLS`, recording what it accepts.
final class LoopbackHarness: @unchecked Sendable {
    let port: NWEndpoint.Port
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.companion.loopback")
    private let sessions = Locked<[CompanionVerifiedSession]>([])
    private let received = Locked(Data())
    private let failures = Locked(0)
    private let connections = Locked<[NWConnection]>([])

    init(server: CompanionIdentity, acceptsClient: @escaping @Sendable (Data) -> Bool) async throws {
        let parameters = try requireParameters(CompanionTLS.parameters(identity: server, acceptsPeer: acceptsClient))
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        let sessions = sessions, received = received, failures = failures, connections = connections, queue = queue
        listener.newConnectionHandler = { connection in
            connections.with { $0.append(connection) }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let session = CompanionTLS.sessionFacts(of: connection).verified {
                        sessions.with { $0.append(session) }
                    }
                    Self.receiveAll(connection, into: received)
                case .failed:
                    failures.with { $0 += 1 }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        let ready = Locked(false)
        listener.stateUpdateHandler = {
            if case .ready = $0 {
                ready.with { $0 = true }
            }
        }
        listener.start(queue: queue)
        _ = await poll(timeout: .seconds(5)) { ready.with { $0 } ? true : nil }
        // swiftlint:disable:next force_unwrapping
        port = listener.port!
    }

    private static func receiveAll(_ connection: NWConnection, into sink: Locked<Data>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data {
                sink.with { $0.append(data) }
            }
            if !isComplete, error == nil {
                receiveAll(connection, into: sink)
            }
        }
    }

    func nextServerSession(timeout: Duration = .seconds(5)) async -> CompanionVerifiedSession? {
        await poll(timeout: timeout) {
            sessions.with { $0.isEmpty ? nil : $0.removeFirst() }
        }
    }

    func nextServerBytes(timeout: Duration = .seconds(5)) async -> Data {
        await poll(timeout: timeout) { received.with { $0.isEmpty ? nil : $0 } } ?? Data()
    }

    func serverFailures() async -> Int {
        await poll(timeout: .seconds(2)) { failures.with { $0 > 0 ? $0 : nil } } ?? 0
    }

    func connect(
        client: CompanionIdentity,
        pinning macPin: Data,
        via relayPort: NWEndpoint.Port? = nil,
        sending frame: Data? = nil
    ) async -> ClientOutcome {
        guard let parameters = CompanionTLS.parameters(identity: client, acceptsPeer: { $0 == macPin }) else {
            return ClientOutcome(session: nil)
        }
        let connection = NWConnection(host: "127.0.0.1", port: relayPort ?? port, using: parameters)
        connections.with { $0.append(connection) }
        let result = Locked<CompanionVerifiedSession??>(nil)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let session = CompanionTLS.sessionFacts(of: connection).verified
                if let frame {
                    connection.send(content: frame, completion: .contentProcessed { _ in })
                }
                result.with { $0 = .some(session) }
            case .failed, .waiting:
                connection.cancel()
                result.with { $0 = .some(nil) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        let session = await poll(timeout: .seconds(5)) { result.with { $0 } }.flatMap { $0 }
        return ClientOutcome(session: session)
    }

    /// TLS 1.3 with no local identity, accepting any server.
    func connectWithoutCertificate() async {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let connection = NWConnection(host: "127.0.0.1", port: port, using: NWParameters(tls: options))
        connections.with { $0.append(connection) }
        let done = Locked(false)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .waiting: done.with { $0 = true }
            default: break
            }
        }
        connection.start(queue: queue)
        _ = await poll(timeout: .seconds(5)) { done.with { $0 } ? true : nil }
    }

    func stop() {
        listener.cancel()
        connections.with { $0.forEach { $0.cancel() } }
    }
}

private func requireParameters(_ parameters: NWParameters?) throws -> NWParameters {
    guard let parameters else { throw CompanionLoopbackError.noParameters }
    return parameters
}

private enum CompanionLoopbackError: Error { case noParameters }

/// A plain TCP relay to `target` that records every byte it forwards, in both directions.
final class RecordingRelay: @unchecked Sendable {
    let port: NWEndpoint.Port
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.companion.relay")
    private let bytes = Locked(Data())
    private let connections = Locked<[NWConnection]>([])

    init(target: NWEndpoint.Port) async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let bytes = bytes, connections = connections, queue = queue
        listener.newConnectionHandler = { inbound in
            let outbound = NWConnection(host: "127.0.0.1", port: target, using: .tcp)
            connections.with { $0 += [inbound, outbound] }
            Self.pipe(from: inbound, to: outbound, recording: bytes)
            Self.pipe(from: outbound, to: inbound, recording: bytes)
            inbound.start(queue: queue)
            outbound.start(queue: queue)
        }
        let ready = Locked(false)
        listener.stateUpdateHandler = {
            if case .ready = $0 {
                ready.with { $0 = true }
            }
        }
        listener.start(queue: queue)
        _ = await poll(timeout: .seconds(5)) { ready.with { $0 } ? true : nil }
        // swiftlint:disable:next force_unwrapping
        port = listener.port!
    }

    private static func pipe(from source: NWConnection, to sink: NWConnection, recording bytes: Locked<Data>) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                bytes.with { $0.append(data) }
                sink.send(content: data, completion: .contentProcessed { _ in })
            }
            if !isComplete, error == nil {
                pipe(from: source, to: sink, recording: bytes)
            }
        }
    }

    func captured() async -> Data {
        try? await Task.sleep(for: .milliseconds(300))
        return bytes.with { $0 }
    }

    func stop() {
        listener.cancel()
        connections.with { $0.forEach { $0.cancel() } }
    }
}
