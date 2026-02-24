import Foundation
import Network

/// Service for performing real ICMP traceroute using non-privileged BSD sockets.
///
/// Uses `SOCK_DGRAM/IPPROTO_ICMP` with incrementing TTL values. When a router
/// decrements TTL to zero, it returns an ICMP Time Exceeded message revealing
/// its IP address. When the destination is reached, it returns an Echo Reply.
///
/// Falls back to a single TCP probe if ICMP socket creation fails (e.g., in Simulator).
public actor TracerouteService: TracerouteServiceProtocol {

    // MARK: - Configuration

    public let defaultMaxHops: Int = 30
    public let defaultTimeout: TimeInterval = 2.0
    /// Number of probes sent per hop (standard traceroute uses 3).
    private let probesPerHop: Int = 3

    // MARK: - State

    private var isRunning = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Performs a traceroute to the specified host.
    /// - Parameters:
    ///   - host: Target hostname or IP address
    ///   - maxHops: Maximum number of hops (default 30)
    ///   - timeout: Timeout per probe in seconds (default 2.0)
    /// - Returns: AsyncStream of TracerouteHop results
    public func trace(
        host: String,
        maxHops: Int? = nil,
        timeout: TimeInterval? = nil
    ) -> AsyncStream<TracerouteHop> {
        let effectiveMaxHops = maxHops ?? defaultMaxHops
        let effectiveTimeout = timeout ?? defaultTimeout

        return AsyncStream { continuation in
            Task {
                await self.performTrace(
                    host: host,
                    maxHops: effectiveMaxHops,
                    timeout: effectiveTimeout,
                    continuation: continuation
                )
            }
        }
    }

    /// Stops the current traceroute operation.
    public func stop() async {
        isRunning = false
    }

    /// Returns whether a traceroute is currently running.
    public var running: Bool {
        isRunning
    }

    // MARK: - Private Implementation

    private func performTrace(
        host: String,
        maxHops: Int,
        timeout: TimeInterval,
        continuation: AsyncStream<TracerouteHop>.Continuation
    ) async {
        isRunning = true
        defer {
            isRunning = false
            continuation.finish()
        }

        // Resolve hostname to IP
        let resolvedIP = resolveHostname(host)
        guard let targetIP = resolvedIP else {
            continuation.yield(TracerouteHop(
                hopNumber: 1,
                ipAddress: nil,
                hostname: host,
                times: [],
                isTimeout: true
            ))
            return
        }

        // Try ICMP traceroute first; fall back to TCP probe if unavailable
        if let socket = try? ICMPSocket() {
            await performICMPTrace(
                socket: socket,
                host: host,
                targetIP: targetIP,
                maxHops: maxHops,
                timeout: timeout,
                continuation: continuation
            )
        } else {
            await performTCPFallback(
                host: host,
                targetIP: targetIP,
                maxHops: maxHops,
                timeout: timeout,
                continuation: continuation
            )
        }
    }

    // MARK: - Real ICMP Traceroute

    /// Performs a real traceroute by sending ICMP echo requests with incrementing TTL.
    ///
    /// Algorithm:
    /// ```
    /// for ttl in 1...maxHops:
    ///     set IP_TTL = ttl
    ///     send 3 ICMP echo requests
    ///     collect responses:
    ///         Time Exceeded → router at this hop (extract source IP)
    ///         Echo Reply    → destination reached, stop
    ///         Timeout       → show * for this probe
    ///     yield TracerouteHop
    ///     if destination reached: break
    /// ```
    private func performICMPTrace(
        socket: ICMPSocket,
        host: String,
        targetIP: String,
        maxHops: Int,
        timeout: TimeInterval,
        continuation: AsyncStream<TracerouteHop>.Continuation
    ) async {
        for ttl in 1...maxHops {
            guard isRunning else { break }

            var probeTimes: [Double] = []
            var hopIP: String?
            var destinationReached = false

            // Send multiple probes per hop
            for _ in 0..<probesPerHop {
                guard isRunning else { break }

                let response = await socket.sendProbe(
                    to: targetIP,
                    ttl: Int32(ttl),
                    timeout: timeout
                )

                switch response.kind {
                case .echoReply:
                    probeTimes.append(response.rtt)
                    hopIP = response.sourceIP ?? targetIP
                    destinationReached = true

                case .timeExceeded(let routerIP, _):
                    probeTimes.append(response.rtt)
                    if hopIP == nil {
                        hopIP = routerIP
                    }

                case .timeout:
                    // No response for this probe — will show as missing time
                    break

                case .error:
                    break
                }
            }

            let allTimeout = probeTimes.isEmpty

            // Reverse DNS lookup for the hop IP (non-blocking, best-effort)
            var hostname: String?
            if let ip = hopIP {
                hostname = await reverseDNS(ip)
                // Don't set hostname if it matches the original host (redundant)
                if hostname == host { hostname = nil }
            }

            continuation.yield(TracerouteHop(
                hopNumber: ttl,
                ipAddress: hopIP,
                hostname: hostname,
                times: probeTimes,
                isTimeout: allTimeout
            ))

            if destinationReached { break }
        }
    }

    // MARK: - TCP Fallback

    /// Multi-hop TCP traceroute for when ICMP sockets are unavailable (e.g., iOS Simulator,
    /// restricted sandbox). Sends TCP SYN probes with incrementing TTL values to the target.
    ///
    /// Intermediate routers that decrement TTL to zero send ICMP Time Exceeded back, but
    /// our TCP socket cannot receive that ICMP error — so intermediate hops show as timeouts
    /// (like `* * *` in standard traceroute output). When TTL is large enough to reach the
    /// destination, the connect() either succeeds or is refused (RST), revealing the endpoint.
    ///
    /// This is the same behaviour as `tcptraceroute` on macOS/Linux: timeouts for intermediate
    /// routers that don't respond to TCP, real RTT when the destination is reached.
    private nonisolated func performTCPFallback(
        host: String,
        targetIP: String,
        maxHops: Int,
        timeout: TimeInterval,
        continuation: AsyncStream<TracerouteHop>.Continuation
    ) async {
        // Try port 443 first; common ports most likely to elicit a reply at the destination
        let port: UInt16 = 443

        for ttl in 1...maxHops {
            // Check actor-isolated `isRunning` without blocking the cooperative pool
            let running = await self.isRunning
            guard running else { break }

            var probeTimes: [Double] = []
            var destinationReached = false

            // Send probesPerHop probes at this TTL, matching standard traceroute behaviour
            for _ in 0..<probesPerHop {
                let result = tcpProbe(host: targetIP, port: port, timeout: timeout, ttl: Int32(ttl))
                switch result {
                case .connected(let rtt), .refused(let rtt):
                    probeTimes.append(rtt)
                    destinationReached = true
                case .timeout, .error:
                    // Intermediate hop dropped packet (TTL expired) or no response — keep going
                    break
                }
            }

            let allTimeout = probeTimes.isEmpty

            continuation.yield(TracerouteHop(
                hopNumber: ttl,
                // We can only identify the destination IP; intermediate routers are unknown via TCP
                ipAddress: destinationReached ? targetIP : nil,
                hostname: destinationReached && host != targetIP ? host : nil,
                times: probeTimes,
                isTimeout: allTimeout
            ))

            if destinationReached { break }
        }
    }

    // MARK: - TCP Probe

    private enum ProbeResult: Sendable {
        case connected(Double)   // RTT in milliseconds
        case refused(Double)     // Host responded with RST (still reachable)
        case timeout
        case error
    }

    /// Attempts a TCP connection to measure reachability and latency.
    ///
    /// - Parameters:
    ///   - host: IPv4 address string of the target.
    ///   - port: TCP port to connect to.
    ///   - timeout: How long to wait for the connect to complete.
    ///   - ttl: Optional IP TTL to set before connecting. Pass a value ≥ 1 for
    ///     traceroute-style probing — the packet will be dropped by the router at
    ///     that hop count, causing a timeout here while routers along the path
    ///     see (and silently discard) the probe.
    private nonisolated func tcpProbe(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        ttl: Int32? = nil
    ) -> ProbeResult {
        let startTime = ContinuousClock.now

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return .error }

        // Set IP TTL before connecting when performing traceroute probes
        if let ttlValue = ttl {
            var t = ttlValue
            setsockopt(fd, IPPROTO_IP, IP_TTL, &t, socklen_t(MemoryLayout<Int32>.size))
        }

        // Set non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(fd)
            return .error
        }

        // Initiate non-blocking connect
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            let elapsed = ContinuousClock.now - startTime
            let rtt = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1e15
            close(fd)
            return .connected(rtt)
        }

        guard errno == EINPROGRESS else {
            close(fd)
            return .error
        }

        // Use poll to wait for connect with timeout
        let timeoutMs = Int32(timeout * 1000)
        var pollFd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollFd, 1, timeoutMs)

        let elapsed = ContinuousClock.now - startTime
        let rtt = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1e15

        if pollResult <= 0 {
            close(fd)
            return .timeout
        }

        // Check if connection succeeded or was refused
        var connectError: Int32 = 0
        var errorLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &connectError, &errorLen)
        close(fd)

        if connectError == 0 {
            return .connected(rtt)
        } else if connectError == ECONNREFUSED {
            return .refused(rtt)
        } else {
            return .timeout
        }
    }

    // MARK: - DNS Resolution

    private nonisolated func resolveHostname(_ hostname: String) -> String? {
        ServiceUtilities.resolveHostnameSync(hostname)
    }

    /// Reverse DNS lookup for a hop IP address. Returns the hostname if available.
    private func reverseDNS(_ ipAddress: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                inet_pton(AF_INET, ipAddress, &addr.sin_addr)

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                let result = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        getnameinfo(
                            sockaddrPtr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0, 0
                        )
                    }
                }

                if result == 0 {
                    let name = String(decoding: hostname.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    // Don't return the IP address itself as a "hostname"
                    if name != ipAddress {
                        continuation.resume(returning: name)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
