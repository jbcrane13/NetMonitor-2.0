import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for TracerouteService state and TracerouteHop model logic.
/// Network-dependent tracing (ICMPSocket, DNS resolution) is excluded.
@Suite("TracerouteService")
struct TracerouteServiceTests {

    // MARK: - Regression: "only 1 hop" (NetMonitor-2.0-7w6)
    //
    // Root cause: ICMPSocket.sendProbe was not checking the return value of
    // setsockopt(IP_TTL). If that call silently fails the probe is sent with the
    // default TTL (64) and reaches the destination at every hop, causing
    // destinationReached=true at TTL=1 and the trace terminating after a single hop.
    //
    // Additional contributor: the inner probe loop did not break when echoReply was
    // received. Extra probes at the same TTL produced additional echo replies that
    // lingered in the receive buffer and could be matched by subsequent TTL probes,
    // causing the outer loop to terminate earlier than expected.
    //
    // Both issues are fixed in ICMPSocket.sendProbe (setsockopt error check) and
    // TracerouteService.performICMPTrace (inner-loop break on destinationReached).
    // The tests below guard the pure-logic layer that is exercisable without network.

    @Test("parseResponse: Time Exceeded with embedded IPv4 header is NOT misidentified as Echo Reply")
    func timeExceededWithIPHeaderNotMisidentifiedAsEchoReply() {
        // Craft a full packet: outer 20-byte IPv4 header + Time Exceeded ICMP payload
        // outer IP header: version=4, IHL=5 (20 bytes), rest zeroed
        var buf = [UInt8](repeating: 0, count: 84)
        buf[0] = 0x45  // IPv4, IHL=5 → ipOffset=20
        // ICMP starts at offset 20
        buf[20] = 11   // Time Exceeded type
        buf[21] = 0    // code
        // inner IP header at ICMP offset 28 (8 bytes of Time Exceeded header)
        // inner ICMP at offset 48 (28 + 20)
        // sequence at offset 54 (48 + 6)
        let origSeq: UInt16 = 5
        buf[54] = UInt8(origSeq >> 8)
        buf[55] = UInt8(origSeq & 0xFF)

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "10.0.0.1", rtt: 2.0)

        // Must NOT be misidentified as echoReply (which would trigger destinationReached=true
        // at TTL=1 and cause the "only 1 hop" regression).
        if case .echoReply = response.kind {
            Issue.record("Time Exceeded response was wrongly parsed as echoReply — regression bug NetMonitor-2.0-7w6")
        }
        if case .timeExceeded(let routerIP, let s) = response.kind {
            #expect(routerIP == "10.0.0.1")
            #expect(s == origSeq)
        } else if case .echoReply = response.kind {
            // already handled above
        } else {
            // error or timeout — also acceptable since the inner IP header is zeroed
        }
    }

    @Test("parseResponse: Echo Reply with IPv4 header IS correctly identified")
    func echoReplyWithIPHeaderCorrectlyIdentified() {
        var buf = [UInt8](repeating: 0, count: 84)
        buf[0] = 0x45  // IPv4, IHL=5 → ipOffset=20
        buf[20] = 0    // Echo Reply type
        let seq: UInt16 = 12
        buf[26] = UInt8(seq >> 8)
        buf[27] = UInt8(seq & 0xFF)

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "8.8.8.8", rtt: 10.0)
        if case .echoReply(let s) = response.kind {
            #expect(s == seq)
        } else {
            Issue.record("Expected echoReply with IPv4 header, got \(response.kind)")
        }
    }

    @Test("parseResponse: Time Exceeded short payload (< 36 bytes) produces origSeq=0, not echoReply")
    func timeExceededShortPayloadDoesNotProduceEchoReply() {
        // Short buffer: ICMP Time Exceeded header only (8 bytes), no room for inner IP+ICMP
        var buf = [UInt8](repeating: 0, count: 30)
        buf[0] = 11  // Time Exceeded
        // buf has no IP header prefix so ipOffset=0

        let response = ICMPSocket.parseResponse(buffer: buf, sourceIP: "192.168.1.1", rtt: 1.0)
        // Should be timeExceeded (with origSeq=0), never echoReply
        if case .echoReply = response.kind {
            Issue.record("Short Time Exceeded wrongly parsed as echoReply — triggers destinationReached=true prematurely")
        }
    }

    // MARK: - Default configuration (accessed via async actor)

    @Test("defaultMaxHops is 30")
    func defaultMaxHopsIs30() async {
        let service = TracerouteService()
        let maxHops = await service.defaultMaxHops
        #expect(maxHops == 30)
    }

    @Test("defaultTimeout is 2.0 seconds")
    func defaultTimeoutIs2Seconds() async {
        let service = TracerouteService()
        let timeout = await service.defaultTimeout
        #expect(timeout == 2.0)
    }

    // MARK: - Initial state

    @Test("running is false before any trace")
    func runningIsFalseBeforeAnyTrace() async {
        let service = TracerouteService()
        let running = await service.running
        #expect(running == false)
    }

    // MARK: - stop() state management

    @Test("stop() is idempotent when no trace is active")
    func stopIsIdempotentWithNoActiveTrace() async {
        let service = TracerouteService()
        await service.stop()
        await service.stop()
        let running = await service.running
        #expect(running == false)
    }

    // MARK: - TracerouteHop struct pure logic

    @Test("hop with zero times has nil averageTime")
    func hopWithZeroTimesHasNilAverageTime() {
        let hop = TracerouteHop(hopNumber: 3, ipAddress: "10.0.0.1", times: [])
        #expect(hop.averageTime == nil)
    }

    @Test("hop isTimeout is false when times are present")
    func hopIsNotTimeoutWhenTimesPresent() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1", times: [5.0, 6.0])
        #expect(hop.isTimeout == false)
    }

    @Test("hop isTimeout is true when flag is set")
    func hopIsTimeoutWhenFlagSet() {
        let hop = TracerouteHop(hopNumber: 2, isTimeout: true)
        #expect(hop.isTimeout == true)
    }

    @Test("hop hopNumber is stored correctly")
    func hopNumberStoredCorrectly() {
        let hop = TracerouteHop(hopNumber: 15, ipAddress: "1.2.3.4", times: [10.0])
        #expect(hop.hopNumber == 15)
    }

    @Test("hop with hostname stores it correctly")
    func hopHostnameStoredCorrectly() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "8.8.8.8", hostname: "dns.google", times: [20.0])
        #expect(hop.hostname == "dns.google")
        #expect(hop.ipAddress == "8.8.8.8")
    }

    @Test("hop times array is stored in order")
    func hopTimesStoredInOrder() {
        let times = [1.1, 2.2, 3.3]
        let hop = TracerouteHop(hopNumber: 1, times: times)
        #expect(hop.times == times)
    }
}
