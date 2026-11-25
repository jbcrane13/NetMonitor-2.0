import Foundation
import Network
import Testing
@testable import NetMonitorCore

@Suite("CompanionSessionGate")
struct CompanionSessionGateTests {
    private let pin = Data(repeating: 0xAB, count: 32)
    private let exporter = Data(repeating: 0x01, count: 32)

    private func facts(
        version: UInt16 = 0x0304,
        pins: [Data]? = nil,
        early: Bool = false,
        exporter: Data?? = .none
    ) -> CompanionSessionFacts {
        CompanionSessionFacts(
            tlsVersion: version,
            peerPins: pins ?? [pin],
            earlyDataAccepted: early,
            exporter: exporter ?? self.exporter
        )
    }

    @Test("A full TLS 1.3 handshake with one pinned peer certificate is verified")
    func verifiesFullHandshake() {
        #expect(facts().verified == CompanionVerifiedSession(peerPin: pin, exporter: exporter))
    }

    @Test("TLS 1.2 is refused")
    func refusesTLS12() {
        #expect(facts(version: 0x0303).verified == nil)
    }

    @Test("A session without a peer certificate, as a resumed one would be, is refused")
    func refusesResumedSession() {
        #expect(facts(pins: []).verified == nil)
    }

    @Test("Accepted early data is refused")
    func refusesEarlyData() {
        #expect(facts(early: true).verified == nil)
    }

    @Test("A missing exporter fails closed")
    func refusesMissingExporter() {
        #expect(facts(exporter: .some(nil)).verified == nil)
    }
}

@Suite("CompanionIdentity")
struct CompanionIdentityTests {
    @Test("An identity survives its raw representation, keeping its pin")
    func rawRoundTrip() throws {
        let identity = CompanionIdentity()
        let restored = try CompanionIdentity(rawRepresentation: identity.rawRepresentation)
        #expect(restored.pin == identity.pin)
        #expect(identity.pin.count == 32)
        #expect(CompanionIdentity().pin != identity.pin)
    }

    @Test("It yields a TLS identity the Security framework accepts")
    func makesSecIdentity() {
        #expect(CompanionIdentity().makeSecIdentity() != nil)
    }
}

/// Real handshakes on 127.0.0.1 through Network.framework (#590).
@Suite("CompanionTLS loopback", .serialized)
struct CompanionTLSLoopbackTests {
    private let mac = CompanionIdentity()
    private let phone = CompanionIdentity()

    @Test("Mutually pinned peers reach a verified TLS 1.3 session with equal exporters")
    func mutualPins() async throws {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { [phone] in $0 == phone.pin })
        defer { harness.stop() }
        let outcome = await harness.connect(client: phone, pinning: mac.pin)
        let server = try #require(await harness.nextServerSession())
        let client = try #require(outcome.session)
        #expect(server.peerPin == phone.pin)
        #expect(client.peerPin == mac.pin)
        #expect(server.exporter == client.exporter)
    }

    @Test("A phone pinning a different Mac key fails the handshake")
    func wrongPin() async throws {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { _ in true })
        defer { harness.stop() }
        let outcome = await harness.connect(client: phone, pinning: CompanionIdentity().pin)
        #expect(outcome.session == nil)
        #expect(await harness.nextServerSession(timeout: .milliseconds(500)) == nil)
    }

    @Test("A client certificate the Mac hasn't pinned is refused")
    func unpinnedClient() async throws {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { [phone] in $0 == phone.pin })
        defer { harness.stop() }
        _ = await harness.connect(client: CompanionIdentity(), pinning: mac.pin)
        #expect(await harness.nextServerSession(timeout: .milliseconds(500)) == nil)
        #expect(await harness.serverFailures() >= 1)
    }

    @Test("A client without a certificate is refused")
    func clientWithoutCertificate() async throws {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { _ in true })
        defer { harness.stop() }
        await harness.connectWithoutCertificate()
        #expect(await harness.nextServerSession(timeout: .milliseconds(500)) == nil)
    }

    @Test("A phone removed from the live pin set is refused on its next connect")
    func revokedPhone() async throws {
        let allowed = PinSet([phone.pin])
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { allowed.contains($0) })
        defer { harness.stop() }
        _ = await harness.connect(client: phone, pinning: mac.pin)
        #expect(await harness.nextServerSession() != nil)
        allowed.removeAll()
        _ = await harness.connect(client: phone, pinning: mac.pin)
        #expect(await harness.nextServerSession(timeout: .milliseconds(500)) == nil)
    }

    @Test("Frames are encrypted on the wire: a relay between the peers never sees the plaintext")
    func encryptedOnTheWire() async throws {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { _ in true })
        defer { harness.stop() }
        let relay = try await RecordingRelay(target: harness.port)
        defer { relay.stop() }
        let sentinel = "SENTINEL-590-\(UUID().uuidString)"
        let frame = try CompanionMessage.error(ErrorPayload(code: "X", message: sentinel)).encodeLengthPrefixed()
        let outcome = await harness.connect(client: phone, pinning: mac.pin, via: relay.port, sending: frame)
        #expect(outcome.session != nil)
        let received = await harness.nextServerBytes()
        #expect(received.range(of: Data(sentinel.utf8)) != nil)
        let wire = await relay.captured()
        #expect(!wire.isEmpty)
        #expect(wire.range(of: Data(sentinel.utf8)) == nil)
        #expect(wire.range(of: Data("protocolVersion".utf8)) == nil)
    }
}
