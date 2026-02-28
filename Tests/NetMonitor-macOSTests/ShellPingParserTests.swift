import Testing
@testable import NetMonitor_macOS

// MARK: - ShellPingResult Tests

@Suite("ShellPingResult")
struct ShellPingResultTests {

    @Test func isReachableWhenReceivedGreaterThanZero() {
        let result = ShellPingResult(
            transmitted: 3, received: 2,
            packetLoss: 33.3,
            minLatency: 1.0, avgLatency: 2.0, maxLatency: 3.0, stddevLatency: 0.5
        )
        #expect(result.isReachable)
    }

    @Test func isNotReachableWhenReceivedIsZero() {
        let result = ShellPingResult(
            transmitted: 3, received: 0,
            packetLoss: 100.0,
            minLatency: 0, avgLatency: 0, maxLatency: 0, stddevLatency: 0
        )
        #expect(!result.isReachable)
    }

    @Test func isReachableWhenAllPacketsReceived() {
        let result = ShellPingResult(
            transmitted: 5, received: 5,
            packetLoss: 0.0,
            minLatency: 1.0, avgLatency: 1.5, maxLatency: 2.0, stddevLatency: 0.1
        )
        #expect(result.isReachable)
    }
}

// MARK: - ShellPingOutputParser.parseResponseLine Tests

@Suite("ShellPingOutputParser - parseResponseLine")
struct ShellPingParseResponseLineTests {

    @Test func parsesValidResponseLine() {
        let line = "64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=1.234 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 1)
        #expect(result?.latency == 1.234)
        #expect(result?.ttl == 64)
        #expect(result?.bytes == 64)
        #expect(result?.host == "192.168.1.1")
    }

    @Test func parsesResponseLineWithHighLatency() {
        let line = "64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=12.567 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result?.sequenceNumber == 2)
        #expect(result?.latency == 12.567)
        #expect(result?.ttl == 118)
        #expect(result?.host == "8.8.8.8")
    }

    @Test func parsesTimeoutLine() {
        let line = "Request timeout for icmp_seq 3"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 3)
        #expect(result?.latency == nil)
        #expect(result?.ttl == nil)
        #expect(result?.bytes == 0)
    }

    @Test func returnsNilForHeaderLine() {
        let line = "PING 192.168.1.1 (192.168.1.1): 56 data bytes"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    @Test func returnsNilForEmptyString() {
        let result = ShellPingOutputParser.parseResponseLine("")
        #expect(result == nil)
    }

    @Test func returnsNilForSummaryLine() {
        let line = "3 packets transmitted, 3 packets received, 0.0% packet loss"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    @Test func returnsNilForStatsLine() {
        let line = "round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.567 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }
}

// MARK: - ShellPingOutputParser.parseResult Tests

@Suite("ShellPingOutputParser - parseResult")
struct ShellPingParseResultTests {

    @Test func parsesSuccessfulPingOutput() throws {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=10.123 ms
        64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=11.456 ms
        64 bytes from 1.1.1.1: icmp_seq=2 ttl=57 time=9.789 ms

        --- 1.1.1.1 ping statistics ---
        3 packets transmitted, 3 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 9.789/10.456/11.456/0.678 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 3)
        #expect(result.received == 3)
        #expect(result.packetLoss == 0.0)
        #expect(result.minLatency == 9.789)
        #expect(result.avgLatency == 10.456)
        #expect(result.maxLatency == 11.456)
        #expect(result.stddevLatency == 0.678)
        #expect(result.isReachable)
    }

    @Test func parsesFullPacketLoss() throws {
        let output = """
        PING 192.168.99.99 (192.168.99.99): 56 data bytes
        Request timeout for icmp_seq 0
        Request timeout for icmp_seq 1

        --- 192.168.99.99 ping statistics ---
        3 packets transmitted, 0 packets received, 100.0% packet loss
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 3)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        #expect(!result.isReachable)
    }

    @Test func parsesPartialPacketLoss() throws {
        let output = """
        PING 10.0.0.1 (10.0.0.1): 56 data bytes
        64 bytes from 10.0.0.1: icmp_seq=0 ttl=64 time=1.234 ms
        Request timeout for icmp_seq 1

        --- 10.0.0.1 ping statistics ---
        2 packets transmitted, 1 packets received, 50.0% packet loss
        round-trip min/avg/max/stddev = 1.234/1.234/1.234/0.000 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 2)
        #expect(result.received == 1)
        #expect(result.packetLoss == 50.0)
        #expect(result.isReachable)
    }

    @Test func parsesEmptyOutputWithDefaults() throws {
        let result = try ShellPingOutputParser.parseResult("")
        #expect(result.transmitted == 0)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        #expect(result.minLatency == 0.0)
        #expect(result.avgLatency == 0.0)
        #expect(!result.isReachable)
    }

    @Test func handlesSinglePacketPing() throws {
        let output = """
        PING 8.8.8.8 (8.8.8.8): 56 data bytes
        64 bytes from 8.8.8.8: icmp_seq=0 ttl=118 time=15.000 ms

        --- 8.8.8.8 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 15.000/15.000/15.000/0.000 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 1)
        #expect(result.received == 1)
        #expect(result.minLatency == 15.000)
        #expect(result.avgLatency == 15.000)
        #expect(result.isReachable)
    }
}

// MARK: - ShellPingOutputParser - Malformed & Edge Case Tests

@Suite("ShellPingOutputParser - Malformed Input")
struct ShellPingParserMalformedTests {

    // MARK: - parseResponseLine: garbage strings

    @Test("garbage string returns nil")
    func garbageStringReturnsNil() {
        let result = ShellPingOutputParser.parseResponseLine("this is complete garbage 123 abc !@#")
        #expect(result == nil)
    }

    @Test("random numbers return nil")
    func randomNumbersReturnsNil() {
        let result = ShellPingOutputParser.parseResponseLine("42 99 100 200")
        #expect(result == nil)
    }

    @Test("JSON-like string returns nil")
    func jsonLikeStringReturnsNil() {
        let result = ShellPingOutputParser.parseResponseLine("{\"host\":\"1.1.1.1\",\"time\":10}")
        #expect(result == nil)
    }

    @Test("partial response line missing time returns nil")
    func partialResponseMissingTime() {
        let line = "64 bytes from 192.168.1.1: icmp_seq=1 ttl=64"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    @Test("partial response line missing ttl returns nil")
    func partialResponseMissingTtl() {
        let line = "64 bytes from 192.168.1.1: icmp_seq=1 time=1.234 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    @Test("partial response line missing icmp_seq returns nil")
    func partialResponseMissingSeq() {
        let line = "64 bytes from 192.168.1.1: ttl=64 time=1.234 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result == nil)
    }

    @Test("whitespace-only string returns nil")
    func whitespaceOnlyReturnsNil() {
        let result = ShellPingOutputParser.parseResponseLine("   \t  ")
        #expect(result == nil)
    }

    @Test("newline-only string returns nil")
    func newlineOnlyReturnsNil() {
        let result = ShellPingOutputParser.parseResponseLine("\n")
        #expect(result == nil)
    }

    // MARK: - parseResponseLine: timeout format variations

    @Test("timeout line with high sequence number")
    func timeoutHighSeq() {
        let line = "Request timeout for icmp_seq 999"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 999)
        #expect(result?.latency == nil)
    }

    @Test("timeout line with zero sequence number")
    func timeoutZeroSeq() {
        let line = "Request timeout for icmp_seq 0"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 0)
        #expect(result?.latency == nil)
    }

    // MARK: - parseResponseLine: varied ping formats

    @Test("hostname response line with parenthesized IP")
    func hostnameResponseWithIP() {
        let line = "64 bytes from dns.google (8.8.8.8): icmp_seq=1 ttl=118 time=5.432 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.sequenceNumber == 1)
        #expect(result?.latency == 5.432)
        #expect(result?.ttl == 118)
    }

    @Test("response with sub-millisecond latency")
    func subMillisecondLatency() {
        let line = "64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=0.123 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.latency == 0.123)
    }

    @Test("response with very high latency")
    func veryHighLatency() {
        let line = "64 bytes from 1.2.3.4: icmp_seq=5 ttl=50 time=999.999 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.latency == 999.999)
        #expect(result?.sequenceNumber == 5)
    }

    @Test("response with large byte count")
    func largeByteCount() {
        let line = "1024 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=2.000 ms"
        let result = ShellPingOutputParser.parseResponseLine(line)
        #expect(result != nil)
        #expect(result?.bytes == 1024)
    }

    // MARK: - parseResult: malformed full output

    @Test("garbage output parses with defaults")
    func garbageFullOutput() throws {
        let output = """
        this is not ping output at all
        just random text
        nothing useful here
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 0)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        #expect(!result.isReachable)
    }

    @Test("output with only summary line, no stats line")
    func summaryOnlyNoStats() throws {
        let output = """
        3 packets transmitted, 0 packets received, 100.0% packet loss
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 3)
        #expect(result.received == 0)
        #expect(result.packetLoss == 100.0)
        #expect(result.minLatency == 0.0)
        #expect(result.avgLatency == 0.0)
    }

    @Test("output with only stats line, no summary line")
    func statsOnlyNoSummary() throws {
        let output = """
        round-trip min/avg/max/stddev = 1.0/2.0/3.0/0.5 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        // No summary line parsed, so transmitted/received stay 0
        #expect(result.transmitted == 0)
        #expect(result.received == 0)
        // But stats are parsed
        #expect(result.minLatency == 1.0)
        #expect(result.avgLatency == 2.0)
        #expect(result.maxLatency == 3.0)
        #expect(result.stddevLatency == 0.5)
    }

    @Test("output with Linux-style received format")
    func linuxStyleReceived() throws {
        // Linux uses "3 received" instead of "3 packets received"
        let output = """
        PING 1.1.1.1 (1.1.1.1) 56(84) bytes of data.
        64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=10.0 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 received, 0% packet loss, time 0ms
        rtt min/avg/max/mdev = 10.0/10.0/10.0/0.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        // The summary regex uses "(?:packets )?received" so this should match
        #expect(result.transmitted == 1)
        #expect(result.received == 1)
        #expect(result.packetLoss == 0.0)
    }

    /// Regression test for ab05737: statsPattern was "stddev" only, missing Linux "mdev" variant.
    /// Fix: pattern updated to min/avg/max/(?:stddev|mdev). Verifies stddevLatency is
    /// correctly extracted when Linux "mdev" keyword is present instead of "stddev".
    @Test("Linux mdev format parses stddevLatency correctly (regression: ab05737)")
    func linuxMdevStddevLatency() throws {
        let output = """
        PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
        64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=5.0 ms
        64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=15.0 ms

        --- 8.8.8.8 ping statistics ---
        2 packets transmitted, 2 received, 0% packet loss, time 1001ms
        rtt min/avg/max/mdev = 5.0/10.0/15.0/2.5 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.minLatency == 5.0)
        #expect(result.avgLatency == 10.0)
        #expect(result.maxLatency == 15.0)
        #expect(result.stddevLatency == 2.5, "stddevLatency must be parsed from Linux mdev keyword")
        #expect(result.transmitted == 2)
        #expect(result.received == 2)
    }

    @Test("multiline output with extra blank lines")
    func extraBlankLines() throws {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes

        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=10.0 ms


        --- 1.1.1.1 ping statistics ---

        1 packets transmitted, 1 packets received, 0.0% packet loss

        round-trip min/avg/max/stddev = 10.0/10.0/10.0/0.0 ms
        """
        let result = try ShellPingOutputParser.parseResult(output)
        #expect(result.transmitted == 1)
        #expect(result.received == 1)
        #expect(result.minLatency == 10.0)
        #expect(result.isReachable)
    }
}
