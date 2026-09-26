import Foundation
import Network

/// RFC 1035 (plus RFC 2782 SRV, RFC 8659 CAA, RFC 9460 HTTPS/SVCB) DNS wire-format
/// parsing shared by both DNS query paths:
/// - The system-resolver path (`DNSServiceQueryRecord`), where `packet` is just the
///   record's raw rdata bytes and `rdataOffset` is 0.
/// - The custom-server UDP path (`DNSUDPResolver`), where `packet` is the full
///   response datagram and `rdataOffset` is the rdata's position within it — this
///   matters because name compression pointers are relative to the whole packet.
enum DNSWireFormat {

    // MARK: - Record type <-> wire type number

    /// Numeric DNS TYPE values (RFC 1035 §3.2.2, RFC 2782, RFC 8659, RFC 9460).
    static func typeNumber(for type: DNSRecordType) -> UInt16 {
        switch type {
        case .a: return 1
        case .ns: return 2
        case .cname: return 5
        case .soa: return 6
        case .ptr: return 12
        case .mx: return 15
        case .txt: return 16
        case .aaaa: return 28
        case .srv: return 33
        case .https: return 65
        case .caa: return 257
        }
    }

    static func recordType(forTypeNumber number: UInt16) -> DNSRecordType? {
        switch number {
        case 1: return .a
        case 2: return .ns
        case 5: return .cname
        case 6: return .soa
        case 12: return .ptr
        case 15: return .mx
        case 16: return .txt
        case 28: return .aaaa
        case 33: return .srv
        case 65: return .https
        case 257: return .caa
        default: return nil
        }
    }

    // MARK: - Record parsing

    /// Parses a single resource record's rdata into a `DNSRecord`.
    /// - Parameters:
    ///   - domain: The name to attribute the record to (may differ from the
    ///     originally queried name when following a CNAME chain).
    ///   - packet: The buffer that `rdataOffset` is relative to (see type doc).
    ///   - rdataOffset: Offset of this record's rdata within `packet`, relative to `packet.startIndex`.
    ///   - rdataLength: Length of the rdata in bytes.
    static func parseRecord(
        domain: String,
        type: DNSRecordType,
        packet: Data,
        rdataOffset: Int,
        rdataLength: Int,
        ttl: UInt32
    ) -> DNSRecord? {
        guard rdataLength > 0,
              packet.startIndex + rdataOffset >= packet.startIndex,
              packet.startIndex + rdataOffset + rdataLength <= packet.endIndex else { return nil }

        switch type {
        case .a, .aaaa:
            return parseAddressRecord(domain: domain, type: type, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .mx:
            return parseMXRecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .txt:
            return parseTXTRecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .cname, .ns, .ptr:
            return parseDomainNameRecord(domain: domain, type: type, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .soa:
            return parseSOARecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .srv:
            return parseSRVRecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .caa:
            return parseCAARecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        case .https:
            // SVCB param parsing (RFC 9460) is intentionally not implemented — surface the
            // raw rdata as hex rather than mis-parse it. See issue #322.
            return parseHTTPSRecord(domain: domain, packet: packet, rdataOffset: rdataOffset, rdataLength: rdataLength, ttl: ttl)
        }
    }

    private static func parseAddressRecord(
        domain: String,
        type: DNSRecordType,
        packet: Data,
        rdataOffset: Int,
        rdataLength: Int,
        ttl: UInt32
    ) -> DNSRecord? {
        let base = packet.startIndex + rdataOffset
        let addressData = Data(packet[base..<base + rdataLength])

        let addressString: String?
        switch type {
        case .a:
            addressString = rdataLength == 4 ? IPv4Address(addressData).map { "\($0)" } : nil
        case .aaaa:
            addressString = rdataLength == 16 ? IPv6Address(addressData).map { "\($0)" } : nil
        default:
            addressString = nil
        }

        guard let value = addressString else { return nil }
        return DNSRecord(name: domain, type: type, value: value, ttl: Int(ttl))
    }

    private static func parseMXRecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        guard rdataLength >= 2 else { return nil }
        let base = packet.startIndex + rdataOffset
        let priority = (UInt16(packet[base]) << 8) | UInt16(packet[base + 1])

        var nameOffset = rdataOffset + 2
        guard let mailServer = parseDNSName(from: packet, offset: &nameOffset) else { return nil }

        return DNSRecord(name: domain, type: .mx, value: mailServer, ttl: Int(ttl), priority: Int(priority))
    }

    private static func parseTXTRecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        var offset = packet.startIndex + rdataOffset
        let end = offset + rdataLength
        var strings: [String] = []

        while offset < end {
            let length = Int(packet[offset])
            offset += 1
            guard offset + length <= end else { break }
            let stringData = packet[offset..<offset + length]
            if let string = String(data: stringData, encoding: .utf8) {
                strings.append(string)
            }
            offset += length
        }

        return DNSRecord(name: domain, type: .txt, value: strings.joined(separator: "\n"), ttl: Int(ttl))
    }

    private static func parseDomainNameRecord(
        domain: String,
        type: DNSRecordType,
        packet: Data,
        rdataOffset: Int,
        rdataLength: Int,
        ttl: UInt32
    ) -> DNSRecord? {
        var offset = rdataOffset
        guard let name = parseDNSName(from: packet, offset: &offset) else { return nil }
        return DNSRecord(name: domain, type: type, value: name, ttl: Int(ttl))
    }

    private static func parseSOARecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        var offset = rdataOffset

        guard let mname = parseDNSName(from: packet, offset: &offset) else { return nil }
        guard let rname = parseDNSName(from: packet, offset: &offset) else { return nil }

        guard packet.startIndex + offset + 20 <= packet.endIndex else { return nil }

        let base = packet.startIndex + offset
        let values = packet[base..<base + 20].withUnsafeBytes { ptr in
            (0..<5).map { i in ptr.load(fromByteOffset: i * 4, as: UInt32.self).bigEndian }
        }

        let soaValue = """
        \(mname) \(rname) (
          Serial: \(values[0])
          Refresh: \(values[1])
          Retry: \(values[2])
          Expire: \(values[3])
          Minimum: \(values[4])
        )
        """

        return DNSRecord(name: domain, type: .soa, value: soaValue, ttl: Int(ttl))
    }

    /// RFC 2782: 2-byte priority, 2-byte weight, 2-byte port, then a (possibly compressed) target name.
    private static func parseSRVRecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        guard rdataLength >= 6 else { return nil }
        let base = packet.startIndex + rdataOffset
        let priority = (UInt16(packet[base]) << 8) | UInt16(packet[base + 1])
        let weight   = (UInt16(packet[base + 2]) << 8) | UInt16(packet[base + 3])
        let port     = (UInt16(packet[base + 4]) << 8) | UInt16(packet[base + 5])

        var nameOffset = rdataOffset + 6
        guard let target = parseDNSName(from: packet, offset: &nameOffset) else { return nil }

        return DNSRecord(
            name: domain,
            type: .srv,
            value: "\(target):\(port) (weight \(weight))",
            ttl: Int(ttl),
            priority: Int(priority)
        )
    }

    /// RFC 8659: 1-byte flags, 1-byte tag length, tag (ASCII), remaining bytes are the value.
    private static func parseCAARecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        guard rdataLength >= 2 else { return nil }
        let base = packet.startIndex + rdataOffset
        let flags = packet[base]
        let tagLength = Int(packet[base + 1])
        guard 2 + tagLength <= rdataLength else { return nil }

        let tagStart = base + 2
        guard let tag = String(data: packet[tagStart..<tagStart + tagLength], encoding: .ascii) else { return nil }

        let valueStart = tagStart + tagLength
        let valueLength = rdataLength - 2 - tagLength
        let valueData = packet[valueStart..<valueStart + valueLength]
        let value = String(data: valueData, encoding: .utf8) ?? valueData.map { String(format: "%02x", $0) }.joined()

        return DNSRecord(name: domain, type: .caa, value: "\(flags) \(tag) \"\(value)\"", ttl: Int(ttl))
    }

    /// HTTPS/SVCB (RFC 9460) param parsing is out of scope — show the raw rdata as hex.
    private static func parseHTTPSRecord(domain: String, packet: Data, rdataOffset: Int, rdataLength: Int, ttl: UInt32) -> DNSRecord? {
        let base = packet.startIndex + rdataOffset
        let raw = packet[base..<base + rdataLength]
        let hex = raw.map { String(format: "%02x", $0) }.joined()
        return DNSRecord(name: domain, type: .https, value: "raw rdata: \(hex)", ttl: Int(ttl))
    }

    // MARK: - DNS name (de)compression

    /// Decodes a (possibly compressed) DNS name starting at `offset` (relative to
    /// `data.startIndex`), advancing `offset` past it. Follows RFC 1035 §4.1.4
    /// compression pointers, with a jump limit to reject hostile/cyclic pointers.
    static func parseDNSName(from data: Data, offset: inout Int) -> String? {
        var labels: [String] = []
        var currentOffset = data.startIndex + offset
        var didFollowPointer = false
        var jumps = 0
        let maxJumps = 20

        while currentOffset < data.endIndex {
            let lengthByte = Int(data[currentOffset])

            if (lengthByte & 0xC0) == 0xC0 {
                guard currentOffset + 1 < data.endIndex else { return nil }
                jumps += 1
                guard jumps <= maxJumps else { return nil }

                let pointerHigh = (lengthByte & 0x3F) << 8
                let pointerLow = Int(data[currentOffset + 1])
                let pointer = data.startIndex + pointerHigh + pointerLow

                if !didFollowPointer {
                    offset = (currentOffset + 2) - data.startIndex
                }
                didFollowPointer = true

                guard pointer < data.endIndex, pointer != currentOffset else { return nil }
                currentOffset = pointer
                continue
            }

            currentOffset += 1

            if lengthByte == 0 {
                if !didFollowPointer {
                    offset = currentOffset - data.startIndex
                }
                return labels.joined(separator: ".")
            }

            guard currentOffset + lengthByte <= data.endIndex else { return nil }

            let labelData = data[currentOffset..<currentOffset + lengthByte]
            guard let label = String(data: labelData, encoding: .utf8) else { return nil }

            labels.append(label)
            currentOffset += lengthByte
        }

        return nil
    }

    static func parseDNSName(from data: Data) -> String? {
        var offset = 0
        return parseDNSName(from: data, offset: &offset)
    }

    // MARK: - Reverse lookup names

    /// Builds the `in-addr.arpa` / `ip6.arpa` name for a plain IPv4/IPv6 address,
    /// or `nil` if `ipAddress` doesn't parse as either.
    static func reverseLookupName(for ipAddress: String) -> String? {
        if let v4 = IPv4Address(ipAddress) {
            let octets = [UInt8](v4.rawValue)
            return octets.reversed().map(String.init).joined(separator: ".") + ".in-addr.arpa"
        }
        if let v6 = IPv6Address(ipAddress) {
            let bytes = [UInt8](v6.rawValue)
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            let nibbles = hex.reversed().map(String.init)
            return nibbles.joined(separator: ".") + ".ip6.arpa"
        }
        return nil
    }

    // MARK: - Query construction (used by DNSUDPResolver)

    /// Builds a single-question RFC 1035 query message with recursion desired.
    static func buildQuery(id: UInt16, domain: String, type: DNSRecordType) -> Data {
        var packet = Data()
        packet.append(UInt8(id >> 8))
        packet.append(UInt8(id & 0xFF))
        packet.append(0x01) // flags (hi byte): RD=1
        packet.append(0x00) // flags (lo byte)
        packet.append(0x00)
        packet.append(0x01) // QDCOUNT = 1
        packet.append(0x00)
        packet.append(0x00) // ANCOUNT
        packet.append(0x00)
        packet.append(0x00) // NSCOUNT
        packet.append(0x00)
        packet.append(0x00) // ARCOUNT

        for label in domain.split(separator: ".", omittingEmptySubsequences: true) {
            let bytes = Array(label.utf8.prefix(63))
            packet.append(UInt8(bytes.count))
            packet.append(contentsOf: bytes)
        }
        packet.append(0x00) // root label

        let qtype = typeNumber(for: type)
        packet.append(UInt8(qtype >> 8))
        packet.append(UInt8(qtype & 0xFF))
        packet.append(0x00)
        packet.append(0x01) // QCLASS = IN
        return packet
    }

    // MARK: - Response parsing (used by DNSUDPResolver)

    /// Parses a full DNS response datagram, validating the transaction ID and
    /// distinguishing NXDOMAIN (RCODE 3), a truncated response (TC bit), and a
    /// successful-but-empty answer section (NODATA) from a parseable set of records.
    static func parseResponse(_ data: Data, expectedID: UInt16, domain: String, type: DNSRecordType) throws -> [DNSRecord] {
        guard data.count >= 12, u16(data, at: 0) == expectedID else { throw DNSError.lookupFailed }

        let flags = u16(data, at: 2)
        guard (flags >> 15) & 0x1 == 1 else { throw DNSError.lookupFailed } // QR bit
        let truncated = (flags >> 9) & 0x1 == 1
        let rcode = flags & 0x000F

        if rcode == 3 {
            throw DNSError.nxdomain(domain: domain)
        }
        guard rcode == 0 else { throw DNSError.lookupFailed }

        var offset = 12
        try skipQuestions(data, count: Int(u16(data, at: 4)), offset: &offset)
        let records = parseAnswers(data, count: Int(u16(data, at: 6)), offset: &offset)

        if records.isEmpty {
            if truncated {
                throw DNSError.truncated(domain: domain)
            }
            throw DNSError.noRecords(domain: domain, type: type)
        }
        return records
    }

    private static func u16(_ data: Data, at relativeOffset: Int) -> UInt16 {
        let i = data.startIndex + relativeOffset
        return (UInt16(data[i]) << 8) | UInt16(data[i + 1])
    }

    private static func skipQuestions(_ data: Data, count: Int, offset: inout Int) throws {
        for _ in 0..<count {
            guard parseDNSName(from: data, offset: &offset) != nil else { throw DNSError.lookupFailed }
            offset += 4 // QTYPE + QCLASS
        }
    }

    private static func parseAnswers(_ data: Data, count: Int, offset: inout Int) -> [DNSRecord] {
        var records: [DNSRecord] = []
        for _ in 0..<count {
            guard let name = parseDNSName(from: data, offset: &offset) else { break }
            guard data.startIndex + offset + 10 <= data.endIndex else { break }

            let base = data.startIndex + offset
            let rrtype = (UInt16(data[base]) << 8) | UInt16(data[base + 1])
            let rrttl = (UInt32(data[base + 4]) << 24) | (UInt32(data[base + 5]) << 16)
                | (UInt32(data[base + 6]) << 8) | UInt32(data[base + 7])
            let rdlength = Int((UInt16(data[base + 8]) << 8) | UInt16(data[base + 9]))
            offset += 10

            let rdataOffset = offset
            guard data.startIndex + rdataOffset + rdlength <= data.endIndex else { break }

            if let parsedType = recordType(forTypeNumber: rrtype),
               let record = parseRecord(domain: name, type: parsedType, packet: data, rdataOffset: rdataOffset, rdataLength: rdlength, ttl: rrttl) {
                records.append(record)
            }
            offset += rdlength
        }
        return records
    }
}
