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
    private func makeService(_ backing: InMemoryCompanionSecretStore = InMemoryCompanionSecretStore()) -> (MacConnectionService, PairedMacStore) {
        let store = PairedMacStore(backing: backing)
        let service = MacConnectionService(insightClient: CompanionInsightClient(send: { _ in false }), macStore: store)
        return (service, store)
    }

    private func start(_ fake: FakeCompanionMac, in service: MacConnectionService) async throws -> DiscoveredMac {
        let port = try await fake.start()
        let mac = DiscoveredMac(id: "fake", name: fake.name, macID: fake.macID, protocolVersion: CompanionMessage.currentProtocolVersion)
        let endpoint = try NWEndpoint.hostPort(host: .ipv4(.loopback), port: #require(NWEndpoint.Port(rawValue: port)))
        service.addDiscoveredMacForTesting(mac, endpoint: endpoint)
        return mac
    }

    @Test("Typing the Mac's code pairs: same comparison code, the Mac's key saved, then a paired link")
    func pairsWithTypedCode() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, confirmDelay: .milliseconds(600))
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)

        service.pair(code: code, with: mac)
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        guard case .comparing(let shown, _) = service.pairingState else {
            Issue.record("expected comparing, got \(service.pairingState)")
            return
        }
        #expect(shown.count == 7)
        #expect(try store.load() == nil)

        // The user says the codes match before the Mac's verdict arrives: the phone waits.
        service.confirmComparison(true)
        #expect(service.pairingState == .waitingForMac(code: shown, macName: "Test Mac"))
        #expect(try store.load() == nil)
        await waitUntil({ service.connectionState.isConnected }, timeout: .seconds(5))
        #expect(service.pairingState == .paired(macName: "Test Mac"))
        let record = try #require(try store.load())
        #expect(record.macPin == fake.identity.pin)
        #expect(record.macID == fake.macID)
        #expect(service.isPaired(with: mac))
    }

    @Test("Scanning the QR pairs too, pinning the key the QR names")
    func pairsWithQR() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let port = try await fake.start()
        service.pair(with: fake.invitation(port: port))
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        // The Mac accepts first; the phone still waits for its own user.
        try await Task.sleep(for: .milliseconds(600))
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
        await waitUntil({
            if case .failed = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        #expect(try store.load() == nil)
        #expect(!service.connectionState.isConnected)
    }

    @Test("A wrong code is refused by the Mac and nothing is saved")
    func wrongCode() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: .random(), with: mac)
        await waitUntil({
            if case .failed = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        if case .failed = service.pairingState {} else {
            Issue.record("expected failed, got \(service.pairingState)")
        }
        #expect(try store.load() == nil)
    }

    @Test("Don't Pair on the Mac (the codes didn't match) saves nothing on the phone")
    func rejectedOnMac() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code, confirmation: .reject)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        service.confirmComparison(true)
        await waitUntil({ service.pairingState == .failed("Cancelled on the Mac.") }, timeout: .seconds(5))
        #expect(service.pairingState == .failed("Cancelled on the Mac."))
        #expect(try store.load() == nil)
    }

    @Test("Don't Match on the phone saves nothing, even when the Mac accepts")
    func codesDifferOnPhone() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        try await Task.sleep(for: .milliseconds(600))
        service.confirmComparison(false)
        if case .failed = service.pairingState {} else {
            Issue.record("expected failed, got \(service.pairingState)")
        }
        #expect(try store.load() == nil)
        #expect(service.pairedMac == nil)
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
        await waitUntil({
            if case .failed = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        #expect(service.pairingState == .failed("The Mac's answer didn't match what it promised. Nothing was paired."))
        #expect(try store.load() == nil)
    }

    @Test("A Mac's hello without a commitment gets no pairing request")
    func helloWithoutCommitment() throws {
        var attempt = PhonePairingAttempt(
            kind: .code, secret: Data(count: 16), identity: CompanionIdentity(), host: nil, port: 8849, macName: "Mac"
        )
        let session = CompanionVerifiedSession(peerPin: Data(repeating: 1, count: 32), exporter: Data(repeating: 2, count: 32))
        let hello = ServerHelloPayload(macID: UUID(), macName: "Mac", mode: .pairing)
        #expect(PhonePairingFlow.pairRequest(for: &attempt, hello: hello, session: session, phoneName: "iPhone") == nil)
    }

    @Test("A phone the Mac removed gets a terminal 'pair again' state and stops reconnecting")
    func revokedOnMac() async throws {
        let fake = try FakeCompanionMac()
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        // No pairing window, and a pairing the Mac no longer trusts.
        fake.gate.closeWindow()
        try store.save(PairedMacRecord(
            macID: fake.macID, macName: fake.name, macPin: fake.identity.pin, host: nil, port: 8849,
            phoneIdentity: CompanionIdentity().rawRepresentation
        ))
        let reloaded = MacConnectionService(insightClient: CompanionInsightClient(send: { _ in false }), macStore: store)
        try reloaded.addDiscoveredMacForTesting(mac, endpoint: #require(Self.endpoint(of: service, mac)))
        reloaded.connect(to: mac)
        await waitUntil({ reloaded.linkProblem == .notRecognized }, timeout: .seconds(5))
        #expect(reloaded.linkProblem == .notRecognized)
        let attempts = fake.connectionCount
        try await Task.sleep(for: .seconds(2))
        #expect(fake.connectionCount == attempts)
        #expect(!reloaded.connectionState.isConnected)
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

    @Test("Forget This Mac tells the Mac, deletes the key, and disconnects")
    func forget() async throws {
        let code = CompanionPairingCode.random()
        let fake = try FakeCompanionMac(code: code)
        defer { fake.stop() }
        let (service, store) = makeService()
        let mac = try await start(fake, in: service)
        service.pair(code: code, with: mac)
        await waitUntil({
            if case .comparing = service.pairingState {
                true
            } else {
                false
            }
        }, timeout: .seconds(5))
        service.confirmComparison(true)
        await waitUntil({ service.connectionState.isConnected }, timeout: .seconds(6))
        await service.forgetMac()
        #expect(try store.load() == nil)
        #expect(service.pairedMac == nil)
        #expect(!service.connectionState.isConnected)
        await waitUntil({ fake.received.contains("unpair") }, timeout: .seconds(3))
        #expect(fake.received.contains("unpair"))
    }

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
        "The paired Mac record and paired phones round-trip through the real Keychain",
        .enabled(if: keychainIsEntitled, "Needs an entitled (signed) test host: errSecMissingEntitlement otherwise")
    )
    func keychainRoundTrip() throws {
        let keychain = CompanionKeychain(service: "com.netmonitor.tests.companion.\(UUID().uuidString)", accessibility: .whenUnlocked)
        let store = PairedMacStore(backing: keychain)
        defer { try? store.forget() }
        let record = PairedMacRecord(
            macID: UUID(), macName: "Mac", macPin: Data(repeating: 4, count: 32), host: nil, port: 8849,
            phoneIdentity: CompanionIdentity().rawRepresentation
        )
        try store.save(record)
        #expect(try PairedMacStore(backing: keychain).load() == record)
        try store.forget()
        #expect(try store.load() == nil)

        let phones = PairedPhoneStore(backing: keychain)
        let phone = PairedPhone(pin: Data(repeating: 5, count: 32), name: "iPhone", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try phones.add(phone)
        #expect(try phones.all() == [phone])
        try phones.remove(pin: phone.pin)
        #expect(try phones.all().isEmpty)
    }

    private static func endpoint(of service: MacConnectionService, _ mac: DiscoveredMac) -> NWEndpoint? {
        service.endpointForTesting(mac)
    }
}
