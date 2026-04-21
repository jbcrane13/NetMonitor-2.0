import Testing
import Foundation
@testable import NetMonitorCore

// TODO: testability — WakeOnLANService.wake() uses NWConnection to send packets, which is
// difficult to mock without refactoring the service to inject a packet-sender protocol.
// These tests focus on the pure packet construction logic (createMagicPacket, hexStringToBytes)
// and observable state management. Actual UDP sending is integration-level and deferred.

@MainActor
struct WakeOnLANServiceTests {

    // MARK: - Magic packet construction: format validation

    @Test
    func magicPacketHasCorrectStructure() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")

        // Magic packet: 6 bytes 0xFF + 16 × 6-byte MAC = 6 + 96 = 102 bytes
        #expect(packet != nil)
        #expect(packet!.count == 102)
    }

    @Test
    func magicPacketPreambleIsAllFF() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")!

        // First 6 bytes must be 0xFF
        let preamble = packet.prefix(6)
        #expect(preamble.allSatisfy { $0 == 0xFF })
    }

    @Test
    func magicPacketRepeatsMACAddressExactly16Times() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "11:22:33:44:55:66")!

        // Expected MAC bytes
        let expectedMAC: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66]

        // Skip first 6 FF bytes, then check 16 repetitions of MAC
        let payload = Array(packet.dropFirst(6))
        for i in 0..<16 {
            let offset = i * 6
            let macSlice = Array(payload[offset..<offset + 6])
            #expect(macSlice == expectedMAC, "Repetition \(i+1) of MAC should match")
        }
    }

    // MARK: - MAC address format parsing

    @Test
    func macWithColonDelimiterParses() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")
        #expect(packet != nil)
    }

    @Test
    func macWithDashDelimiterParses() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA-BB-CC-DD-EE-FF")
        #expect(packet != nil)
    }

    @Test
    func macWithoutDelimiterParses() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AABBCCDDEEFF")
        #expect(packet != nil)
    }

    @Test
    func macWithMixedDelimitersAndLowercaseParses() {
        let service = WakeOnLANService()
        // Internal implementation uppercases and strips delimiters, so lowercase + colon works
        let packet = service.createMagicPacket(macAddress: "aa:bb:cc:dd:ee:ff")
        #expect(packet != nil)
    }

    @Test
    func allThreeMacFormatsBuildIdenticalPackets() {
        let service = WakeOnLANService()
        let packet1 = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")!
        let packet2 = service.createMagicPacket(macAddress: "AA-BB-CC-DD-EE-FF")!
        let packet3 = service.createMagicPacket(macAddress: "AABBCCDDEEFF")!

        #expect(packet1 == packet2, "Colon and dash formats should produce identical packets")
        #expect(packet1 == packet3, "Colon and no-delimiter formats should produce identical packets")
    }

    // MARK: - Invalid MAC addresses

    @Test
    func macTooShortReturnsNil() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE")
        #expect(packet == nil)
    }

    @Test
    func macTooLongReturnsNil() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF:00")
        #expect(packet == nil)
    }

    @Test
    func macWithNonHexCharactersReturnsNil() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "GG:HH:CC:DD:EE:FF")
        #expect(packet == nil)
    }

    @Test
    func macWithInvalidCharacterInMiddleReturnsNil() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:ZZ")
        #expect(packet == nil)
    }

    @Test
    func emptyMACReturnsNil() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "")
        #expect(packet == nil)
    }

    // MARK: - Hex string parsing

    @Test
    func hexStringToBytesParsesSimpleHex() {
        let service = WakeOnLANService()
        let bytes = service.hexStringToBytes("AABBCCDDEE")
        #expect(bytes != nil)
        #expect(bytes?.count == 5)
        #expect(bytes == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
    }

    @Test
    func hexStringToBytesCaseSensitiveButUppercased() {
        let service = WakeOnLANService()
        // The implementation uppercases input, so lowercase hex should work via uppercasing
        let bytes = service.hexStringToBytes("aabbcc")
        #expect(bytes != nil)
        #expect(bytes == [0xAA, 0xBB, 0xCC])
    }

    @Test
    func hexStringToBytesRejectsOddLength() {
        let service = WakeOnLANService()
        let bytes = service.hexStringToBytes("AAB")
        #expect(bytes == nil)
    }

    @Test
    func hexStringToBytesRejectsInvalidHex() {
        let service = WakeOnLANService()
        let bytes = service.hexStringToBytes("GGHHCC")
        #expect(bytes == nil)
    }

    @Test
    func hexStringToBytesEmptyStringReturnsEmptyArray() {
        let service = WakeOnLANService()
        let bytes = service.hexStringToBytes("")
        #expect(bytes != nil)
        #expect(bytes!.isEmpty)
    }

    // MARK: - Observable state management

    @Test
    func initialStateHasNoResult() {
        let service = WakeOnLANService()
        #expect(service.lastResult == nil)
        #expect(!service.isSending)
        #expect(service.lastError == nil)
    }

    @Test
    func invalidMACUpdatesErrorStateWithoutSending() async {
        let service = WakeOnLANService()
        let success = await service.wake(macAddress: "INVALID", broadcastAddress: "255.255.255.255", port: 9)

        #expect(!success)
        #expect(!service.isSending)
        #expect(service.lastError != nil)
        #expect(service.lastError?.contains("Invalid MAC") ?? false)
    }

    @Test
    func resultTracksAttemptMACAddress() async {
        let service = WakeOnLANService()
        _ = await service.wake(macAddress: "INVALID", broadcastAddress: "255.255.255.255", port: 9)

        #expect(service.lastResult?.macAddress == "INVALID")
    }

    @Test
    func resultMarksInvalidMACAsFailure() async {
        let service = WakeOnLANService()
        _ = await service.wake(macAddress: "XX:YY:ZZ:AA:BB:CC", broadcastAddress: "255.255.255.255", port: 9)

        #expect(service.lastResult?.success == false)
    }

    // MARK: - MAC format edge cases

    @Test
    func macAddressWithMixedCaseParsesCorrectly() {
        let service = WakeOnLANService()
        let packet1 = service.createMagicPacket(macAddress: "Aa:Bb:Cc:Dd:Ee:Ff")
        let packet2 = service.createMagicPacket(macAddress: "AA:BB:CC:DD:EE:FF")
        #expect(packet1 == packet2)
    }

    @Test
    func successfulMagicPacketCreationProducesExactly102Bytes() {
        let service = WakeOnLANService()
        for mac in ["AA:BB:CC:DD:EE:FF", "00:11:22:33:44:55", "FF:FF:FF:FF:FF:FF"] {
            let packet = service.createMagicPacket(macAddress: mac)
            #expect(packet?.count == 102, "MAC \(mac) should produce 102-byte packet")
        }
    }

    @Test
    func macWithLeadingZerosParses() {
        let service = WakeOnLANService()
        let packet = service.createMagicPacket(macAddress: "00:00:00:00:00:01")
        #expect(packet != nil)
        #expect(packet?.count == 102)
    }
}
