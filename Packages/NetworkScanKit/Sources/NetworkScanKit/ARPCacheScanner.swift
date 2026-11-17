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
    // swiftlint:disable:next large_tuple
    var sdl_data: (CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar)
}

// MARK: - ARP Entry

/// One resolved entry from the system ARP table.
public struct ARPEntry: Sendable, Equatable {
    public let ip: String
    public let mac: String
    /// The kernel's `rmx_expire` for the entry; 0 means permanent or not reported.
    /// Only compared against an earlier read of the same table, never against a clock.
    public let expiry: Int32

    public init(ip: String, mac: String, expiry: Int32) {
        self.ip = ip
        self.mac = mac
        self.expiry = expiry
    }
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
    /// cache to settle, then read it back.
    ///
    /// - Parameter hosts: IP address strings to probe (e.g. `["192.168.1.1", ...]`)
    /// - Returns: Tuples of (ip, mac) for each live device found in the ARP cache.
    public static func scanSubnet(hosts: [String]) async -> [(ip: String, mac: String)] {
        populateARPCache(hosts: hosts)
        let entries = await pollUntilSettled(read: readARPEntries)
        return entries.map { (ip: $0.ip, mac: $0.mac) }
    }

    // MARK: - Settle polling (#379)

    /// Re-reads the ARP table every `pollInterval` until no new IP has appeared for
    /// `quietPeriod`, or `cap` has elapsed, and returns the last read.
    ///
    /// Replaces a fixed 2 s sleep: on a warm or small network the table stops changing
    /// well before 2 s, while `cap` keeps the worst case no slower than before.
    /// `read` and `sleep` are injectable so tests run without real waits.
    static func pollUntilSettled(
        pollInterval: Duration = .milliseconds(250),
        quietPeriod: Duration = .milliseconds(500),
        cap: Duration = .seconds(2),
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        read: () -> [ARPEntry]
    ) async -> [ARPEntry] {
        var latest = read()
        var knownIPs = Set(latest.map(\.ip))
        var elapsed: Duration = .zero
        var quiet: Duration = .zero

        while elapsed < cap, quiet < quietPeriod {
            // `try? Task.sleep` returns at once when cancelled; without this check the
            // loop would spin to `cap` re-reading the table.
            guard !Task.isCancelled else { break }
            await sleep(pollInterval)
            elapsed += pollInterval
            guard !Task.isCancelled else { break }

            latest = read()
            let ips = Set(latest.map(\.ip))
            if ips.isSubset(of: knownIPs) {
                quiet += pollInterval
            } else {
                knownIPs.formUnion(ips)
                quiet = .zero
            }
        }
        return latest
    }

    // MARK: - Entry freshness (#378)

    /// The latest expiry seen for each IP. The table can hold one entry per interface
    /// for the same IP (`ifscope`), so the newest wins.
    public static func expiryByIP(_ entries: [ARPEntry]) -> [String: Int32] {
        var result: [String: Int32] = [:]
        for entry in entries {
            result[entry.ip] = max(result[entry.ip] ?? entry.expiry, entry.expiry)
        }
        return result
    }

    /// IPs whose ARP entry was resolved or re-confirmed after `baseline` was read.
    ///
    /// Measured on macOS (Nov 2026): an entry's age does not tell "gone" from "quiet".
    /// Entries past their expiry keep working and many still answer ping, and a UDP
    /// probe to a host with a valid entry does not refresh it. What does prove the host
    /// answered is its expiry moving forward, or an entry appearing that was not there
    /// before. A zero expiry (permanent, or not reported) proves nothing.
    ///
    /// The `arp -anl` fallback derives expiry from whole seconds left, so an entry that
    /// is only counting down can drift by a second between reads; a real refresh moves
    /// it forward by minutes, hence the small tolerance.
    public static func refreshedIPs(baseline: [String: Int32], current: [ARPEntry]) -> Set<String> {
        let tolerance: Int32 = 2
        var refreshed: Set<String> = []
        for (ip, expiry) in expiryByIP(current) {
            guard let previous = baseline[ip] else {
                refreshed.insert(ip)
                continue
            }
            if expiry != 0, previous != 0, expiry > previous &+ tolerance {
                refreshed.insert(ip)
            }
        }
        return refreshed
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
        readARPEntries().map { (ip: $0.ip, mac: $0.mac) }
    }

    /// Read the system ARP cache, keeping each entry's expiry.
    ///
    /// On macOS 27 the routing sysctl returns no IPv4 entries to third-party
    /// processes, while `/usr/sbin/arp` still lists them (#401), so macOS falls back
    /// to running it when the sysctl comes back empty.
    public static func readARPEntries() -> [ARPEntry] {
        let entries = readSysctlEntries()
        #if os(macOS)
        if entries.isEmpty {
            return readArpCommandEntries()
        }
        #endif
        return entries
    }

    private static func readSysctlEntries() -> [ARPEntry] {
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
        var bufferSize = 0
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

    // MARK: - `arp -anl` fallback (#401)

    #if os(macOS)
    private static func readArpCommandEntries() -> [ARPEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-anl"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let now = Int32(clamping: Int(Date().timeIntervalSince1970))
        guard let text = String(bytes: data, encoding: .utf8) else { return [] }
        return parseArpListing(text, now: now)
    }
    #endif

    /// Parses `arp -anl` output (columns: Neighbor, Linklayer Address, Expire(O),
    /// Expire(I), Netif, ...). Incomplete, all-zero and broadcast entries are dropped,
    /// MAC octets are zero-padded (`arp` prints `9c:5:d6:...`), and Expire(O) becomes
    /// an absolute time in seconds (`now` plus the time left) so two reads compare the
    /// way kernel `rmx_expire` values do. `expired` becomes 1, which is non-zero but
    /// older than any live entry; `(none)` becomes 0 (permanent or unknown).
    static func parseArpListing(_ text: String, now: Int32) -> [ARPEntry] {
        var entries: [ARPEntry] = []
        for line in text.split(separator: "\n").dropFirst() {
            let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard columns.count >= 3 else { continue }
            let ip = String(columns[0])
            let octets = columns[1].split(separator: ":")
            guard isValidIPv4Address(ip), octets.count == 6 else { continue }
            let bytes = octets.compactMap { UInt8($0, radix: 16) }
            guard bytes.count == 6,
                  !bytes.allSatisfy({ $0 == 0 }),
                  !bytes.allSatisfy({ $0 == 0xFF }) else { continue }
            let mac = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")

            let expiry: Int32
            switch columns[2] {
            case "(none)": expiry = 0
            case "expired": expiry = 1
            default:
                guard let seconds = parseDuration(columns[2]) else { continue }
                expiry = now &+ seconds
            }
            entries.append(ARPEntry(ip: ip, mac: mac, expiry: expiry))
        }
        return entries
    }

    /// Parses `arp`'s compact durations such as `51s`, `2m6s` or `1h2m3s`.
    static func parseDuration(_ text: Substring) -> Int32? {
        var total: Int32 = 0
        var number: Int32 = 0
        var sawUnit = false
        for character in text {
            if let digit = character.wholeNumberValue {
                number = number * 10 + Int32(digit)
                continue
            }
            switch character {
            case "h": total += number * 3600
            case "m": total += number * 60
            case "s": total += number
            default: return nil
            }
            number = 0
            sawUnit = true
        }
        return sawUnit ? total : nil
    }

    // MARK: - Routing message parsing

    private static func parseARPEntries(buffer: [UInt8], length: Int) -> [ARPEntry] {
        var results: [ARPEntry] = []
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
    ) -> ARPEntry? {
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
            let ip = String(decoding: ipBuf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)

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
            return ARPEntry(ip: ip, mac: mac, expiry: header.rtm_rmx.rmx_expire)
        }
    }

    /// Round up to 4-byte alignment (as used in routing socket messages).
    private static func roundUp(_ value: Int) -> Int {
        (value + 3) & ~3
    }
}
