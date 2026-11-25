import Foundation
import Testing
@testable import NetMonitorCore

@Suite("CompanionTrustGate")
struct CompanionTrustGateTests {
    private let macPin = Data(repeating: 0x0A, count: 32)
    private let pairedPin = Data(repeating: 0x01, count: 32)
    private let newPin = Data(repeating: 0x02, count: 32)
    private let exporter = Data(repeating: 0x33, count: 32)

    private final class Clock: @unchecked Sendable {
        var now: TimeInterval = 1000
    }

    private func gate(_ clock: Clock = Clock()) -> CompanionTrustGate {
        CompanionTrustGate(paired: [pairedPin], now: { clock.now })
    }

    private func request(_ window: CompanionPairingWindow, kind: CompanionPairingProof.Kind = .qr, pin: Data? = nil) -> PairRequestPayload {
        let proof = CompanionPairingProof.make(
            role: .phone, kind: kind, secret: window.secret(for: kind),
            binding: .init(exporter: exporter, macPin: macPin, phonePin: pin ?? newPin)
        )
        return PairRequestPayload(kind: kind, proof: proof, phoneName: "iPhone")
    }

    private func session(_ pin: Data? = nil) -> CompanionVerifiedSession {
        CompanionVerifiedSession(peerPin: pin ?? newPin, exporter: exporter)
    }

    // MARK: Handshake and binding

    @Test("Without a window, only paired pins pass the handshake and bind")
    func pairedOnly() throws {
        let gate = gate()
        #expect(gate.acceptsAtHandshake(pairedPin))
        #expect(!gate.acceptsAtHandshake(newPin))
        let role = try #require(gate.classify(pairedPin))
        guard case .paired(let pin, _) = role else { Issue.record("expected paired")
        return
        }
        #expect(pin == pairedPin)
        #expect(gate.isAuthorized(role, link: UUID()))
        #expect(gate.classify(newPin) == nil)
    }

    @Test("An open window lets unknown pins in as pairing links, at most 8")
    func pairingAdmission() {
        let gate = gate()
        let window = gate.openWindow()
        #expect(gate.acceptsAtHandshake(newPin))
        for _ in 0..<CompanionPairingWindow.maximumConnections {
            #expect(gate.classify(newPin) == .pairing(window: window.generation))
        }
        #expect(gate.classify(newPin) == nil)
        #expect(!gate.acceptsAtHandshake(newPin))
    }

    // MARK: Revocation

    @Test("A revoke between binding and dispatch leaves the link refused")
    func revokeRacingBinding() throws {
        let gate = gate()
        let role = try #require(gate.classify(pairedPin))
        gate.revoke(pairedPin)
        #expect(!gate.isAuthorized(role, link: UUID()))
        #expect(!gate.acceptsAtHandshake(pairedPin))
        #expect(gate.classify(pairedPin) == nil)
    }

    @Test("Trusting a revoked pin again gives a new generation; links bound before stay refused")
    func generations() throws {
        let gate = gate()
        let old = try #require(gate.classify(pairedPin))
        gate.revoke(pairedPin)
        gate.trust(pairedPin)
        let fresh = try #require(gate.classify(pairedPin))
        #expect(!gate.isAuthorized(old, link: UUID()))
        #expect(gate.isAuthorized(fresh, link: UUID()))
    }

    // MARK: Pairing

    @Test("A valid proof consumes the window once and yields the Mac's proof and the comparison code")
    func beginPairing() throws {
        let gate = gate()
        let window = gate.openWindow()
        let role = try #require(gate.classify(newPin))
        let link = UUID()
        let step = try #require(gate.beginPairing(link: link, role: role, request: request(window), session: session(), macPin: macPin))
        #expect(step.phonePin == newPin)
        #expect(CompanionPairingProof.verify(
            step.challenge, role: .mac, kind: .qr, secret: window.secret(for: .qr),
            binding: .init(exporter: exporter, macPin: macPin, phonePin: newPin)
        ))
        #expect(step.comparisonCode == CompanionPairingProof.comparisonCode(exporter: exporter, macPin: macPin, phonePin: newPin))
        #expect(gate.isAuthorized(role, link: link))
        #expect(!gate.isAuthorized(role, link: UUID()))
        #expect(gate.classify(Data(repeating: 9, count: 32)) == nil)
    }

    @Test("A second pairing connection after the window is consumed is refused")
    func secondPairingRefused() throws {
        let gate = gate()
        let window = gate.openWindow()
        let first = try #require(gate.classify(newPin))
        let second = try #require(gate.classify(Data(repeating: 4, count: 32)))
        #expect(gate.beginPairing(link: UUID(), role: first, request: request(window), session: session(), macPin: macPin) != nil)
        let other = Data(repeating: 4, count: 32)
        #expect(gate.beginPairing(link: UUID(), role: second, request: request(window, pin: other), session: session(other), macPin: macPin) == nil)
    }

    @Test("A wrong proof is refused without burning the window")
    func wrongProof() throws {
        let gate = gate()
        let window = gate.openWindow()
        let role = try #require(gate.classify(newPin))
        let bad = PairRequestPayload(kind: .qr, proof: Data(repeating: 0, count: 32), phoneName: "x")
        #expect(gate.beginPairing(link: UUID(), role: role, request: bad, session: session(), macPin: macPin) == nil)
        #expect(gate.beginPairing(link: UUID(), role: role, request: request(window), session: session(), macPin: macPin) != nil)
    }

    @Test("The typed code pairs too, and its proof is not the QR's")
    func typedCode() throws {
        let gate = gate()
        let window = gate.openWindow()
        let role = try #require(gate.classify(newPin))
        let qrProofSentAsCode = PairRequestPayload(kind: .code, proof: request(window).proof, phoneName: "x")
        #expect(gate.beginPairing(link: UUID(), role: role, request: qrProofSentAsCode, session: session(), macPin: macPin) == nil)
        #expect(gate.beginPairing(link: UUID(), role: role, request: request(window, kind: .code), session: session(), macPin: macPin) != nil)
    }

    @Test("A pin that is already paired can't pair again")
    func collision() throws {
        let gate = gate()
        let window = gate.openWindow()
        let role = CompanionLinkRole.pairing(window: window.generation)
        let step = gate.beginPairing(
            link: UUID(), role: role, request: request(window, pin: pairedPin), session: session(pairedPin), macPin: macPin
        )
        #expect(step == nil)
    }

    @Test("After the deadline, or once closed, a window neither admits nor pairs")
    func deadlineAndClose() throws {
        let clock = Clock()
        let gate = gate(clock)
        let window = gate.openWindow()
        let role = try #require(gate.classify(newPin))
        clock.now += CompanionPairingWindow.lifetime
        #expect(gate.classify(newPin) == nil)
        #expect(!gate.isAuthorized(role, link: UUID()))
        #expect(gate.beginPairing(link: UUID(), role: role, request: request(window), session: session(), macPin: macPin) == nil)

        let reopened = gate.openWindow()
        let fresh = try #require(gate.classify(newPin))
        gate.closeWindow()
        #expect(!gate.isAuthorized(fresh, link: UUID()))
        #expect(gate.beginPairing(link: UUID(), role: fresh, request: request(reopened), session: session(), macPin: macPin) == nil)
    }

    @Test("Opening a new window shuts the old one")
    func reopenShutsOld() throws {
        let gate = gate()
        let old = gate.openWindow()
        let oldRole = try #require(gate.classify(newPin))
        _ = gate.openWindow()
        #expect(!gate.isAuthorized(oldRole, link: UUID()))
        #expect(gate.beginPairing(link: UUID(), role: oldRole, request: request(old), session: session(), macPin: macPin) == nil)
    }

    @Test("Once trusted after pairing, the new phone binds as paired")
    func trustAfterPairing() throws {
        let gate = gate()
        let window = gate.openWindow()
        let role = try #require(gate.classify(newPin))
        _ = try #require(gate.beginPairing(link: UUID(), role: role, request: request(window), session: session(), macPin: macPin))
        gate.trust(newPin)
        guard case .paired? = gate.classify(newPin) else { Issue.record("expected paired")
        return
        }
    }
}
