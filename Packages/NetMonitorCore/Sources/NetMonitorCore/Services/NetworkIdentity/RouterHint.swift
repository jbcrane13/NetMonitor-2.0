import CryptoKit
import Darwin
import Foundation

/// The IPv6 default router's link-local address on an interface, as a hint of which network this is
/// (#628 PR B). Read synchronously from the routing table, which a sandboxed, team-signed build can
/// read. Unauthenticated: a cloned router address is indistinguishable.
public enum RouterHint {
    /// The digest of an identifying router address (16 bytes as the kernel reports them), or nil for a
    /// low-entropy one (`fe80::1`, an interface ID with fewer than 4 non-zero bytes that isn't EUI-64).
    /// The scope (bytes 2–3, which only select the interface) is zeroed first.
    public static func digest(_ address: [UInt8]) -> String? {
        guard address.count == 16, address[0] == 0xFE, address[1] & 0xC0 == 0x80 else { return nil }
        var canonical = address
        canonical[2] = 0
        canonical[3] = 0
        let iid = canonical[8..<16]
        let isEUI64 = canonical[11] == 0xFF && canonical[12] == 0xFE
        guard isEUI64 || iid.filter({ $0 != 0 }).count >= 4 else { return nil }
        let hash = SHA256.hash(data: Data("netmonitor.router.v1".utf8) + Data(canonical))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// The router hint on `interface`: the key of its identifying IPv6 default routers.
    public static func read(interface: String) -> RouterHintStatus {
        let index = if_nametoindex(interface)
        guard index != 0, let addresses = defaultRouters() else { return .failed }
        let digests = addresses.filter { $0.index == UInt16(index) }.compactMap { digest($0.address) }
        return digests.isEmpty ? .absent : .present(RouterKey(digests))
    }

    private struct MessageHeader {
        var msglen: UInt16
        var version: UInt8
        var type: UInt8
        var index: UInt16
        var flags: Int32
        var addrs: Int32
        var pid: Int32
        var seq: Int32
        var errno: Int32
        var use: Int32
        var inits: UInt32
        // swiftlint:disable:next large_tuple
        var metrics: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    }

    /// The IPv6 default routes' gateways with their interface index; nil when the table can't be read.
    private static func defaultRouters() -> [(index: UInt16, address: [UInt8])]? {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, AF_INET6, NET_RT_FLAGS, 0x2] // RTF_GATEWAY
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else { return nil }
        guard length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        let headerSize = MemoryLayout<MessageHeader>.size
        var routers: [(UInt16, [UInt8])] = []
        var offset = 0
        while offset + headerSize <= length {
            let header = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: MessageHeader.self) }
            let messageLength = Int(header.msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }
            defer { offset += messageLength }
            // Destination (bit 0) and gateway (bit 1) sockaddrs follow the header.
            guard header.addrs & 0x3 == 0x3 else { continue }
            var cursor = offset + headerSize
            var sockaddrs: [[UInt8]] = []
            for _ in 0..<2 {
                guard cursor < offset + messageLength else { break }
                let size = Int(buffer[cursor])
                let end = min(cursor + max(size, 1), offset + messageLength)
                sockaddrs.append(Array(buffer[cursor..<end]))
                cursor += size > 0 ? (size + 3) & ~3 : 4
            }
            guard sockaddrs.count == 2, let destination = ipv6Bytes(sockaddrs[0]), destination.allSatisfy({ $0 == 0 }),
                  let gateway = ipv6Bytes(sockaddrs[1]) else { continue }
            routers.append((header.index, gateway))
        }
        return routers
    }

    /// The 16 address bytes of a `sockaddr_in6`; a zero-length sockaddr (the default destination) is all zeros.
    private static func ipv6Bytes(_ sockaddr: [UInt8]) -> [UInt8]? {
        if sockaddr.count < 2 || sockaddr[0] == 0 {
            return [UInt8](repeating: 0, count: 16)
        }
        guard sockaddr[1] == UInt8(AF_INET6), sockaddr.count >= 24 else { return nil }
        return Array(sockaddr[8..<24])
    }
}
