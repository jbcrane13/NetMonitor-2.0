import Foundation
import Network
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// Loopback harness for the companion service tests (#590): a Mac on a free port with in-memory
/// credentials, a TLS phone, and small helpers.

/// Opens once; everything waiting before or after passes.
actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var waiters = 0

    func wait() async {
        guard !isOpen else { return }
        waiters += 1
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

/// A Mac companion service on a free loopback port with in-memory credentials.
final class TestMac: @unchecked Sendable {
    let service: CompanionService
    let pin: Data
    let macID: UUID
    let macName: String
    let port: UInt16
    /// What the live authorisation token said when a paused handler resumed.
    let tokenAfterPause: Locked<Bool?>
    private let handledTypes: Locked<[String]>
    private let events: Locked<[CompanionPairingEvent]>

    /// Message types the handler was given.
    var handled: [String] { handledTypes.with { $0 } }

    private init(
        service: CompanionService,
        credentials: CompanionCredentials,
        port: UInt16,
        handled: Locked<[String]>,
        events: Locked<[CompanionPairingEvent]>,
        tokenAfterPause: Locked<Bool?>
    ) {
        self.tokenAfterPause = tokenAfterPause
        self.service = service
        pin = credentials.identity.pin
        macID = credentials.macID
        macName = credentials.macName
        self.port = port
        handledTypes = handled
        self.events = events
    }

    static func start(
        paired pins: [Data] = [],
        backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore(),
        limits: CompanionService.Limits = CompanionService.Limits(authDeadline: .milliseconds(800), pairingDeadline: .seconds(20)),
        handlerPause: AsyncGate? = nil
    ) async throws -> TestMac {
        let phones = pins.map { PairedPhone(pin: $0, name: "Phone", pairedAt: Date()) }
        let credentials = CompanionCredentials.inMemory(
            seedPhones: phones, defaultsSuite: "test.companion.\(UUID().uuidString)", backing: backing
        )
        let service = CompanionService(credentials: credentials, port: 0, limits: limits, advertises: false)
        let handled = Locked<[String]>([])
        let events = Locked<[CompanionPairingEvent]>([])
        let tokenAfterPause = Locked<Bool?>(nil)
        await service.addEventHandler(UUID()) { event in events.with { $0.append(event) } }
        try await service.start(messageHandler: { message, _, authorization in
            handled.with { $0.append(message.logName) }
            if let handlerPause {
                await handlerPause.wait()
                let current = authorization.isCurrent()
                tokenAfterPause.with { $0 = current }
            }
            return nil
        })
        let port = try #require(await poll { await service.listeningPort.flatMap { $0 == 0 ? nil : $0 } })
        return TestMac(
            service: service, credentials: credentials, port: port, handled: handled, events: events, tokenAfterPause: tokenAfterPause
        )
    }

    /// The next pairing event other than a refused attempt.
    func nextEvent(timeout: Duration = .seconds(5)) async -> CompanionPairingEvent? {
        await poll(timeout: timeout) { [events] in
            events.with { list -> CompanionPairingEvent? in
                guard let index = list.firstIndex(where: {
                    if case .refusedAttempt = $0 {
                        false
                    } else {
                        true
                    }
                }) else { return nil }
                return list.remove(at: index)
            }
        }
    }

    func stop() {
        let service = service
        Task { await service.stop() }
    }
}

/// A phone end built on `CompanionTLS`, recording the frames it receives.
final class TestCompanionPhone: @unchecked Sendable {
    let identity: CompanionIdentity
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "test.companion.phone")
    private let decoder = CompanionFrameDecoder()
    private let inbox = Locked<[CompanionMessage]>([])
    private let raw = Locked(Data())
    private let closed = Locked(false)
    private let ready = Locked<Bool?>(nil)

    init(identity: CompanionIdentity, macPin: Data, port: UInt16) {
        self.identity = identity
        // swiftlint:disable:next force_unwrapping
        let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: { $0 == macPin })!
        // swiftlint:disable:next force_unwrapping
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }

    func start() async {
        let ready = ready, closed = closed
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                ready.with { $0 = true }
                self?.receive()
            case .failed, .cancelled, .waiting:
                // `.waiting`: the Mac reset the connection mid-handshake, so this attempt is over.
                ready.with { $0 = $0 ?? false }
                closed.with { $0 = true }
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = await poll { ready.with { $0 } }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                raw.with { $0.append(data) }
                let decoder = decoder, inbox = inbox
                Task {
                    let batch = await decoder.append(data)
                    inbox.with { $0.append(contentsOf: batch.messages) }
                }
            }
            if isComplete || error != nil {
                closed.with { $0 = true }
            } else {
                receive()
            }
        }
    }

    func send(_ message: CompanionMessage) {
        guard let data = try? message.encodeLengthPrefixed() else { return }
        sendRaw(data)
    }

    /// Every byte the Mac sent, decrypted, in order.
    var receivedBytes: Data { raw.with { $0 } }

    func sendRaw(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    /// The binding of this phone's session, as the phone computes it.
    func binding(macPin: Data) throws -> CompanionPairingProof.Binding {
        let session = try #require(CompanionTLS.sessionFacts(of: connection).verified)
        return CompanionPairingProof.Binding(exporter: session.exporter, macPin: macPin, phonePin: identity.pin)
    }

    func sendPairRequest(offer: CompanionPairingOffer) throws {
        let binding = try binding(macPin: offer.invitation.macPin)
        send(.pairRequest(PairRequestPayload(
            kind: .qr,
            proof: CompanionPairingProof.make(role: .phone, kind: .qr, secret: offer.invitation.secret, binding: binding),
            nonce: CompanionPairingProof.makeNonce(),
            phoneName: "iPhone"
        )))
    }

    func firstMessage(timeout: Duration = .seconds(5)) async -> CompanionMessage? {
        await nextMessage(timeout: timeout)
    }

    func nextMessage(timeout: Duration = .seconds(5)) async -> CompanionMessage? {
        await poll(timeout: timeout) { [inbox] in
            inbox.with { $0.isEmpty ? nil : $0.removeFirst() }
        }
    }

    /// The first received message matching `predicate`, removed from the inbox.
    func message(timeout: Duration, where predicate: @escaping @Sendable (CompanionMessage) -> Bool) async -> CompanionMessage? {
        await poll(timeout: timeout) { [inbox] in
            inbox.with { list in
                list.firstIndex(where: predicate).map { list.remove(at: $0) }
            }
        }
    }

    func waitUntilClosed(timeout: Duration = .seconds(5)) async -> Bool {
        await poll(timeout: timeout) { [closed] in closed.with { $0 } ? true : nil } ?? false
    }

    deinit {
        connection.cancel()
    }
}

/// Test-only shared state for Network.framework callbacks.
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

func poll<T>(timeout: Duration = .seconds(5), _ read: () async -> T?) async -> T? {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = await read() {
            return value
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await read()
}

func poll(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    await poll(timeout: timeout) { await condition() ? true : nil } ?? false
}

/// ``poll(timeout:_:)`` for a condition on main-actor state (view models), checked on the main
/// actor so a `@MainActor` test needn't send its state anywhere.
@MainActor
func pollOnMain(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}
