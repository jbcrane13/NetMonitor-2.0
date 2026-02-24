import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for ICMPSocket pure static functions: buildEchoRequest, icmpChecksum, parseResponse.
/// These are all nonisolated static methods — no network, no socket, no entitlements needed.
@Suite("ICMPSocket — Pure Functions")
struct ICMPSocketTests {

    // MARK: - buildEchoRequest

    @Test("Packet length = 8 byte header + payloadSize")
    func packetLengthEqualsHeaderPlusPayload() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, payloadSize: 56)
        #expect(packet.count == 64, "8 header + 56 payload = 64 bytes")
    }

    @Test("Type byte is 8 (Echo Request)")
    func packetTypeIsEchoRequest() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1)
        #expect(packet[0] == 8, "ICMP Echo Request type is 8")
    }

    @Test("Code byte is 0")
    func packetCodeIsZero() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1)
        #expect(packet[1] == 0)
    }

    @Test("Sequence number is stored big-endian at bytes 6-7")
    func sequenceStoredBigEndian() {
        let seq: UInt16 = 0x1234
        let packet = ICMPSocket.buildEchoRequest(sequence: seq)
        let high = UInt16(packet[6]) << 8
        let low  = UInt16(packet[7])
        #expect((high | low) == seq)
    }

    @Test("Sequence 0x0001 round-trips correctly")
    func sequence1RoundTrips() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1)
        let seq = UInt16(packet[6]) << 8 | UInt16(packet[7])
        #expect(seq == 1)
    }

    @Test("Identifier is stored big-endian at bytes 4-5")
    func identifierStoredBigEndian() {
        let id: UInt16 = 0xABCD
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, identifier: id)
        let high = UInt16(packet[4]) << 8
        let low  = UInt16(packet[5])
        #expect((high | low) == id)
    }

    @Test("Checksum bytes are non-zero for non-empty packet")
    func checksumIsNonZero() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, payloadSize: 56)
        let checksum = UInt16(packet[2]) << 8 | UInt16(packet[3])
        #expect(checksum != 0, "A valid ICMP packet must have a non-zero checksum")
    }

    @Test("Checksum verification: applying checksum to packet yields zero")
    func checksumVerifiesCorrectly() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 42, payloadSize: 56)
        // RFC 1071: checksum of packet including embedded checksum should be 0xFFFF (or 0 after NOT)
        let sum = ICMPSocket.icmpChecksum(packet)
        #expect(sum == 0, "Re-checksumming a correctly checksummed packet should yield 0")
    }

    @Test("Payload is filled with repeating 0x00-0xFF pattern")
    func payloadFilledWithPattern() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, payloadSize: 8)
        // Payload starts at byte 8; pattern is i & 0xFF
        for i in 0..<8 {
            #expect(packet[8 + i] == UInt8(i & 0xFF))
        }
    }

    @Test("Zero-size payload produces 8-byte packet")
    func zeroPayloadProduces8Bytes() {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, payloadSize: 0)
        #expect(packet.count == 8)
    }

    // MARK: - icmpChecksum

    @Test("Checksum of all-zero buffer is 0xFFFF")
    func checksumOfZeroBufferIsFFFF() {
        let zeroes = [UInt8](repeating: 0, count: 8)
        #expect(ICMPSocket.icmpChecksum(zeroes) == 0xFFFF)
    }

    @Test("Checksum of empty buffer is 0xFFFF")
    func checksumOfEmptyIsFFFF() {
        #expect(ICMPSocket.icmpChecksum([]) == 0xFFFF)
    }

    @Test("Checksum handles odd-length data (trailing byte padded)")
    func checksumHandlesOddLength() {
        // Should not crash and should produce a valid value
        let odd = [UInt8](repeating: 0xFF, count: 5)
        let result = ICMPSocket.icmpChecksum(odd)
        #expect(result != 0xFFFF, "Non-zero input should not yield 0xFFFF")
    }

    @Test("Checksum is deterministic for the same input")
    func checksumIsDeterministic() {
        let data: [UInt8] = [0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01]
        let c1 = ICMPSocket.icmpChecksum(data)
        let c2 = ICMPSocket.icmpChecksum(data)
        #expect(c1 == c2)
    }

    // MARK: - parseResponse — Echo Reply

    @Test("parseResponse: Echo Reply (type 0) extracts sequence number")
    func parseEchoReplyExtractsSequence() {
        // Simulate a raw buffer without IP header (starts directly with ICMP)
        var buf = [UInt8](repeating: 0, count: 64)
        buf[0] = 0  // Echo Reply type
        buf[1] = 0  // code
        // Sequence at bytes 6-7 (big-endian)
        let seq: UInt16 = 7
        buf[6] = UInt8(seq >> 8)
        buf[7] = UInt8(seq & 0xFF)

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "8.8.8.8", rtt: 12.5)
        if case .echoReply(let s) = response.kind {
            #expect(s == seq)
        } else {
            Issue.record("Expected echoReply, got \(response.kind)")
        }
        #expect(response.sourceIP == "8.8.8.8")
        #expect(response.rtt == 12.5)
    }

    @Test("parseResponse: Time Exceeded (type 11) extracts original sequence")
    func parseTimeExceededExtractsOriginalSeq() {
        // Minimum buffer: 8 (ICMP hdr) + 20 (inner IP) + 8 (inner ICMP) = 36 bytes
        var buf = [UInt8](repeating: 0, count: 64)
        buf[0] = 11 // Time Exceeded
        buf[1] = 0
        // Original sequence at offset 8 + 20 + 6 = 34
        let origSeq: UInt16 = 42
        buf[34] = UInt8(origSeq >> 8)
        buf[35] = UInt8(origSeq & 0xFF)

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "10.0.0.1", rtt: 3.2)
        if case .timeExceeded(let routerIP, let s) = response.kind {
            #expect(s == origSeq)
            #expect(routerIP == "10.0.0.1")
        } else {
            Issue.record("Expected timeExceeded, got \(response.kind)")
        }
    }

    @Test("parseResponse: unknown type returns .error")
    func parseUnknownTypeReturnsError() {
        var buf = [UInt8](repeating: 0, count: 64)
        buf[0] = 99 // unknown ICMP type
        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: nil, rtt: 0)
        if case .error = response.kind { } else {
            Issue.record("Expected error for unknown ICMP type, got \(response.kind)")
        }
    }

    @Test("parseResponse: buffer too short returns .error")
    func parseTooShortBufferReturnsError() {
        let buf = [UInt8](repeating: 0, count: 4) // less than 8
        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: nil, rtt: 0)
        if case .error = response.kind { } else {
            Issue.record("Expected error for too-short buffer, got \(response.kind)")
        }
    }

    @Test("parseResponse: skips IPv4 header when IP version nibble is 4")
    func parseSkipsIPv4Header() {
        // Craft a buffer with a 20-byte IPv4 header followed by an Echo Reply
        var buf = [UInt8](repeating: 0, count: 84)
        buf[0] = 0x45  // IPv4, header length = 5*4 = 20 bytes
        let icmpStart = 20
        buf[icmpStart + 0] = 0  // Echo Reply
        buf[icmpStart + 1] = 0
        let seq: UInt16 = 99
        buf[icmpStart + 6] = UInt8(seq >> 8)
        buf[icmpStart + 7] = UInt8(seq & 0xFF)

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "1.2.3.4", rtt: 5.0)
        if case .echoReply(let s) = response.kind {
            #expect(s == seq, "Should extract sequence after skipping 20-byte IP header")
        } else {
            Issue.record("Expected echoReply after IP header skip, got \(response.kind)")
        }
    }

    // MARK: - Parameterized: buildEchoRequest with various payload sizes

    @Test("buildEchoRequest: various payload sizes produce correct total lengths",
          arguments: [0, 1, 8, 56, 128])
    func buildEchoRequestLengths(payloadSize: Int) {
        let packet = ICMPSocket.buildEchoRequest(sequence: 1, payloadSize: payloadSize)
        #expect(packet.count == 8 + payloadSize)
    }
}
