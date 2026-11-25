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

    @Test("An unpaired phone gets an explicit refusal, the link closes, and no message type reaches the handler")
    func unpairedRefused() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: mac.pin, port: mac.port)
        await phone.start()
        guard case .serverHello(let hello)? = await phone.firstMessage() else {
            Issue.record("expected serverHello")
            return
        }
        #expect(hello.mode == .refused)
        for message in Self.everyPhoneMessage {
            phone.send(message)
        }
        #expect(await phone.waitUntilClosed())
        #expect(await phone.nextMessage(timeout: .milliseconds(300)) == nil)
        #expect(mac.handled.isEmpty)
        // Settings can show the attempt whenever it is opened.
        #expect(await poll { await mac.service.refusedAttemptDate() != nil })
    }

    @Test("The refusal is the status alone: its bytes carry neither the Mac's name nor its ID")
    func refusalRevealsNothing() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: mac.pin, port: mac.port)
        await phone.start()
        guard case .serverHello(let hello)? = await phone.firstMessage() else {
            Issue.record("expected the refusal")
            return
        }
        #expect(hello == .refusal)
        #expect(await phone.waitUntilClosed())
        let bytes = phone.receivedBytes
        #expect(!bytes.isEmpty)
        #expect(bytes.range(of: Data(mac.macName.utf8)) == nil)
        #expect(bytes.range(of: Data(mac.macID.uuidString.utf8)) == nil)
        #expect(bytes.range(of: Data(mac.macID.uuidString.lowercased().utf8)) == nil)
        #expect(bytes.range(of: Data("macName".utf8)) == nil)
        #expect(bytes.range(of: Data("macID".utf8)) == nil)
    }

    @Test("A paired phone is greeted as paired and its messages reach the handler")
    func pairedDispatches() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        guard case .serverHello(let payload)? = await phone.firstMessage() else {
            Issue.record("expected serverHello")
            return
        }
        #expect(payload.mode == .paired)
        phone.send(.heartbeat(HeartbeatPayload()))
        #expect(await poll { mac.handled.contains("heartbeat") })
    }

    @Test("A removed phone's live link closes, and on reconnect it is refused")
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
        guard case .serverHello(let hello)? = await again.firstMessage() else {
            Issue.record("expected the refusal")
            return
        }
        #expect(hello.mode == .refused)
        again.send(.heartbeat(HeartbeatPayload()))
        #expect(await again.waitUntilClosed())
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
        guard case .serverHello(let hello)? = await phone.firstMessage() else {
            Issue.record("expected the refusal")
            return
        }
        #expect(hello.mode == .refused)
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

    @Test("Pairing with the QR: proofs both ways, the same code, both confirmations, then the phone is paired")
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
        let commitment = try #require(hello.commitment)
        let binding = try phone.binding(macPin: offer.invitation.macPin)
        let phoneNonce = CompanionPairingProof.makeNonce()
        phone.send(.pairRequest(PairRequestPayload(
            kind: .qr,
            proof: CompanionPairingProof.make(role: .phone, kind: .qr, secret: offer.invitation.secret, binding: binding),
            nonce: phoneNonce,
            phoneName: "Test\u{0007} iPhone"
        )))
        guard case .pairChallenge(let challenge)? = await phone.nextMessage() else {
            Issue.record("expected pairChallenge")
            return
        }
        #expect(CompanionPairingProof.verify(challenge.proof, role: .mac, kind: .qr, secret: offer.invitation.secret, binding: binding))
        // The Mac reveals the nonce it committed to before seeing the phone's.
        #expect(CompanionPairingProof.commitment(to: challenge.nonce) == commitment)

        let event = try #require(await mac.nextEvent())
        guard case .awaitingConfirmation(let link, let name, let code) = event else {
            Issue.record("expected awaitingConfirmation, got \(event)")
            return
        }
        #expect(name == "Test iPhone")
        #expect(code == CompanionPairingProof.comparisonCode(
            exporter: binding.exporter, macPin: binding.macPin, phonePin: binding.phonePin,
            macNonce: challenge.nonce, phoneNonce: phoneNonce
        ))

        // The Mac's user clicks Pair first: nothing is pinned until the phone says the codes match.
        await mac.service.confirmPairing(link: link, accepted: true)
        #expect(await mac.nextEvent() == .awaitingPhone(link: link))
        #expect(await mac.service.pairedPhones().isEmpty)
        phone.send(.pairResult(PairResultPayload(accepted: true)))
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

    @Test("Don't Match on the phone after the Mac clicked Pair: no pin, and the phone is refused later")
    func phoneMismatchAfterMacAccepted() async throws {
        let mac = try await TestMac.start()
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
        await mac.service.confirmPairing(link: link, accepted: true)
        phone.send(.pairResult(PairResultPayload(accepted: false, reason: "The codes didn't match.")))
        #expect(await phone.waitUntilClosed())
        #expect(await mac.service.pairedPhones().isEmpty)
        await mac.service.closePairingWindow()
        let later = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await later.start()
        guard case .serverHello(let hello)? = await later.firstMessage() else {
            Issue.record("expected the refusal")
            return
        }
        #expect(hello.mode == .refused)
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
            phone.send(.pairResult(PairResultPayload(accepted: true)))
            await mac.service.confirmPairing(link: link, accepted: failsStorage)
            guard case .pairResult(let result)? = await phone.nextMessage() else {
                Issue.record("expected pairResult")
                return
            }
            #expect(!result.accepted)
            #expect(await mac.service.pairedPhones().isEmpty)
            await mac.service.closePairingWindow()
            let retry = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
            await retry.start()
            guard case .serverHello(let hello)? = await retry.firstMessage() else {
                Issue.record("expected the refusal")
                return
            }
            #expect(hello.mode == .refused)
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

    @Test("Any frame but the pairing ones closes a pairing link without reaching the handler")
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
        phone.send(.pairRequest(PairRequestPayload(kind: .qr, proof: Data(repeating: 1, count: 32), nonce: Data(count: 32), phoneName: "x")))
        #expect(await phone.waitUntilClosed())
        #expect(await mac.nextEvent(timeout: .milliseconds(300)) == nil)
    }

    static let everyPhoneMessage: [CompanionMessage] = [
        .heartbeat(HeartbeatPayload()),
        .command(CommandPayload(action: .scanDevices)),
        .command(CommandPayload(action: .wakeOnLan, parameters: ["mac": "00:11:22:33:44:55"])),
        .networkProfile(NetworkProfilePayload(name: "n", gatewayIP: "10.0.0.1", subnet: "10.0.0.0/24", interfaceName: "en0")),
        insightRequest(),
        .pairRequest(PairRequestPayload(kind: .qr, proof: Data(count: 32), nonce: Data(count: 32), phoneName: "x")),
        .pairResult(PairResultPayload(accepted: true)),
        .unpair(UnpairPayload())
    ]

    static func insightRequest() -> CompanionMessage {
        .insightRequest(InsightRequestPayload(requestID: UUID(), request: InsightRequest(subject: "s", facts: ["a"])))
    }
}

/// The service's limits and lifecycle (#590): deferred work across a revoke, the per-link model
/// request cap, stale listener generations, the pre-auth frame limit and the link caps.
@Suite("CompanionService limits and lifecycle", .serialized)
struct CompanionServiceLimitsTests {
    // MARK: Deferred work and listener lifecycle

    @Test("A model request held back across a revoke never reaches the handler")
    func deferredWorkAfterRevoke() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let release = AsyncGate()
        await mac.service.setDeferredStartHookForTesting { await release.wait() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        phone.send(Self.insightRequest())
        #expect(await poll { await release.waiters > 0 })
        #expect(await mac.service.revoke(identity.pin))
        await release.open()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!mac.handled.contains("insightRequest"))
    }

    @Test("The handler's token turns false when the phone is removed while the handler is paused")
    func handlerTokenFollowsRevoke() async throws {
        let identity = CompanionIdentity()
        let pause = AsyncGate()
        let mac = try await TestMac.start(paired: [identity.pin], handlerPause: pause)
        defer { mac.stop() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        phone.send(CompanionServiceAuthTests.insightRequest())
        #expect(await poll { await pause.waiters > 0 })
        #expect(await mac.service.revoke(identity.pin))
        await pause.open()
        #expect(await poll { mac.tokenAfterPause.with { $0 } != nil })
        #expect(mac.tokenAfterPause.with { $0 } == false)
    }

    @Test("A phone gets at most two model requests running; a third is answered busy")
    func insightRequestCap() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let release = AsyncGate()
        await mac.service.setDeferredStartHookForTesting { await release.wait() }
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        for _ in 0..<3 {
            phone.send(Self.insightRequest())
        }
        let busy = await phone.message(timeout: .seconds(3)) {
            if case .insightResponse(let response) = $0 {
                response.failureReason == .busy
            } else {
                false
            }
        }
        #expect(busy != nil)
        #expect(await release.waiters == 2)
        await release.open()
    }

    @Test("A connection from a stopped listener's generation is dropped; the current one is taken")
    func staleListenerConnection() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let current = await mac.service.currentListenerGenerationForTesting
        let stale = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
        await mac.service.acceptForTesting(stale, generation: current - 1)
        #expect(await mac.service.linkCountForTesting == 0)
        let fresh = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
        await mac.service.acceptForTesting(fresh, generation: current)
        #expect(await mac.service.linkCountForTesting == 1)
        fresh.cancel()
    }

    // MARK: Limits

    @Test("A frame over 4 KiB on a pairing link closes it before any decoding")
    func pairingFrameLimit() async throws {
        let mac = try await TestMac.start()
        defer { mac.stop() }
        let offer = try #require(await mac.service.openPairingWindow())
        let phone = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        var big = UInt32(5000).bigEndian
        phone.sendRaw(Data(bytes: &big, count: 4) + Data(repeating: 0x20, count: 5000))
        #expect(await phone.waitUntilClosed())
        #expect(await mac.nextEvent(timeout: .milliseconds(300)) == nil)
    }

    @Test("Pairing links are capped, but a paired phone still gets in while they are full")
    func pairingCapSparesPairedPhones() async throws {
        let identity = CompanionIdentity()
        let limits = CompanionService.Limits(maximumPairingLinks: 1, authDeadline: .seconds(5), pairingDeadline: .seconds(20))
        let mac = try await TestMac.start(paired: [identity.pin], limits: limits)
        defer { mac.stop() }
        let offer = try #require(await mac.service.openPairingWindow())
        let first = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        await first.start()
        #expect(await first.firstMessage() != nil)
        let second = TestCompanionPhone(identity: CompanionIdentity(), macPin: offer.invitation.macPin, port: mac.port)
        await second.start()
        #expect(await second.waitUntilClosed())
        let paired = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await paired.start()
        guard case .serverHello(let hello)? = await paired.firstMessage() else {
            Issue.record("the paired phone should get in")
            return
        }
        #expect(hello.mode == .paired)
    }

    @Test("Beyond the total link cap a connection is closed at accept")
    func totalLinkCap() async throws {
        let identity = CompanionIdentity()
        let limits = CompanionService.Limits(maximumLinks: 1, authDeadline: .seconds(5), pairingDeadline: .seconds(20))
        let mac = try await TestMac.start(paired: [identity.pin], limits: limits)
        defer { mac.stop() }
        let first = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await first.start()
        #expect(await first.firstMessage() != nil)
        let second = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await second.start()
        #expect(await second.waitUntilClosed())
        #expect(await second.nextMessage(timeout: .milliseconds(300)) == nil)
    }

    static func insightRequest() -> CompanionMessage {
        CompanionServiceAuthTests.insightRequest()
    }
}

// MARK: - Harness

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
        await service.setEventHandler { event in events.with { $0.append(event) } }
        try await service.start(messageHandler: { message, _, authorization in
            handled.with { $0.append(message.logName) }
            if let handlerPause {
                await handlerPause.wait()
                let current = await authorization.isCurrent()
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
