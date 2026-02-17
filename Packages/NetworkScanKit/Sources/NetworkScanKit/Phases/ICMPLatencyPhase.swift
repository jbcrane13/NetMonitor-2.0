import Foundation
import os.log

private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "ICMPLatency")

/// Global serial queue for ICMP I/O — keeps blocking poll() off the cooperative pool.
private let icmpQueue = DispatchQueue(label: "com.netmonitor.scankit.icmp", qos: .userInitiated)

/// Enriches already-discovered devices with ICMP-based latency measurements.
///
/// Uses a single-socket ping sweep on a dedicated dispatch queue:
/// 1. Send ICMP echo requests to all targets rapidly
/// 2. Collect ALL responses in a tight synchronous loop (no async suspension)
/// 3. Batch-update the accumulator with results
///
/// The dedicated queue prevents cooperative thread pool scheduling from inflating
/// RTT measurements between recvfrom calls.
public struct ICMPLatencyPhase: ScanPhase, Sendable {
    public let id = "icmpLatency"
    public let displayName = "Measuring latency…"
    public let weight: Double = 0.10

    /// How long to wait for responses after sending all probes.
    private let collectTimeout: TimeInterval

    public init(collectTimeout: TimeInterval = 2.0) {
        self.collectTimeout = collectTimeout
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        let ipsNeedingLatency = await accumulator.allDeviceIPs()
        guard !ipsNeedingLatency.isEmpty else {
            await onProgress(1.0)
            return
        }

        // Create a single ICMP socket — fails on Simulator
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            logger.info("ICMP socket unavailable (errno=\(errno)), skipping latency enrichment")
            await onProgress(1.0)
            return
        }

        // Non-blocking for poll-based collection
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        logger.info("ICMP ping sweep: \(ipsNeedingLatency.count) devices")

        let timeout = collectTimeout

        // Run all I/O on a dedicated queue — no async suspension between reads
        let results: [(ip: String, rtt: Double)] = await withCheckedContinuation { continuation in
            icmpQueue.async {
                let results = Self.pingSweep(
                    fd: fd,
                    ips: ipsNeedingLatency,
                    timeout: timeout
                )
                close(fd)
                continuation.resume(returning: results)
            }
        }

        // Batch-update accumulator — ICMP replaces any TCP-based latency
        for (ip, rtt) in results {
            await accumulator.replaceLatency(ip: ip, latency: rtt)
        }

        logger.info("ICMP ping sweep complete: \(results.count)/\(ipsNeedingLatency.count) enriched")
        await onProgress(1.0)
    }

    // MARK: - Synchronous Ping Sweep (runs entirely on icmpQueue)

    /// Sends all echo requests and collects responses in a tight loop.
    /// No async suspension points — timing is accurate.
    private static func pingSweep(
        fd: Int32,
        ips: [String],
        timeout: TimeInterval
    ) -> [(ip: String, rtt: Double)] {

        // Map sequence → (ip, sendTime)
        var pending: [UInt16: (ip: String, sendTime: ContinuousClock.Instant)] = [:]

        // Phase 1: Blast all echo requests
        for (index, ip) in ips.enumerated() {
            let seq = UInt16((index % Int(UInt16.max)) + 1)
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { continue }

            let packet = buildEchoRequest(identifier: 0, sequence: seq)
            let sendTime = ContinuousClock.now

            let sent = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(fd, packet, packet.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if sent == packet.count {
                pending[seq] = (ip: ip, sendTime: sendTime)
            }
        }

        logger.debug("Sent \(pending.count) echo requests, collecting responses…")

        // Phase 2: Collect responses — tight synchronous loop
        var results: [(ip: String, rtt: Double)] = []
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1000))
        var buf = [UInt8](repeating: 0, count: 256)

        while !pending.isEmpty && ContinuousClock.now < deadline {
            let remaining = deadline - .now
            let remainingMs = max(1, Int32(
                remaining.components.seconds * 1000 +
                remaining.components.attoseconds / 1_000_000_000_000_000
            ))

            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFd, 1, min(remainingMs, 200))

            guard pollResult > 0 else {
                if remainingMs <= 1 { break }
                continue
            }

            // Read ALL available responses without blocking between reads
            while true {
                var fromAddr = sockaddr_in()
                var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let received = withUnsafeMutablePointer(to: &fromAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        recvfrom(fd, &buf, buf.count, 0, sockaddrPtr, &fromLen)
                    }
                }

                let recvTime = ContinuousClock.now

                guard received > 0 else { break } // EWOULDBLOCK = no more data

                // Parse: skip IP header if present
                var offset = 0
                if received >= 20 && (buf[0] >> 4) == 4 {
                    offset = Int(buf[0] & 0x0F) * 4
                }

                guard received > offset + 7 else { continue }
                let icmpType = buf[offset]
                guard icmpType == 0 else { continue } // Echo Reply only

                // Sequence number matching only — the kernel already filters SOCK_DGRAM
                // ICMP responses to our socket, and remaps the identifier field internally.
                let respSeq = UInt16(buf[offset + 6]) << 8 | UInt16(buf[offset + 7])
                guard let probe = pending.removeValue(forKey: respSeq) else { continue }

                let elapsed = recvTime - probe.sendTime
                let rtt = Double(elapsed.components.seconds) * 1000.0
                    + Double(elapsed.components.attoseconds) / 1e15

                results.append((ip: probe.ip, rtt: rtt))
            }
        }

        return results
    }

    // MARK: - Packet Building

    private static func buildEchoRequest(identifier: UInt16, sequence: UInt16, payloadSize: Int = 16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadSize)
        packet[0] = 8  // Echo Request
        packet[1] = 0  // Code

        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        for i in 0..<payloadSize {
            packet[8 + i] = UInt8(i & 0xFF)
        }

        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        return packet
    }

    private static func internetChecksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i < data.count - 1 {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count {
            sum += UInt32(data[i]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum)
    }
}
