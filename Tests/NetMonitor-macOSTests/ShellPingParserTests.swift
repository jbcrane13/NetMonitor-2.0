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
