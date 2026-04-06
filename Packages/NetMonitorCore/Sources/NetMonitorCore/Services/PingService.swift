import Foundation
import Network
import NetworkScanKit

public actor PingService: PingServiceProtocol {

    // MARK: - State

    private var isRunning = false
    private var activeRunID: UUID?

    /// Dedicated queue isolates TCP ping measurements from other traffic.
    ///
    /// SAFETY: nonisolated is safe here because DispatchQueue is an immutable, thread-safe
    /// reference created at init and never reassigned (let). Accessing it from outside the
    /// actor's isolation domain is safe — DispatchQueue itself is Sendable.
    nonisolated private let pingQueue = DispatchQueue(label: "com.netmonitor.ping", qos: .userInteractive)

    public init() {}

    // MARK: - Public API

    public func ping(
        host: String,
        count: Int = 4,
        timeout: TimeInterval = 5
    ) -> AsyncStream<PingResult> {
        AsyncStream { continuation in
            Task {
                let runID = self.beginRun()
                let resolvedIP = await resolveHost(host)

                // Try ICMP first; fall back to TCP if socket creation fails
                if let socket = try? ICMPSocket() {
                    await self.pingICMP(
                        socket: socket,
                        host: host,
                        ip: resolvedIP,
                        count: count,
                        timeout: timeout,
                        runID: runID,
                        continuation: continuation
                    )
                } else {
                    await self.pingTCP(
                        host: host,
                        ip: resolvedIP,
                        count: count,
                        timeout: timeout,
                        runID: runID,
                        continuation: continuation
                    )
                }

                self.endRun(runID: runID)
                continuation.finish()
            }
        }
    }

    public func stop() async {
        isRunning = false
        activeRunID = nil
    }

    public func calculateStatistics(_ results: [PingResult], requestedCount: Int? = nil) async -> PingStatistics? {
        guard !results.isEmpty else { return nil }

        let transmitted = requestedCount ?? results.count
        let successfulResults = results.filter { !$0.isTimeout }
        let received = successfulResults.count

        let packetLoss = transmitted > 0
            ? Double(transmitted - received) / Double(transmitted) * 100.0
            : 0.0

        let times = successfulResults.map(\.time)
        let minTime = times.min() ?? 0
        let maxTime = times.max() ?? 0
        let avgTime = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)

        let variance = times.isEmpty ? 0 : times.map { pow($0 - avgTime, 2) }.reduce(0, +) / Double(times.count)
        let stdDev = sqrt(variance)

        return PingStatistics(
            host: results.first?.host ?? "",
            transmitted: transmitted,
            received: received,
            packetLoss: packetLoss,
            minTime: minTime,
            maxTime: maxTime,
            avgTime: avgTime,
            stdDev: stdDev
        )
    }

    // MARK: - Run Management

    private func beginRun() -> UUID {
        let runID = UUID()
        activeRunID = runID
        isRunning = true
        return runID
    }

    private func shouldContinue(runID: UUID) -> Bool {
        isRunning && activeRunID == runID
    }

    private func endRun(runID: UUID) {
        guard activeRunID == runID else { return }
        activeRunID = nil
        isRunning = false
    }

    // MARK: - DNS Resolution

    private func resolveHost(_ host: String) async -> String? {
        await ServiceUtilities.resolveHostname(host)
    }

    // MARK: - ICMP Ping (primary path)

    private func pingICMP(
        socket: ICMPSocket,
        host: String,
        ip: String?,
        count: Int,
        timeout: TimeInterval,
        runID: UUID,
        continuation: AsyncStream<PingResult>.Continuation
    ) async {
        let targetIP = ip ?? host

        for seq in 1...count {
            guard shouldContinue(runID: runID) else { break }

            let response = await socket.sendPing(to: targetIP, timeout: timeout)

            let isTimeout: Bool
            switch response.kind {
            case .echoReply:
                isTimeout = false
            case .timeout, .timeExceeded, .error:
                isTimeout = true
            }

            let result = PingResult(
                sequence: seq,
                host: host,
                ipAddress: ip,
                ttl: 64,
                time: response.rtt,
                size: 64,
                isTimeout: isTimeout,
                method: .icmp
            )
            continuation.yield(result)

            if seq < count {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - TCP Ping (fallback when ICMP socket creation fails)

    /// Reference-type timestamp for Sendable closure capture.
    ///
    /// SAFETY: @unchecked Sendable is safe here because DateRef is only ever created
    /// inside a single NWConnection stateUpdateHandler closure on pingQueue and read
    /// synchronously on that same queue. No concurrent writes occur — the value is set
    /// once at construction and read once when the connection state fires.
    private final class DateRef: @unchecked Sendable {
        var value = Date()
    }

    private func pingTCP(
        host: String,
        ip: String?,
        count: Int,
        timeout: TimeInterval,
        runID: UUID,
        continuation: AsyncStream<PingResult>.Continuation
    ) async {
        for seq in 1...count {
            guard shouldContinue(runID: runID) else { break }

            let (success, connectTime) = await self.connectTest(
                host: ip ?? host,
                timeout: timeout
            )
            let elapsed = connectTime * 1000

            let result = PingResult(
                sequence: seq,
                host: host,
                ipAddress: ip,
                ttl: success ? 64 : 0,
                time: elapsed,
                size: 64,
                isTimeout: !success,
                method: .tcp
            )
            continuation.yield(result)

            if seq < count {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Try connecting to multiple common ports concurrently — succeed if ANY responds.
    /// Measures only the TCP handshake: timestamps captured synchronously on pingQueue,
    /// before any Task spawn or actor hop.
    private func connectTest(host: String, timeout: TimeInterval) async -> (success: Bool, elapsed: TimeInterval) {
        let ports: [NWEndpoint.Port] = [.https, .http, NWEndpoint.Port(rawValue: 22)!]
        let hostEndpoint = NWEndpoint.Host(host)

        let queue = pingQueue
        return await withTaskGroup(of: (Bool, TimeInterval).self, returning: (Bool, TimeInterval).self) { group in
            for port in ports {
                group.addTask {
                    await ConnectionBudget.shared.acquire()
                    let connection = NWConnection(to: .hostPort(host: hostEndpoint, port: port), using: .tcp)
                    defer {
                        connection.cancel()
                        Task { await ConnectionBudget.shared.release() }
                    }

                    return await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, TimeInterval), Never>) in
                        let resumed = ResumeState()
                        let startTime = DateRef()

                        let timeoutTask = Task {
                            try? await Task.sleep(for: .seconds(timeout))
                            guard await resumed.tryResume() else { return }
                            connection.cancel()
                            continuation.resume(returning: (false, timeout))
                        }

                        connection.stateUpdateHandler = { state in
                            // Capture elapsed SYNCHRONOUSLY on pingQueue — true handshake time.
                            let elapsed = Date().timeIntervalSince(startTime.value)
                            switch state {
                            case .ready:
                                Task {
                                    guard await resumed.tryResume() else { return }
                                    timeoutTask.cancel()
                                    connection.cancel()
                                    continuation.resume(returning: (true, elapsed))
                                }
                            case .failed(let error):
                                Task {
                                    guard await resumed.tryResume() else { return }
                                    timeoutTask.cancel()
                                    connection.cancel()

                                    // A refused TCP handshake still proves the host is reachable.
                                    if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                                        continuation.resume(returning: (true, elapsed))
                                    } else {
                                        continuation.resume(returning: (false, elapsed))
                                    }
                                }
                            case .cancelled:
                                Task {
                                    guard await resumed.tryResume() else { return }
                                    timeoutTask.cancel()
                                    connection.cancel()
                                    continuation.resume(returning: (false, elapsed))
                                }
                            default:
                                break
                            }
                        }

                        startTime.value = Date()
                        connection.start(queue: queue)
                    }
                }
            }

            // Return true as soon as any port succeeds, with its elapsed time
            var bestElapsed: TimeInterval = 0
            for await (success, elapsed) in group {
                if success {
                    group.cancelAll()
                    return (true, elapsed)
                }
                bestElapsed = max(bestElapsed, elapsed)
            }
            return (false, bestElapsed)
        }
    }
}
