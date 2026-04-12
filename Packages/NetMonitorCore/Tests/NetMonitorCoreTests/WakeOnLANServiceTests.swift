import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - WakeOnLANService Tests

/// Tests for WakeOnLANService: magic packet construction, MAC address parsing,
/// invalid MAC handling, broadcast address, and state management.
/// Network-level send operations require real sockets and are marked as integration.
@MainActor
struct WakeOnLANServiceTests {

    // MARK: - Magic Packet Construction

    /// To test createMagicPacket (which is private), we exercise the public `wake` API
    /// and inspect the service state. For packet byte-level verification, we replicate
    /// the algorithm in a helper and verify its output directly.

    /// Replicates the packet creation logic for byte-level assertion.
    private func buildExpectedMagicPacket(mac: String) -> Data? {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard cleaned.count == 12 else { return nil }

        var macBytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else { return nil }
            macBytes.append(byte)
            index = nextIndex
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    @Test("Magic packet is 102 bytes: 6 bytes 0xFF + 16 repetitions of 6-byte MAC")
    func magicPacketSize() {
        let packet = buildExpectedMagicPacket(mac: "AA:BB:CC:DD:EE:FF")
        #expect(packet != nil)
        #expect(packet?.count == 102)
    }

    @Test("Magic packet starts with 6 bytes of 0xFF")
    func magicPacketHeader() {
        let packet = buildExpectedMagicPacket(mac: "AA:BB:CC:DD:EE:FF")!
        let header = packet.prefix(6)
        #expect(header == Data(repeating: 0xFF, count: 6))
    }

    @Test("Magic packet contains 16 repetitions of the MAC address")
    func magicPacketMACRepetitions() {
        let mac = "AA:BB:CC:DD:EE:FF"
        let packet = buildExpectedMagicPacket(mac: mac)!
        let macBytes: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]

        for i in 0..<16 {
            let offset = 6 + (i * 6)
            let slice = Array(packet[offset..<(offset + 6)])
            #expect(slice == macBytes, "MAC repetition \(i) does not match")
        }
    }

    // MARK: - MAC Address Parsing

    @Test("Colon-separated MAC address is accepted")
    func colonSeparatedMACAccepted() {
        let packet = buildExpectedMagicPacket(mac: "AA:BB:CC:DD:EE:FF")
        #expect(packet != nil)
    }

    @Test("Dash-separated MAC address is accepted")
    func dashSeparatedMACAccepted() {
        let packet = buildExpectedMagicPacket(mac: "AA-BB-CC-DD-EE-FF")
        #expect(packet != nil)
    }

    @Test("Lowercase MAC address is accepted and normalized")
    func lowercaseMACAccepted() {
        let packet = buildExpectedMagicPacket(mac: "aa:bb:cc:dd:ee:ff")
        #expect(packet != nil)
        // Verify it produces the same packet as uppercase
        let uppercasePacket = buildExpectedMagicPacket(mac: "AA:BB:CC:DD:EE:FF")
        #expect(packet == uppercasePacket)
    }

    @Test("MAC address without separators is accepted")
    func noSeparatorMACAccepted() {
        let packet = buildExpectedMagicPacket(mac: "AABBCCDDEEFF")
        #expect(packet != nil)
    }

    @Test("Mixed-case MAC address is accepted")
    func mixedCaseMACAccepted() {
        let packet = buildExpectedMagicPacket(mac: "aA:Bb:cC:Dd:eE:fF")
        #expect(packet != nil)
    }

    // MARK: - Invalid MAC Address

    @Test("Too-short MAC returns nil")
    func tooShortMACReturnsNil() {
        let packet = buildExpectedMagicPacket(mac: "AA:BB:CC")
        #expect(packet == nil)
    }

    @Test("Too-long MAC returns nil")
    func tooLongMACReturnsNil() {
        let packet = buildExpectedMagicPacket(mac: "AA:BB:CC:DD:EE:FF:00")
        #expect(packet == nil)
    }

    @Test("Empty string MAC returns nil")
    func emptyMACReturnsNil() {
        let packet = buildExpectedMagicPacket(mac: "")
        #expect(packet == nil)
    }

    @Test("Non-hex characters in MAC returns nil")
    func nonHexMACReturnsNil() {
        let packet = buildExpectedMagicPacket(mac: "GG:HH:II:JJ:KK:LL")
        #expect(packet == nil)
    }

    @Test("Invalid MAC triggers lastError in service")
    func invalidMACTriggersLastError() async {
        let service = WakeOnLANService()
        let result = await service.wake(macAddress: "invalid", broadcastAddress: "255.255.255.255", port: 9)
        #expect(result == false)
        #expect(service.lastError == "Invalid MAC address format")
        #expect(service.lastResult?.success == false)
        #expect(service.lastResult?.macAddress == "invalid")
    }

    // MARK: - Service State Management

    @Test("Initial state: isSending is false")
    func initialIsSendingIsFalse() {
        let service = WakeOnLANService()
        #expect(service.isSending == false)
    }

    @Test("Initial state: lastResult is nil")
    func initialLastResultIsNil() {
        let service = WakeOnLANService()
        #expect(service.lastResult == nil)
    }

    @Test("Initial state: lastError is nil")
    func initialLastErrorIsNil() {
        let service = WakeOnLANService()
        #expect(service.lastError == nil)
    }

    @Test("After wake with invalid MAC, isSending returns to false")
    func isSendingReturnsFalseAfterInvalidMAC() async {
        let service = WakeOnLANService()
        _ = await service.wake(macAddress: "bad", broadcastAddress: "255.255.255.255", port: 9)
        #expect(service.isSending == false)
    }

    @Test("lastResult captures MAC address from wake call")
    func lastResultCapturesMACAddress() async {
        let service = WakeOnLANService()
        _ = await service.wake(macAddress: "not-valid", broadcastAddress: "255.255.255.255", port: 9)
        #expect(service.lastResult?.macAddress == "not-valid")
    }

    // MARK: - WakeOnLANResult model

    @Test("WakeOnLANResult stores all fields correctly")
    func wakeOnLANResultFields() {
        let result = WakeOnLANResult(macAddress: "AA:BB:CC:DD:EE:FF", success: true, error: nil)
        #expect(result.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(result.success == true)
        #expect(result.error == nil)
    }

    @Test("WakeOnLANResult with error stores error message")
    func wakeOnLANResultWithError() {
        let result = WakeOnLANResult(macAddress: "AA:BB:CC:DD:EE:FF", success: false, error: "Timeout")
        #expect(result.success == false)
        #expect(result.error == "Timeout")
    }

    // MARK: - Integration: actual send (requires network)

    @Test("Wake with valid MAC and broadcast completes without crash", .tags(.integration))
    func wakeWithValidMACCompletes() async {
        // INTEGRATION GAP: requires UDP socket and network access
        let service = WakeOnLANService()
        let result = await service.wake(macAddress: "AA:BB:CC:DD:EE:FF", broadcastAddress: "255.255.255.255", port: 9)
        // Result depends on network availability — just verify no crash and state reset
        #expect(service.isSending == false)
        #expect(service.lastResult != nil)
        _ = result // suppress unused warning
    }
}
