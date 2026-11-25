import Foundation
import Testing
@testable import NetMonitorCore

@Suite("CompanionPairingCode")
struct CompanionPairingCodeTests {
    private let vector = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])

    @Test("Encodes 125 bits as 25 Crockford digits, most significant first, then the mod-37 check")
    func knownAnswer() throws {
        let code = try #require(CompanionPairingCode(secret: vector))
        #expect(code.canonical == "14D2PF2DBSQQG28T5CY4TQKFFK")
        #expect(code.display == "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K")
    }

    @Test("The largest 125-bit value is all Z with check H")
    func maximumValue() throws {
        var bytes = Data(repeating: 0xFF, count: 16)
        bytes[0] = 0x1F
        let code = try #require(CompanionPairingCode(secret: bytes))
        #expect(code.canonical == String(repeating: "Z", count: 25) + "H")
    }

    @Test("A secret with any of the top 3 bits set is not a 125-bit code")
    func rejectsWideSecret() {
        var bytes = vector
        bytes[0] = 0x20
        #expect(CompanionPairingCode(secret: bytes) == nil)
        #expect(CompanionPairingCode(secret: Data(count: 15)) == nil)
    }

    @Test("Typed input: any case, dashes and spaces ignored, I/L read as 1 and O as 0")
    func parsesTypedInput() throws {
        let typed = "14d2p f2dbs-qqg28 t5cy4 tqkff k"
        let code = try #require(CompanionPairingCode(typed: typed))
        #expect(code.secret == vector)
        let lookalikes = try #require(CompanionPairingCode(typed: "OOOOOOOOOOOOOOOOOOOOOOOOO0"))
        #expect(lookalikes.secret == Data(count: 16))
        #expect(CompanionPairingCode(typed: "I4D2PF2DBSQQG28T5CY4TQKFFK")?.secret == vector)
    }

    @Test("A typo fails the check symbol, and so does a wrong length or symbol")
    func rejectsTypos() {
        #expect(CompanionPairingCode(typed: "14D2PF2DBSQQG28T5CY4TQKFGK") == nil)
        #expect(CompanionPairingCode(typed: "14D2PF2DBSQQG28T5CY4TQKFF") == nil)
        #expect(CompanionPairingCode(typed: "14D2PF2DBSQQG28T5CY4TQKFFKK") == nil)
        #expect(CompanionPairingCode(typed: "14D2PF2DBSQQG28T5CY4TQKFUK") == nil)
    }

    @Test("Random codes carry 125 bits and round-trip through their typed form")
    func randomRoundTrip() throws {
        for _ in 0..<50 {
            let code = CompanionPairingCode.random()
            #expect(code.secret.count == 16)
            #expect(code.secret[0] & 0xE0 == 0)
            #expect(CompanionPairingCode(typed: code.display)?.secret == code.secret)
        }
    }
}
