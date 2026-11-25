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
