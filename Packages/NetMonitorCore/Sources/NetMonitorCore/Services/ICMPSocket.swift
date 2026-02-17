import Foundation
import os.log

private let icmpLog = Logger(subsystem: "com.netmonitor", category: "ICMPSocket")

// MARK: - ICMP Types & Constants

enum ICMPError: Error, Sendable {
    case socketCreationFailed
    case invalidAddress
    case sendFailed
}

enum ICMPType: UInt8, Sendable {
    case echoReply = 0
    case echoRequest = 8
    case timeExceeded = 11
}

/// Parsed ICMP response from a ping or traceroute probe.
struct ICMPResponse: Sendable {
    enum Kind: Sendable {
        case echoReply(sequence: UInt16)
        case timeExceeded(routerIP: String, originalSequence: UInt16)
        case timeout
        case error
    }

    let kind: Kind
    let sourceIP: String?
    /// Round-trip time in milliseconds, measured with ContinuousClock.
    let rtt: Double
}

// MARK: - ICMPSocket Actor

/// Low-level ICMP socket wrapper for non-privileged ping and traceroute.
/// Uses `SOCK_DGRAM/IPPROTO_ICMP` (no root required on iOS, App Store approved).
///
/// The kernel handles:
/// - IP header construction/stripping
/// - Identifier remapping (maps to internal port)
/// - Response filtering (only delivers replies matching our socket)
///
/// We match responses by sequence number only.
actor ICMPSocket {
    /// The BSD socket file descriptor. Set once in init, never changed.
    private let fd: Int32
    /// Monotonically increasing sequence counter for correlating probes.
    private var sequenceCounter: UInt16 = 0
    /// Dedicated queue for blocking BSD socket I/O to avoid blocking the cooperative pool.
    private nonisolated let ioQueue = DispatchQueue(label: "com.netmonitor.icmp.io", qos: .userInteractive)

    init() throws {
        let rawFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard rawFd >= 0 else {
            icmpLog.error("socket() failed: errno=\(errno)")
            throw ICMPError.socketCreationFailed
        }
        self.fd = rawFd
        icmpLog.info("ICMP socket created: fd=\(rawFd)")

        // Set non-blocking for poll-based timeout
        let flags = fcntl(rawFd, F_GETFL, 0)
        _ = fcntl(rawFd, F_SETFL, flags | O_NONBLOCK)
    }

    deinit {
        Darwin.close(fd)
    }

    // MARK: - Public API

    /// Send an ICMP echo request and wait for a reply (echo reply or time exceeded).
    /// Used by PingService for standard ping.
    func sendPing(to target: String, timeout: TimeInterval, payloadSize: Int = 56) async -> ICMPResponse {
        let seq = nextSequence()
        let socketFd = fd

        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let response = Self.performProbe(
                    fd: socketFd,
                    target: target,
                    sequence: seq,
                    payloadSize: payloadSize,
                    timeout: timeout
                )
                continuation.resume(returning: response)
            }
        }
    }

    /// Send an ICMP echo request with a specific TTL and wait for the response.
    /// Used by TracerouteService — routers return Time Exceeded when TTL expires.
    func sendProbe(to target: String, ttl: Int32, timeout: TimeInterval, payloadSize: Int = 56) async -> ICMPResponse {
        let seq = nextSequence()
        let socketFd = fd

        // Set TTL before sending (must happen on actor to serialize with other calls)
        var ttlValue = ttl
        setsockopt(socketFd, IPPROTO_IP, IP_TTL, &ttlValue, socklen_t(MemoryLayout<Int32>.size))

        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let response = Self.performProbe(
                    fd: socketFd,
                    target: target,
                    sequence: seq,
                    payloadSize: payloadSize,
                    timeout: timeout
                )
                continuation.resume(returning: response)
            }
        }
    }

    // MARK: - Sequence Counter

    private func nextSequence() -> UInt16 {
        sequenceCounter &+= 1
        return sequenceCounter
    }

    // MARK: - Static I/O (runs on ioQueue, never on cooperative pool)

    /// Builds an ICMP echo request, sends it, waits for a response, and parses it.
    /// Entirely self-contained — no actor state accessed.
    private nonisolated static func performProbe(
        fd: Int32,
        target: String,
        sequence: UInt16,
        payloadSize: Int,
        timeout: TimeInterval
    ) -> ICMPResponse {
        // Build target address
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, target, &addr.sin_addr) == 1 else {
            icmpLog.error("inet_pton failed for target: \(target)")
            return ICMPResponse(kind: .error, sourceIP: nil, rtt: 0)
        }

        // Build ICMP echo request packet
        let packet = buildEchoRequest(sequence: sequence, payloadSize: payloadSize)

        // Drain any stale responses from previous pings before timing
        drainSocket(fd: fd)

        // Start timing with ContinuousClock for sub-millisecond precision
        let startTime = ContinuousClock.now

        // Send
        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(fd, packet, packet.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if sent < 0 {
            let err = errno
            icmpLog.error("sendto failed: errno=\(err) (\(String(cString: strerror(err))))")
        }

        guard sent == packet.count else {
            icmpLog.error("sendto short write: sent=\(sent) expected=\(packet.count)")
            return ICMPResponse(kind: .error, sourceIP: nil, rtt: 0)
        }

        icmpLog.debug("Sent \(packet.count) bytes to \(target) seq=\(sequence)")

        // Poll+receive loop: keep reading until we get our sequence or timeout
        let deadline = startTime + .milliseconds(Int(timeout * 1000))

        while true {
            let remaining = deadline - .now
            let remainingMs = max(1, Int32(remaining.components.seconds * 1000
                + remaining.components.attoseconds / 1_000_000_000_000_000))

            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFd, 1, remainingMs)

            let elapsed = ContinuousClock.now - startTime
            let rtt = Double(elapsed.components.seconds) * 1000.0
                + Double(elapsed.components.attoseconds) / 1e15

            guard pollResult > 0 else {
                icmpLog.warning("poll timeout after \(rtt, format: .fixed(precision: 1))ms seq=\(sequence)")
                return ICMPResponse(kind: .timeout, sourceIP: nil, rtt: rtt)
            }

            // Receive response
            var responseBuffer = [UInt8](repeating: 0, count: 1024)
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let received = withUnsafeMutablePointer(to: &fromAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    recvfrom(fd, &responseBuffer, responseBuffer.count, 0, sockaddrPtr, &fromLen)
                }
            }

            if received < 0 {
                let err = errno
                icmpLog.error("recvfrom failed: errno=\(err) (\(String(cString: strerror(err))))")
                return ICMPResponse(kind: .error, sourceIP: nil, rtt: rtt)
            }

            guard received > 0 else {
                return ICMPResponse(kind: .error, sourceIP: nil, rtt: rtt)
            }

            let sourceIP = ipString(from: fromAddr)
            let buf = Array(responseBuffer[0..<received])

            // Log raw response for debugging
            let headerBytes = buf.prefix(40)
            icmpLog.debug("Received \(received) bytes from \(sourceIP ?? "?") seq=\(sequence) header: \(headerBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")

            let parsed = parseResponse(buffer: buf, sourceIP: sourceIP, rtt: rtt)

            // Verify this is the response we're looking for
            switch parsed.kind {
            case .echoReply(let respSeq):
                if respSeq == sequence {
                    return parsed
                }
                icmpLog.debug("Skipping echo reply with wrong seq: got=\(respSeq) expected=\(sequence)")
                continue // Read next message

            case .timeExceeded(_, let origSeq):
                if origSeq == sequence {
                    return parsed
                }
                icmpLog.debug("Skipping time exceeded with wrong seq: got=\(origSeq) expected=\(sequence)")
                continue

            case .timeout, .error:
                return parsed
            }
        }
    }

    // MARK: - Packet Construction

    /// Builds an ICMP echo request packet (header + payload).
    /// Header: type(1) + code(1) + checksum(2) + identifier(2) + sequence(2) = 8 bytes
    /// The kernel rewrites identifier and checksum for SOCK_DGRAM sockets.
    nonisolated static func buildEchoRequest(sequence: UInt16, payloadSize: Int = 56, identifier: UInt16 = 0) -> [UInt8] {
        let headerSize = 8
        let packetSize = headerSize + payloadSize
        var packet = [UInt8](repeating: 0, count: packetSize)

        // Type: Echo Request (8)
        packet[0] = ICMPType.echoRequest.rawValue
        // Code: 0
        packet[1] = 0
        // Checksum: 0 (computed below)
        packet[2] = 0
        packet[3] = 0
        // Identifier (network byte order / big-endian)
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        // Sequence (network byte order / big-endian)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        // Payload: repeating pattern for identification
        for i in 0..<payloadSize {
            packet[headerSize + i] = UInt8(i & 0xFF)
        }

        // Calculate and set checksum
        let checksum = icmpChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        return packet
    }

    // MARK: - Response Parsing

    /// Parses a received ICMP message into a typed response.
    ///
    /// Despite the man page claiming SOCK_DGRAM strips the IP header,
    /// in practice macOS/iOS returns the full IP packet. We must skip
    /// the IP header (variable length via `ip_hl` field) to reach ICMP.
    ///
    /// After skipping IP:
    /// - **Echo Reply**: ICMP header (8 bytes) + payload
    /// - **Time Exceeded**: ICMP header (8 bytes) + original IP header (20 bytes)
    ///   + first 8 bytes of original ICMP echo request
    nonisolated static func parseResponse(
        buffer: [UInt8],
        sourceIP: String?,
        rtt: Double
    ) -> ICMPResponse {
        guard buffer.count >= 8 else {
            return ICMPResponse(kind: .error, sourceIP: sourceIP, rtt: rtt)
        }

        // Skip IP header if present (check IP version nibble)
        let ipOffset: Int
        if (buffer[0] >> 4) == 4 {
            // IPv4: header length is lower nibble * 4
            ipOffset = Int(buffer[0] & 0x0F) * 4
        } else {
            // No IP header (kernel stripped it) — start at 0
            ipOffset = 0
        }

        let icmp = Array(buffer[ipOffset...])
        guard icmp.count >= 8 else {
            return ICMPResponse(kind: .error, sourceIP: sourceIP, rtt: rtt)
        }

        let icmpType = icmp[0]

        switch icmpType {
        case ICMPType.echoReply.rawValue:
            let respSeq = UInt16(icmp[6]) << 8 | UInt16(icmp[7])
            return ICMPResponse(
                kind: .echoReply(sequence: respSeq),
                sourceIP: sourceIP,
                rtt: rtt
            )

        case ICMPType.timeExceeded.rawValue:
            // Payload structure: ICMP header (8) + original IP header (20) + original ICMP (8)
            // Original ICMP sequence is at offset 8 + 20 + 6 = 34
            var originalSeq: UInt16 = 0
            if icmp.count >= 36 {
                originalSeq = UInt16(icmp[34]) << 8 | UInt16(icmp[35])
            }

            return ICMPResponse(
                kind: .timeExceeded(
                    routerIP: sourceIP ?? "*",
                    originalSequence: originalSeq
                ),
                sourceIP: sourceIP,
                rtt: rtt
            )

        default:
            return ICMPResponse(kind: .error, sourceIP: sourceIP, rtt: rtt)
        }
    }

    // MARK: - Checksum

    /// RFC 1071 Internet Checksum — ones' complement of the ones' complement sum
    /// of all 16-bit words in the ICMP message.
    nonisolated static func icmpChecksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        let count = data.count

        // Sum all 16-bit words (big-endian)
        while index < count - 1 {
            let word = UInt32(data[index]) << 8 | UInt32(data[index + 1])
            sum += word
            index += 2
        }

        // Handle trailing odd byte
        if index < count {
            sum += UInt32(data[index]) << 8
        }

        // Fold 32-bit sum into 16 bits
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return ~UInt16(sum & 0xFFFF)
    }

    // MARK: - Socket Buffer Management

    /// Drains any pending data from the socket receive buffer.
    /// Called before each new probe to prevent stale responses from being
    /// read as replies to the current probe.
    private nonisolated static func drainSocket(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 1024)
        var drained = 0
        while true {
            let n = recv(fd, &buf, buf.count, MSG_DONTWAIT)
            if n <= 0 { break }
            drained += 1
        }
        if drained > 0 {
            icmpLog.debug("Drained \(drained) stale message(s) from socket buffer")
        }
    }

    // MARK: - Utilities

    /// Converts a sockaddr_in to a human-readable IPv4 string.
    private nonisolated static func ipString(from addr: sockaddr_in) -> String? {
        var addrCopy = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result = inet_ntop(AF_INET, &addrCopy.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        guard result != nil else { return nil }
        return String(cString: buffer)
    }
}
