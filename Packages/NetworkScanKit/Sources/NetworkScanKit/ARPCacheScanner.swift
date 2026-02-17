import Foundation

// MARK: - BSD routing socket types not exposed in iOS Swift SDK
// These are stable, well-documented BSD types from <net/route.h> and <net/if_dl.h>.
// Defined here because iOS Swift module map doesn't export them.

/// Routing message address bitmask flags (from <net/route.h>)
private let RTA_DST: Int32       = 0x1
private let RTA_GATEWAY: Int32   = 0x2

/// Route flag: entry has link-layer info (ARP) (from <net/route.h>)
private let RTF_LLINFO: Int32    = 0x400

/// Routing metrics (from <net/route.h>).  Layout is stable across all
/// Apple platforms (macOS, iOS, tvOS, watchOS) on arm64.
private struct RouteMetrics {
    var rmx_locks: UInt32
    var rmx_mtu: UInt32
    var rmx_hopcount: UInt32
    var rmx_expire: Int32
    var rmx_recvpipe: UInt32
    var rmx_sendpipe: UInt32
    var rmx_ssthresh: UInt32
    var rmx_rtt: UInt32
    var rmx_rttvar: UInt32
    var rmx_pksent: UInt32
    var rmx_state: UInt32
    var rmx_filler: (UInt32, UInt32, UInt32)
}

/// Routing message header (from <net/route.h>).
private struct RouteMsgHdr {
    var rtm_msglen: UInt16
    var rtm_version: UInt8
    var rtm_type: UInt8
    var rtm_index: UInt16
    var rtm_flags: Int32
    var rtm_addrs: Int32
    var rtm_pid: Int32
    var rtm_seq: Int32
    var rtm_errno: Int32
    var rtm_use: Int32
    var rtm_inits: UInt32
    var rtm_rmx: RouteMetrics
}

/// Link-layer socket address (from <net/if_dl.h>).
private struct SockaddrDL {
    var sdl_len: UInt8
    var sdl_family: UInt8
    var sdl_index: UInt16
    var sdl_type: UInt8
    var sdl_nlen: UInt8
    var sdl_alen: UInt8
    var sdl_slen: UInt8
    // sdl_data follows (variable length: name + MAC bytes)
    // We access it via pointer arithmetic from the struct base.
    var sdl_data: (CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar)
}

// MARK: - ARP Cache Scanner

/// Scans the local subnet by triggering ARP resolution via UDP probes,
/// then reads the system ARP cache to discover live devices with MAC addresses.
///
/// This technique finds devices that don't have any open TCP ports —
/// the same approach used by Fing, Net Analyzer, and other top iOS scanners.
///
/// Uses BSD sockets directly (no NWConnection, no ConnectionBudget needed).
public enum ARPCacheScanner: Sendable {

    // MARK: - Public API

    /// Send UDP packets to all hosts to trigger ARP resolution, wait for the
    /// cache to populate, then read it back.
    ///
    /// - Parameter hosts: IP address strings to probe (e.g. `["192.168.1.1", ...]`)
    /// - Returns: Tuples of (ip, mac) for each live device found in the ARP cache.
    public static func scanSubnet(hosts: [String]) async -> [(ip: String, mac: String)] {
        populateARPCache(hosts: hosts)
        // Give the OS time to complete ARP resolution for all probed hosts.
        // 2 seconds is sufficient for most /24 networks.
        try? await Task.sleep(for: .seconds(2))
        return readARPCache()
    }

    // MARK: - UDP probe (triggers ARP resolution)

    /// Fire-and-forget UDP packets to each host on a high port.
    /// This triggers the kernel to perform ARP resolution for each IP,
    /// populating the system ARP cache.
    public static func populateARPCache(hosts: [String]) {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return }
        defer { close(sock) }

        // Set non-blocking so sendto never blocks
        var flags = fcntl(sock, F_GETFL, 0)
        if flags >= 0 {
            flags |= O_NONBLOCK
            _ = fcntl(sock, F_SETFL, flags)
        }

        // Single byte payload — we just need the kernel to ARP-resolve the destination
        var payload: UInt8 = 0

        for (index, host) in hosts.enumerated() {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(55555).bigEndian
            guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { continue }

            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(sock, &payload, 1, MSG_DONTWAIT,
                               sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            // Rate-limit: 20ms pause every 50 packets to avoid UDP flood
            if (index + 1) % 50 == 0 {
                usleep(20_000)
            }
        }
    }

    // MARK: - ARP cache reading via sysctl

    /// Read the system ARP cache and return IP/MAC pairs for live devices.
    public static func readARPCache() -> [(ip: String, mac: String)] {
        // sysctl parameters for reading the routing table's ARP entries
        var mib: [Int32] = [
            CTL_NET,
            AF_ROUTE,       // PF_ROUTE
            0,              // protocol
            AF_INET,        // IPv4
            NET_RT_FLAGS,
            RTF_LLINFO      // only link-layer (ARP) entries
        ]

        // First call: determine buffer size
        var bufferSize: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &bufferSize, nil, 0) == 0,
              bufferSize > 0 else {
            return []
        }

        // Second call: read data
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &bufferSize, nil, 0) == 0 else {
            return []
        }

        return parseARPEntries(buffer: buffer, length: bufferSize)
    }

    // MARK: - Routing message parsing

    private static func parseARPEntries(buffer: [UInt8], length: Int) -> [(ip: String, mac: String)] {
        var results: [(ip: String, mac: String)] = []
        results.reserveCapacity(64)

        let headerSize = MemoryLayout<RouteMsgHdr>.size
        var offset = 0

        while offset + headerSize <= length {
            let msgLen: Int = buffer.withUnsafeBufferPointer { ptr in
                let raw = UnsafeRawPointer(ptr.baseAddress! + offset)
                let header = raw.load(as: RouteMsgHdr.self)
                return Int(header.rtm_msglen)
            }

            guard msgLen > 0, offset + msgLen <= length else { break }

            if let entry = parseOneEntry(buffer: buffer, offset: offset, msgLen: msgLen) {
                results.append(entry)
            }

            offset += msgLen
        }

        return results
    }

    private static func parseOneEntry(
        buffer: [UInt8], offset: Int, msgLen: Int
    ) -> (ip: String, mac: String)? {
        let headerSize = MemoryLayout<RouteMsgHdr>.size
        guard msgLen > headerSize else { return nil }

        return buffer.withUnsafeBufferPointer { ptr in
            let base = UnsafeRawPointer(ptr.baseAddress! + offset)

            // Read the header to check address mask
            let header = base.load(as: RouteMsgHdr.self)

            // We need both RTA_DST (destination IP) and RTA_GATEWAY (link-layer address)
            let addrs = header.rtm_addrs
            guard addrs & RTA_DST != 0, addrs & RTA_GATEWAY != 0 else { return nil }

            // sockaddr structures follow the header
            var saOffset = headerSize

            // First sockaddr: RTA_DST = destination IP (sockaddr_in)
            guard saOffset + MemoryLayout<sockaddr_in>.size <= msgLen else { return nil }
            let sinPtr = (base + saOffset).assumingMemoryBound(to: sockaddr_in.self)
            let sin = sinPtr.pointee
            guard sin.sin_family == sa_family_t(AF_INET) else { return nil }

            var ipAddr = sin.sin_addr
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ipAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            let ip = String(cString: ipBuf)

            // Advance past the first sockaddr (4-byte aligned)
            let saLen1 = Int(sin.sin_len)
            guard saLen1 > 0 else { return nil }
            saOffset += roundUp(saLen1)

            // Second sockaddr: RTA_GATEWAY = link-layer address (SockaddrDL)
            guard saOffset + MemoryLayout<SockaddrDL>.size <= msgLen else { return nil }
            let sdlPtr = (base + saOffset).assumingMemoryBound(to: SockaddrDL.self)
            let sdl = sdlPtr.pointee
            guard sdl.sdl_family == sa_family_t(AF_LINK) else { return nil }

            // Check that we have a valid MAC address (6 bytes)
            let macLen = Int(sdl.sdl_alen)
            guard macLen == 6 else { return nil }

            // MAC bytes start at (struct base + offsetof(sdl_data) + sdl_nlen)
            let nameLen = Int(sdl.sdl_nlen)
            let sdlDataOffset = MemoryLayout<SockaddrDL>.offset(of: \SockaddrDL.sdl_data)!
            let macStart = (base + saOffset + sdlDataOffset + nameLen)
            let macBytes = (0..<6).map { macStart.load(fromByteOffset: $0, as: UInt8.self) }

            // Filter out all-zeros and broadcast (ff:ff:ff:ff:ff:ff)
            let allZero = macBytes.allSatisfy { $0 == 0 }
            let broadcast = macBytes.allSatisfy { $0 == 0xFF }
            guard !allZero, !broadcast else { return nil }

            let mac = macBytes.map { String(format: "%02x", $0) }.joined(separator: ":")
            return (ip: ip, mac: mac)
        }
    }

    /// Round up to 4-byte alignment (as used in routing socket messages).
    private static func roundUp(_ value: Int) -> Int {
        (value + 3) & ~3
    }
}
