import Foundation
import Testing
@testable import NetMonitorCore

@Suite("CompanionPairingInvitation")
struct CompanionPairingInvitationTests {
    private let invitation = CompanionPairingInvitation(
        macID: UUID(),
        macName: "Studio Mac",
        macPin: Data(repeating: 0x11, count: 32),
        secret: Data(repeating: 0x22, count: 32),
        host: "studio.local",
        port: 8849
    )

    @Test("The QR text round-trips every field")
    func roundTrip() throws {
        let parsed = try #require(CompanionPairingInvitation(qrText: invitation.qrText))
        #expect(parsed == invitation)
        #expect(invitation.qrText.hasPrefix("netmonitor://pair?v=2&"))
    }

    @Test("Another scheme, another version, a short key or a missing pin is not an invitation")
    func rejectsMalformed() {
        let text = invitation.qrText
        #expect(CompanionPairingInvitation(qrText: text.replacingOccurrences(of: "netmonitor://", with: "https://")) == nil)
        #expect(CompanionPairingInvitation(qrText: text.replacingOccurrences(of: "v=2", with: "v=1")) == nil)
        #expect(CompanionPairingInvitation(qrText: "netmonitor://pair?v=2&m=\(invitation.macID.uuidString)&k=AAAA") == nil)
        #expect(CompanionPairingInvitation(qrText: "not a url") == nil)
    }
}

@Suite("CompanionPairingProof")
struct CompanionPairingProofTests {
    private let secret = Data(repeating: 0x5A, count: 32)
    private let exporter = Data(repeating: 0x01, count: 32)
    private let macPin = Data(repeating: 0x0A, count: 32)
    private let phonePin = Data(repeating: 0x0B, count: 32)

    private func proof(
        role: CompanionPairingProof.Role = .phone,
        kind: CompanionPairingProof.Kind = .qr,
        secret: Data? = nil,
        exporter: Data? = nil
    ) -> Data {
        CompanionPairingProof.make(
            role: role, kind: kind, secret: secret ?? self.secret,
            binding: .init(exporter: exporter ?? self.exporter, macPin: macPin, phonePin: phonePin)
        )
    }

    private func verifies(_ value: Data, role: CompanionPairingProof.Role = .phone, kind: CompanionPairingProof.Kind = .qr) -> Bool {
        CompanionPairingProof.verify(
            value, role: role, kind: kind, secret: secret, binding: .init(exporter: exporter, macPin: macPin, phonePin: phonePin)
        )
    }

    @Test("A proof made with the secret over this session verifies")
    func verifies() {
        #expect(verifies(proof()))
    }

    @Test("A wrong secret, another session, the other role or the other kind fails")
    func rejectsMismatches() {
        #expect(!verifies(proof(secret: Data(repeating: 0x5B, count: 32))))
        #expect(!verifies(proof(exporter: Data(repeating: 0x02, count: 32))))
        #expect(!verifies(proof(role: .mac)))
        #expect(!verifies(proof(kind: .code)))
        #expect(!verifies(Data()))
    }

    @Test("Swapping the pins fails: a proof names which key is the Mac's")
    func bindsPinRoles() {
        let swapped = CompanionPairingProof.make(
            role: .phone, kind: .qr, secret: secret, binding: .init(exporter: exporter, macPin: phonePin, phonePin: macPin)
        )
        #expect(!verifies(swapped))
    }

    private let macNonce = Data(repeating: 0x4D, count: 32)
    private let phoneNonce = Data(repeating: 0x50, count: 32)

    private func code(exporter: Data? = nil, macNonce: Data? = nil, phoneNonce: Data? = nil) -> String {
        CompanionPairingProof.comparisonCode(
            exporter: exporter ?? self.exporter, macPin: macPin, phonePin: phonePin,
            macNonce: macNonce ?? self.macNonce, phoneNonce: phoneNonce ?? self.phoneNonce
        )
    }

    @Test("Both ends get the same 6-digit comparison code; another session gets another")
    func comparisonCode() {
        let code = code()
        #expect(code.count == 7)
        #expect(code.filter(\.isNumber).count == 6)
        #expect(code == self.code())
        let codes = Set((0..<20).map { self.code(exporter: Data(repeating: UInt8($0), count: 32)) })
        #expect(codes.count > 15)
    }

    @Test("Each side's nonce changes the code, so neither can fix it alone")
    func nonceSensitivity() {
        let macSide = Set((0..<20).map { code(macNonce: Data(repeating: UInt8($0), count: 32)) })
        let phoneSide = Set((0..<20).map { code(phoneNonce: Data(repeating: UInt8($0), count: 32)) })
        #expect(macSide.count > 15)
        #expect(phoneSide.count > 15)
    }

    @Test("A commitment binds its nonce and reveals nothing of it")
    func commitment() {
        let nonce = CompanionPairingProof.makeNonce()
        let commitment = CompanionPairingProof.commitment(to: nonce)
        #expect(commitment == CompanionPairingProof.commitment(to: nonce))
        #expect(commitment != CompanionPairingProof.commitment(to: CompanionPairingProof.makeNonce()))
        #expect(commitment.range(of: nonce) == nil)
        #expect(nonce.count == 32)
    }
}
