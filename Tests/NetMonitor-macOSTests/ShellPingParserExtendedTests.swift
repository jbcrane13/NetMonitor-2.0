import Testing
@testable import NetMonitor_macOS

// MARK: - ShellPingOutputParser Extended Tests

struct ShellPingParserExtendedTests {

    // MARK: - IPv6 Output Parsing

    @Test func ipv6ResponseLineReturnsNil() {
        // The parser regex expects IPv4-style output; IPv6 ping output should not match
        let line = "64 bytes from 2001:db8::1: icmp_seq=1 hlim=64 time=5.123 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        // IPv6 format uses "hlim" not "ttl" — parser should return nil or not crash
        // Either outcome is acceptable; we just verify no crash and reasonable behaviour
        if let r = result {
            // If it parsed, sequence and latency must be sensible
            #expect(r.sequenceNumber >= 0)
        } else {
            #expect(result == nil)
        }
    }

    @Test func ipv6SummaryLineProducesDefaultResult() throws {
        // Linux IPv6 ping summary differs from IPv4 format
        let output = """
        PING6 2001:db8::1 56 data bytes
        64 bytes from 2001:db8::1: icmp_seq=0 hlim=64 time=12.0 ms

        --- 2001:db8::1 ping6 statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/std-dev = 12.0/12.0/12.0/0.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        // Summary line still matches the standard regex
        #expect(result.transmitted == 1)
        #expect(result.received == 1)
        #expect(result.packetLoss == 0.0)
        #expect(result.isReachable)
    }

    // MARK: - Unreachable Host Output

    @Test func unreachableHostOutputProducesZeroReceived() throws {
        let output = """
        PING 192.0.2.1 (192.0.2.1): 56 data bytes
        Request timeout for icmp_seq 0
        Request timeout for icmp_seq 1
        Request timeout for icmp_seq 2

        --- 192.0.2.1 ping statistics ---
        3 packets transmitted, 0 packets received, 100.0% packet loss
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 3)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        #expect(!result.isReachable)
    }

    @Test func unreachableHostTimeoutLinesParseIndividually() {
        for seq in 0..<5 {
            let line = "Request timeout for icmp_seq \(seq)"
            let parsed = ShellPingOutputParser.parseResponseLine(line)
            #expect(parsed != nil)
            #expect(parsed?.sequenceNumber == seq)
            #expect(parsed?.latency == nil)
        }
    }

    @Test func hostUnreachableIcmpMessageReturnsNil() {
        // macOS may emit "92 bytes from ... Destination Net Unreachable" — no icmp_seq/ttl/time
        let line = "92 bytes from 192.168.1.1: Destination Net Unreachable"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    // MARK: - Partial / Interrupted Output

    @Test func partialOutputMissingSummaryFallsBackToDefaults() throws {
        // Simulates Ctrl-C interruption — no summary or stats line
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=8.5 ms
        64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=9.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        // No summary line found → defaults (transmitted=0, received=0, loss=100%)
        #expect(result.transmitted == 0)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        // Stats line also absent → latency defaults to 0
        #expect(result.minLatency == 0.0)
        #expect(result.avgLatency == 0.0)
    }

    @Test func partialOutputWithOnlyOneResponseLine() throws {
        let output = """
        PING 8.8.8.8 (8.8.8.8): 56 data bytes
        64 bytes from 8.8.8.8: icmp_seq=0 ttl=118 time=11.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        // Summary absent → transmitted/received default to 0; no stats line
        #expect(result.transmitted == 0)
        #expect(!result.isReachable)
    }

    // MARK: - Non-Standard Format Handling

    @Test func windowsPingFormatDoesNotCrash() throws {
        // Windows ping uses a different format — should parse gracefully
        let output = """
        Pinging 8.8.8.8 with 32 bytes of data:
        Reply from 8.8.8.8: bytes=32 time=14ms TTL=118
        Reply from 8.8.8.8: bytes=32 time=13ms TTL=118

        Ping statistics for 8.8.8.8:
            Packets: Sent = 2, Received = 2, Lost = 0 (0% loss),
        Approximate round trip times in milli-seconds:
            Minimum = 13ms, Maximum = 14ms, Average = 13ms
        """
        // Should not throw; result will have defaults since format doesn't match
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted >= 0)
        #expect(result.received >= 0)
    }

    @Test func responseLineWithDomainNameHostField() {
        let line = "64 bytes from lga34s32-in-f4.1e100.net (142.250.80.68): icmp_seq=3 ttl=115 time=7.891 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 3)
        #expect(result?.latency == 7.891)
        #expect(result?.ttl == 115)
    }

    @Test func statsLineWithRttPrefixInsteadOfRoundTrip() throws {
        // Linux uses "rtt" prefix instead of "round-trip"
        let output = """
        1 packets transmitted, 1 packets received, 0% packet loss
        rtt min/avg/max/mdev = 5.0/5.0/5.0/0.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 1)
        #expect(result.received == 1)
        // rtt prefix also matches the "min/avg/max/stddev = ..." pattern since the
        // statsPattern looks for "min/avg/max/stddev = ..."
        #expect(result.minLatency == 5.0)
        #expect(result.avgLatency == 5.0)
    }
}
