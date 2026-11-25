import Foundation
import Network
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// The Mac's companion service on loopback with real TLS (#590): who it lets in, what it
/// dispatches, and how pairing and Remove behave.
@Suite("CompanionService authentication", .serialized)
struct CompanionServiceAuthTests {
    // MARK: Refusal

    @Test("An unpaired phone fails the handshake, and no message type reaches the handler")
    func unpairedRefused() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: mac.pin, port: mac.port)
        await phone.start()
        for message in Self.everyPhoneMessage {
            phone.send(message)
        }
        #expect(await phone.waitUntilClosed())
        #expect(await phone.firstMessage(timeout: .milliseconds(300)) == nil)
        #expect(mac.handled.isEmpty)
    }

    @Test("A paired phone is greeted as paired and its messages reach the handler")
    func pairedDispatches() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        let hello = await phone.firstMessage()
        guard case .serverHello(let payload)? = hello else {
            Issue.record("expected serverHello, got \(String(describing: hello))")
            return
        }
        #expect(payload.mode == .paired)
        phone.send(.heartbeat(HeartbeatPayload()))
        #expect(await poll { mac.handled.contains("heartbeat") })
    }

    @Test("A removed phone's live link closes and it can't reconnect")
    func revokedPhone() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        #expect(await mac.service.revoke(identity.pin))
        #expect(await phone.waitUntilClosed())
        #expect(await mac.service.pairedPhones().isEmpty)

        let again = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await again.start()
        again.send(.heartbeat(HeartbeatPayload()))
        #expect(await again.waitUntilClosed())
        #expect(await again.firstMessage(timeout: .milliseconds(300)) == nil)
        #expect(!mac.handled.contains("heartbeat"))
    }

    @Test("A Keychain delete failure still denies the phone at once and reports it")
    func revokeDeleteFailure() async throws {
        let identity = CompanionIdentity()
        let backing = InMemoryCompanionSecretStore()
        let mac = try await TestMac.start(paired: [identity.pin], backing: backing)
        defer { mac.stop() }
        backing.failDeletes = true
        #expect(await !mac.service.revoke(identity.pin))
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        #expect(await phone.waitUntilClosed())
        #expect(await mac.service.pairedPhones().isEmpty)
    }

    @Test("A connection that never completes its handshake is closed at the deadline")
    func stalledHandshake() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let stalled = try NWConnection(host: "127.0.0.1", port: #require(NWEndpoint.Port(rawValue: mac.port)), using: .tcp)
        let closed = Locked(false)
        stalled.stateUpdateHandler = { state in
            if case .ready = state {
                stalled.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
                    if isComplete || error != nil {
                        closed.with { $0 = true }
                    }
                }
            }
        }
        stalled.start(queue: .global())
        defer { stalled.cancel() }
        #expect(await poll(timeout: .seconds(3)) { closed.with { $0 } })
    }

    // MARK: Pairing

    @Test("Pairing with the QR: proofs both ways, the same comparison code, confirm, then the phone is paired")
    func pairingRoundTrip() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let offer = try #require(await mac.service.openPairingWindow())
        let phoneIdentity = CompanionIdentity()
        let phone = TestCompanionPhone(identity: phoneIdentity, macPin: offer.invitation.macPin, port: mac.port)
        await phone.start()
        guard case .serverHello(let hello)? = await phone.firstMessage() else {
            Issue.record("expected serverHello")
            return
        }
        #expect(hello.mode == .pairing)
        let binding = try phone.binding(macPin: offer.invitation.macPin)
        phone.send(.pairRequest(PairRequestPayload(
            kind: .qr,
            proof: CompanionPairingProof.make(role: .phone, kind: .qr, secret: offer.invitation.secret, binding: binding),
            phoneName: "Test\u{0007} iPhone"
        )))
        guard case .pairChallenge(let challenge)? = await phone.nextMessage() else {
            Issue.record("expected pairChallenge")
            return
        }
        #expect(CompanionPairingProof.verify(challenge.proof, role: .mac, kind: .qr, secret: offer.invitation.secret, binding: binding))

        let event = try #require(await mac.nextEvent())
        guard case .awaitingConfirmation(let link, let name, let code) = event else {
            Issue.record("expected awaitingConfirmation, got \(event)")
            return
        }
        #expect(name == "Test iPhone")
        #expect(code == CompanionPairingProof.comparisonCode(exporter: binding.exporter, macPin: binding.macPin, phonePin: binding.phonePin))
        #expect(await mac.service.pairedPhones().isEmpty)

        await mac.service.confirmPairing(link: link, accepted: true)
        guard case .pairResult(let result)? = await phone.nextMessage() else {
            Issue.record("expected pairResult")
            return
        }
        #expect(result.accepted)
        #expect(await mac.service.pairedPhones().map(\.pin) == [phoneIdentity.pin])

        let paired = TestCompanionPhone(identity: phoneIdentity, macPin: mac.pin, port: mac.port)
        await paired.start()
        guard case .serverHello(let again)? = await paired.firstMessage() else {
            Issue.record("expected serverHello")
            return
        }
        #expect(again.mode == .paired)
    }

    @Test("Don't Pair on the Mac, or a failed Keychain save, pins nothing")
    func rejectedPairing() async throws {
        for failsStorage in [false, true] {
            let backing = InMemoryCompanionSecretStore()
            let mac = try await TestMac.start(backing: backing)
            defer { mac.stop() }
            let offer = try #require(await mac.service.openPairingWindow())
            let identity = CompanionIdentity()
            let phone = TestCompanionPhone(identity: identity, macPin: offer.invitation.macPin, port: mac.port)
            await phone.start()
            _ = await phone.firstMessage()
            try phone.sendPairRequest(offer: offer)
            _ = await phone.nextMessage()
            guard case .awaitingConfirmation(let link, _, _)? = await mac.nextEvent() else {
                Issue.record("expected awaitingConfirmation")
                return
            }
            backing.failWrites = failsStorage
            await mac.service.confirmPairing(link: link, accepted: !failsStorage ? false : true)
            guard case .pairResult(let result)? = await phone.nextMessage() else {
                Issue.record("expected pairResult")
                return
            }
            #expect(!result.accepted)
            #expect(await mac.service.pairedPhones().isEmpty)
            let retry = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
            await retry.start()
            #expect(await retry.waitUntilClosed())
        }
    }

    @Test("Once one phone has proved the secret, the window's other connections close and a second request gets nothing")
    func secondPairingRefused() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let offer = try #require(await mac.service.openPairingWindow())
        let first = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        let second = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        await first.start()
        await second.start()
        _ = await first.firstMessage()
        _ = await second.firstMessage()
        try first.sendPairRequest(offer: offer)
        _ = await first.nextMessage()
        #expect(await second.waitUntilClosed())
        try? second.sendPairRequest(offer: offer)
        #expect(await second.nextMessage(timeout: .milliseconds(300)) == nil)
    }

    @Test("Any frame but pairRequest closes a pairing link without reaching the handler")
    func pairingLinkRefusesOtherFrames() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let offer = try #require(await mac.service.openPairingWindow())
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        phone.send(.command(CommandPayload(action: .scanDevices)))
        #expect(await phone.waitUntilClosed())
        #expect(mac.handled.isEmpty)
    }

    @Test("A wrong proof closes the link and nothing is offered for confirmation")
    func wrongProof() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        _ = try #require(await mac.service.openPairingWindow())
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        phone.send(.pairRequest(PairRequestPayload(kind: .qr, proof: Data(repeating: 1, count: 32), phoneName: "x")))
        #expect(await phone.waitUntilClosed())
        #expect(await mac.nextEvent(timeout: .milliseconds(300)) == nil)
    }

    static let everyPhoneMessage: [CompanionMessage] = [
        .heartbeat(HeartbeatPayload()),
        .command(CommandPayload(action: .scanDevices)),
        .command(CommandPayload(action: .wakeOnLan, parameters: ["mac": "00:11:22:33:44:55"])),
        .networkProfile(NetworkProfilePayload(name: "n", gatewayIP: "10.0.0.1", subnet: "10.0.0.0/24", interfaceName: "en0")),
        .insightRequest(InsightRequestPayload(requestID: UUID(), request: InsightRequest(subject: "s", facts: ["a"]))),
        .pairRequest(PairRequestPayload(kind: .qr, proof: Data(count: 32), phoneName: "x")),
        .unpair(UnpairPayload())
    ]
}

// MARK: - Harness

/// A Mac companion service on a free loopback port with in-memory credentials.
final class TestMac: @unchecked Sendable {
    let service: CompanionService
    let pin: Data
    let port: UInt16
    private let handledTypes: Locked<[String]>
    private let events: Locked<[CompanionPairingEvent]>

    /// Message types the handler was given.
    var handled: [String] { handledTypes.with { $0 } }

    private init(service: CompanionService, pin: Data, port: UInt16, handled: Locked<[String]>, events: Locked<[CompanionPairingEvent]>) {
        self.service = service
        self.pin = pin
        self.port = port
        handledTypes = handled
        self.events = events
    }

    static func start(paired pins: [Data] = [], backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore()) async throws -> TestMac {
        let defaults = try #require(UserDefaults(suiteName: "test.companion.\(UUID().uuidString)"))
        let phones = pins.map { PairedPhone(pin: $0, name: "Phone", pairedAt: Date()) }
        let credentials = CompanionCredentials.inMemory(seedPhones: phones, defaults: defaults, backing: backing)
        let limits = CompanionService.Limits(authDeadline: .milliseconds(800), pairingDeadline: .seconds(20))
        let service = CompanionService(credentials: credentials, port: 0, limits: limits, advertises: false)
        let handled = Locked<[String]>([])
        let events = Locked<[CompanionPairingEvent]>([])
        await service.setEventHandler { event in events.with { $0.append(event) } }
        try await service.start(messageHandler: { message, _ in
            handled.with { $0.append(message.logName) }
            return nil
        })
        let port = try #require(await poll { await service.listeningPort.flatMap { $0 == 0 ? nil : $0 } })
        return TestMac(service: service, pin: credentials.identity.pin, port: port, handled: handled, events: events)
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
            case .failed, .cancelled:
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

    func waitUntilClosed(timeout: Duration = .seconds(5)) async -> Bool {
        await poll(timeout: timeout) { [closed] in closed.with { $0 } ? true : nil } ?? false
    }

    deinit {
        connection.cancel()
    }
}

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
