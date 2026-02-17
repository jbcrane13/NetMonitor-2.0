import Foundation

// MARK: - ShellPingResult
// Renamed from "PingResult" to avoid conflict with NetMonitorCore.PingResult.

/// Aggregate result from a shell /sbin/ping invocation.
struct ShellPingResult: Sendable {
    let transmitted: Int
    let received: Int
    let packetLoss: Double      // 0-100
    let minLatency: Double      // ms
    let avgLatency: Double      // ms
    let maxLatency: Double      // ms
    let stddevLatency: Double   // ms

    var isReachable: Bool { received > 0 }
}

/// A single parsed ping response line.
struct ShellPingLine: Sendable {
    let sequenceNumber: Int
    let latency: Double?
    let ttl: Int?
    let bytes: Int
    let host: String
}

/// Actor-based service for executing ping commands via /sbin/ping.
/// Used by GatewayInfoCard for latency measurement.
actor ShellPingService {
    private let pingPath = "/sbin/ping"
    private let runner = ShellCommandRunner()

    func ping(host: String, count: Int = 1, timeout: TimeInterval = 5) async throws -> ShellPingResult {
        let arguments = [
            "-c", String(count),
            "-W", String(Int(timeout * 1000)),
            host
        ]
        let output = try await runner.run(pingPath, arguments: arguments, timeout: timeout * Double(count) + 5)
        return try ShellPingOutputParser.parseResult(output.stdout)
    }

    func pingStream(host: String, count: Int) -> AsyncThrowingStream<ShellPingLine, Error> {
        let arguments = ["-c", String(count), host]
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in await runner.stream(pingPath, arguments: arguments) {
                        if let pingLine = ShellPingOutputParser.parseResponseLine(line) {
                            continuation.yield(pingLine)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel() async { await runner.cancel() }
}

// MARK: - Parser

enum ShellPingOutputParser {
    private static let responsePattern = try! NSRegularExpression(
        pattern: #"(\d+) bytes from ([^:]+): icmp_seq=(\d+) ttl=(\d+) time=([0-9.]+) ms"#
    )
    private static let summaryPattern = try! NSRegularExpression(
        pattern: #"(\d+) packets transmitted, (\d+) (?:packets )?received, ([0-9.]+)% packet loss"#
    )
    private static let statsPattern = try! NSRegularExpression(
        pattern: #"min/avg/max/stddev = ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms"#
    )
    private static let timeoutPattern = try! NSRegularExpression(
        pattern: #"Request timeout for icmp_seq (\d+)"#
    )

    static func parseResponseLine(_ line: String) -> ShellPingLine? {
        let range = NSRange(line.startIndex..., in: line)
        if let match = timeoutPattern.firstMatch(in: line, range: range),
           let seqRange = Range(match.range(at: 1), in: line),
           let seq = Int(line[seqRange]) {
            return ShellPingLine(sequenceNumber: seq, latency: nil, ttl: nil, bytes: 0, host: "")
        }
        if let match = responsePattern.firstMatch(in: line, range: range),
           match.numberOfRanges == 6,
           let bytesRange = Range(match.range(at: 1), in: line),
           let hostRange = Range(match.range(at: 2), in: line),
           let seqRange = Range(match.range(at: 3), in: line),
           let ttlRange = Range(match.range(at: 4), in: line),
           let timeRange = Range(match.range(at: 5), in: line),
           let bytes = Int(line[bytesRange]),
           let seq = Int(line[seqRange]),
           let ttl = Int(line[ttlRange]),
           let time = Double(line[timeRange]) {
            return ShellPingLine(sequenceNumber: seq, latency: time, ttl: ttl, bytes: bytes, host: String(line[hostRange]))
        }
        return nil
    }

    static func parseResult(_ output: String) throws -> ShellPingResult {
        let lines = output.components(separatedBy: .newlines)
        var transmitted = 0, received = 0
        var packetLoss: Double = 100, minL: Double = 0, avgL: Double = 0, maxL: Double = 0, stddev: Double = 0
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let m = summaryPattern.firstMatch(in: line, range: range),
               let r1 = Range(m.range(at: 1), in: line),
               let r2 = Range(m.range(at: 2), in: line),
               let r3 = Range(m.range(at: 3), in: line) {
                transmitted = Int(line[r1]) ?? 0
                received = Int(line[r2]) ?? 0
                packetLoss = Double(line[r3]) ?? 100
            }
            if let m = statsPattern.firstMatch(in: line, range: range),
               let r1 = Range(m.range(at: 1), in: line),
               let r2 = Range(m.range(at: 2), in: line),
               let r3 = Range(m.range(at: 3), in: line),
               let r4 = Range(m.range(at: 4), in: line) {
                minL = Double(line[r1]) ?? 0
                avgL = Double(line[r2]) ?? 0
                maxL = Double(line[r3]) ?? 0
                stddev = Double(line[r4]) ?? 0
            }
        }
        return ShellPingResult(transmitted: transmitted, received: received, packetLoss: packetLoss,
                               minLatency: minL, avgLatency: avgL, maxLatency: maxL, stddevLatency: stddev)
    }
}
