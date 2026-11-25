import Foundation
import Network
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// The phone end of pairing and of the paired link (#590), against `FakeCompanionMac` on
/// loopback with real TLS.
@Suite("MacConnectionService pairing", .serialized)
@MainActor
struct MacConnectionServicePairingTests {
    private func makeService(
        _ backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore(),
        defaults: UserDefaults? = nil
    ) -> (MacConnectionService, PairedMacStore) {
        let store = PairedMacStore(backing: backing)
        let service = MacConnectionService(
            insightClient: CompanionInsightClient(send: { _ in false }),
            macStore: store,
            defaults: defaults ?? Self.freshDefaults()
        )
        return (service, store)
    }

    private static func freshDefaults() -> UserDefaults {
        let suite = "test.companion.phone.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return UserDefaults(suiteName: suite)!
    }

    private func start(_ fake: FakeCompanionMac, in service: MacConnectionService) async throws -> DiscoveredMac {
        let port = try await fake.start()
        let mac = DiscoveredMac(id: "fake", name: fake.name, macID: fake.macID, protocolVersion: CompanionMessage.currentProtocolVersion)
        let endpoint = try NWEndpoint.hostPort(host: .ipv4(.loopback), port: #require(NWEndpoint.Port(rawValue: port)))
        service.addDiscoveredMacForTesting(mac, endpoint: endpoint)
        return mac
    }

    private func waitForComparing(_ service: MacConnectionService) async -> String? {
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        if case .comparing(let code, _) = service.pairingState {
            return code
        }
        Issue.record("expected comparing, got \(service.pairingState)")
        return nil
    }

    private func isFailed(_ service: MacConnectionService) -> Bool {
        if case .failed = service.pairingState {
            return true
        }
        return false
    }

    /// Pairs `service` with `fake` by typed code and waits for the paired link.
    private func pair(_ service: MacConnectionService, with fake: FakeCompanionMac, code: CompanionPairingCode) async throws -> DiscoveredMac {
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        _ = await waitForComparing(service)
        service.confirmComparison(true)
        await waitUntil({ service.connectionState.isConnected }, timeout: .seconds(6))
        return mac
    }

    // MARK: - Pairing

    @Test("Typing the Mac's code pairs: same comparison code, They Match, the Mac's key saved, then a paired link")
    func pairsWithTypedCode() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, confirmDelay: .milliseconds(600))
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)

        service.pair(code: code, with: mac)
        let shown = try #require(await waitForComparing(service))
        #expect(shown.count == 7)
        #expect(try store.load() == nil)

        service.confirmComparison(true)
        #expect(service.pairingState == .waitingForMac(code: shown, macName: "Test Mac"))
        #expect(try store.load() == nil)
        await waitUntil({ service.connectionState.isConnected }, timeout: .seconds(5))
        #expect(service.pairingState == .paired(macName: "Test Mac"))
        let record = try #require(try store.load())
        #expect(record.macPin == fake.identity.pin)
        #expect(record.macID == fake.macID)
        #expect(service.isPaired(with: mac))
        #expect(fake.received.contains("verdict:true"))
    }

    @Test("Scanning the QR pairs too, pinning the key the QR names; nothing is saved before They Match")
    func pairsWithQR() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let port = try await fake.start()
        service.pair(with: fake.invitation(port: port))
        _ = await waitForComparing(service)
        #expect(try store.load() == nil)
        service.confirmComparison(true)
        await waitUntil({ service.connectionState.isConnected }, timeout: .seconds(6))
        #expect(try store.load()?.macPin == fake.identity.pin)
    }

    @Test("A QR naming another Mac's key fails the handshake and saves nothing")
    func wrongPinInQR() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let port = try await fake.start()
        let real = fake.invitation(port: port)
        let forged = CompanionPairingInvitation(
            macID: real.macID, macName: real.macName, macPin: CompanionIdentity().pin, secret: real.secret, host: real.host, port: real.port
        )
        service.pair(with: forged)
        await waitUntil({ isFailed(service) }, timeout: .seconds(5))
        #expect(isFailed(service))
        #expect(try store.load() == nil)
        #expect(!service.connectionState.isConnected)
    }

    @Test("Back while still connecting closes the pairing link: the attempt can't continue unseen")
    func backWhileConnecting() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        #expect(service.pairingState == .connecting)
        service.resetPairingState()
        #expect(service.pairingState == .idle)
        // An absence check: had the link stayed open, the Mac's hello and challenge would arrive
        // within a few hundred milliseconds and move the state on.
        try await Task.sleep(for: .seconds(1))
        #expect(service.pairingState == .idle)
        #expect(!fake.received.contains("verdict:true"))
        #expect(try store.load() == nil)
    }

    @Test("A wrong code is refused by the Mac and nothing is saved")
    func wrongCode() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: .random(), with: mac)
        await waitUntil({ isFailed(service) }, timeout: .seconds(5))
        #expect(isFailed(service))
        #expect(try store.load() == nil)
    }

    @Test("Don't Pair on the Mac saves nothing on the phone")
    func rejectedOnMac() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, confirmation: .reject)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        _ = await waitForComparing(service)
        service.confirmComparison(true)
        await waitUntil({ service.pairingState == .failed("Cancelled on the Mac.") }, timeout: .seconds(5))
        #expect(service.pairingState == .failed("Cancelled on the Mac."))
        #expect(try store.load() == nil)
    }

    @Test("Don't Match on the phone tells the Mac, and neither side keeps a pin")
    func codesDifferOnPhone() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, confirmDelay: .milliseconds(50))
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        _ = await waitForComparing(service)
        service.confirmComparison(false)
        #expect(isFailed(service))
        await waitUntil({ fake.received.contains("verdict:false") }, timeout: .seconds(3))
        #expect(fake.received.contains("verdict:false"))
        #expect(try store.load() == nil)
        #expect(service.pairedMac == nil)
        // The Mac never pinned the phone, so no paired link can come up.
        #expect(!service.connectionState.isConnected)
    }

    @Test("A Mac that reveals a nonce other than the one it committed to is not paired")
    func brokenCommitment() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, revealsWrongNonce: true)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        await waitUntil({ isFailed(service) }, timeout: .seconds(5))
        #expect(service.pairingState == .failed("The Mac's answer didn't match what it promised. Nothing was paired."))
        #expect(try store.load() == nil)
    }

    @Test("A Mac's hello without a commitment gets no pairing request")
    func helloWithoutCommitment() throws {
        var attempt = PhonePairingAttempt(
            kind: .code, secret: Data(count: 16), identity: CompanionIdentity(), host: nil, port: CompanionLink.defaultPort, macName: "Mac"
        )
        let session = CompanionVerifiedSession(peerPin: Data(repeating: 1, count: 32), exporter: Data(repeating: 2, count: 32))
        let hello = ServerHelloPayload(macID: UUID(), macName: "Mac", mode: .pairing)
        #expect(PhonePairingFlow.pairRequest(for: &attempt, hello: hello, session: session, phoneName: "iPhone") == nil)
    }

    // MARK: - Revoked versus unreachable

    @Test("A phone the Mac refuses gets a terminal 'Forget, then pair again' and stops reconnecting")
    func refusedByMac() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let backing = InMemoryCompanionSecretStore()
        let (service, store) = makeService(backing)
        let mac = try await start(fake, in: service)
        // No pairing window, and a pairing the Mac doesn't trust: it answers serverHello{refused}.
        fake.gate.closeWindow()
        try store.save(PairedMacRecord(
            macID: fake.macID, macName: fake.name, macPin: fake.identity.pin, host: nil, port: CompanionLink.defaultPort,
            phoneIdentity: CompanionIdentity().rawRepresentation
        ))
        let (reloaded, _) = makeService(backing)
        try reloaded.addDiscoveredMacForTesting(mac, endpoint: #require(service.endpointForTesting(mac)))
        reloaded.connect(to: mac)
        await waitUntil({ reloaded.linkProblem == .notRecognized }, timeout: .seconds(5))
        #expect(reloaded.linkProblem == .notRecognized)
        let attempts = fake.connectionCount
        // An absence check: a refused phone must not come back.
        try await Task.sleep(for: .seconds(2))
        #expect(fake.connectionCount == attempts)
        #expect(!reloaded.connectionState.isConnected)
    }

    @Test("Full slots or a dropped connection read as unreachable and retry, never as 'pair again'")
    func transientFailureRetries() async throws {
        let fake = try FakeCompanionMac(dropsConnections: true)
        defer { fake.stop() }
        let backing = InMemoryCompanionSecretStore()
        let store = PairedMacStore(backing: backing)
        try store.save(PairedMacRecord(
            macID: fake.macID, macName: fake.name, macPin: fake.identity.pin, host: nil, port: CompanionLink.defaultPort,
            phoneIdentity: CompanionIdentity().rawRepresentation
        ))
        let service = MacConnectionService(
            insightClient: CompanionInsightClient(send: { _ in false }),
            macStore: store,
            defaults: Self.freshDefaults(),
            helloTimeout: .milliseconds(800)
        )
        let mac = try await start(fake, in: service)
        service.connect(to: mac)
        await waitUntil({ fake.connectionCount >= 2 }, timeout: .seconds(6))
        #expect(fake.connectionCount >= 2)
        #expect(service.linkProblem == nil)
        #expect(service.pairedMac != nil)
        service.disconnect()
    }

    @Test("A Mac that isn't paired, or is too old, isn't connected to")
    func notPairedOrOld() throws {
        let (service, _) = makeService()
        let unpaired = DiscoveredMac(id: "a", name: "A", macID: UUID(), protocolVersion: 2)
        let old = DiscoveredMac(id: "b", name: "B")
        service.addDiscoveredMacForTesting(unpaired, endpoint: .hostPort(host: .ipv4(.loopback), port: 9))
        service.addDiscoveredMacForTesting(old, endpoint: .hostPort(host: .ipv4(.loopback), port: 9))
        service.connect(to: unpaired)
        #expect(service.linkProblem == .notPaired)
        #expect(service.connectionState == .disconnected)
        service.connect(to: old)
        #expect(service.linkProblem == .macNeedsUpdate)
        service.connectDirect(host: "127.0.0.1", port: 9)
        #expect(service.linkProblem == .notPaired)
    }

    // MARK: - Forget

    @Test("Forget This Mac tells the Mac, deletes the key, and disconnects")
    func forget() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code)
        defer { fake.stop() }
        let (service, store) = makeService()
        _ = try await pair(service, with: fake, code: code)
        await service.forgetMac()
        #expect(try store.load() == nil)
        #expect(service.pairedMac == nil)
        #expect(service.forgetError == nil)
        #expect(!service.connectionState.isConnected)
        await waitUntil({ fake.received.contains("unpair") }, timeout: .seconds(3))
        #expect(fake.received.contains("unpair"))
    }

    @Test("A Forget whose delete fails blocks the key, survives a relaunch, and deletes it on the next try")
    func failedForgetStaysForgotten() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code)
        defer { fake.stop() }
        let backing = InMemoryCompanionSecretStore()
        let defaults = Self.freshDefaults()
        let (service, store) = makeService(backing, defaults: defaults)
        let mac = try await pair(service, with: fake, code: code)
        backing.failDeletes = true
        await service.forgetMac()
        #expect(service.forgetError != nil)
        #expect(service.pairedMac == nil)
        #expect(try store.load() != nil)

        // Browsing and a relaunch don't bring it back.
        service.startBrowsing()
        service.stopBrowsing()
        #expect(service.pairedMac == nil)
        let (relaunched, _) = makeService(backing, defaults: defaults)
        #expect(relaunched.pairedMac == nil)
        relaunched.addDiscoveredMacForTesting(mac, endpoint: .hostPort(host: .ipv4(.loopback), port: 9))
        relaunched.connect(to: mac)
        #expect(relaunched.linkProblem == .notPaired)

        // Once deleting works, the next load deletes it for good.
        backing.failDeletes = false
        let (later, _) = makeService(backing, defaults: defaults)
        #expect(later.pairedMac == nil)
        #expect(try store.load() == nil)
        #expect(!defaults.bool(forKey: MacConnectionService.pendingForgetKey))
    }

    // MARK: - Keychain

    /// The data protection keychain needs an entitled (signed) test host; the unsigned gate run
    /// skips this test instead of failing it, and the signed evidence run executes it.
    nonisolated static let keychainIsEntitled: Bool = {
        let probe = CompanionKeychain(service: "com.netmonitor.tests.companion.probe", accessibility: .whenUnlocked)
        do {
            try probe.write(Data([1]), account: "probe")
            try probe.delete(account: "probe")
            return true
        } catch {
            return false
        }
    }()

    @Test(
        "The paired Mac record and paired phones round-trip through the real Keychain; a rewrite updates in place",
        .enabled(if: keychainIsEntitled, "Needs an entitled (signed) test host: errSecMissingEntitlement otherwise")
    )
    func keychainRoundTrip() throws {
        let keychain = CompanionKeychain(service: "com.netmonitor.tests.companion.\(UUID().uuidString)", accessibility: .whenUnlocked)
        let store = PairedMacStore(backing: keychain)
        defer { try? store.forget() }
        let record = PairedMacRecord(
            macID: UUID(), macName: "Mac", macPin: Data(repeating: 4, count: 32), host: nil, port: CompanionLink.defaultPort,
            phoneIdentity: CompanionIdentity().rawRepresentation
        )
        try store.save(record)
        #expect(try PairedMacStore(backing: keychain).load() == record)
        let renamed = PairedMacRecord(
            macID: record.macID, macName: "Renamed", macPin: record.macPin, host: nil, port: record.port, phoneIdentity: record.phoneIdentity
        )
        try store.save(renamed)
        #expect(try store.load() == renamed)
        try store.forget()
        #expect(try store.load() == nil)

        let phones = PairedPhoneStore(backing: keychain)
        let phone = PairedPhone(pin: Data(repeating: 5, count: 32), name: "iPhone", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try phones.add(phone)
        #expect(try phones.all() == [phone])
        try phones.remove(pin: phone.pin)
        #expect(try phones.all().isEmpty)
    }
}

/// The phone's pairing steps without sockets (#590).
@Suite("PhonePairingController")
@MainActor
struct PhonePairingControllerTests {
    private func connecting() -> PhonePairingController {
        let controller = PhonePairingController()
        controller.begin(PhonePairingAttempt(
            kind: .code, secret: Data(count: 16), identity: CompanionIdentity(), host: nil, port: CompanionLink.defaultPort, macName: "Mac"
        ))
        return controller
    }

    @Test("An acceptance before the phone's They Match is out of order and saves nothing")
    func acceptanceBeforeConfirmation() {
        let controller = connecting()
        let session = CompanionVerifiedSession(peerPin: Data(repeating: 1, count: 32), exporter: Data(repeating: 2, count: 32))
        #expect(controller.result(PairResultPayload(accepted: true), session: session) == nil)
        #expect(controller.state == .failed("The Mac answered out of order. Nothing was paired."))
    }

    @Test("A Mac that isn't pairing refuses the hello, and pairing fails with what to do")
    func refusedHello() {
        let controller = connecting()
        let session = CompanionVerifiedSession(peerPin: Data(repeating: 1, count: 32), exporter: Data(repeating: 2, count: 32))
        let hello = ServerHelloPayload(macID: UUID(), macName: "Mac", mode: .refused)
        #expect(controller.hello(hello, session: session, phoneName: "iPhone") == nil)
        #expect(controller.state == .failed("The Mac isn't pairing right now. Click Pair iPhone… on the Mac, then try again."))
    }

    @Test("A link that ends while connecting fails pairing with a reason")
    func linkEnded() {
        let controller = connecting()
        controller.linkEnded()
        #expect(controller.state == .failed("Couldn't reach the Mac, or it didn't accept the code. Check the code and try again."))
        #expect(!controller.isActive)
    }
}
