import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for `DNSWireFormat`'s RFC 1035 parsers, using hand-assembled wire-format
/// bytes rather than live network calls. Uncompressed names are built with a small
/// local `encodeName` helper (a separate code path from the parser under test).
struct DNSWireFormatTests {

    // MARK: - Test helper (encoder — deliberately independent of the parser)

    private func encodeName(_ name: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for label in name.split(separator: ".") {
            let labelBytes = Array(label.utf8)
            bytes.append(UInt8(labelBytes.count))
            bytes.append(contentsOf: labelBytes)
        }
        bytes.append(0) // root
        return bytes
    }

    // MARK: - A / AAAA

    @Test("parses an A record's 4-byte rdata into a dotted-quad address")
    func parsesARecord() {
        let rdata = Data([93, 184, 216, 34])
        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .a, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 300)
        #expect(record?.value == "93.184.216.34")
        #expect(record?.ttl == 300)
        #expect(record?.type == .a)
    }

    @Test("parses an AAAA record's 16-byte rdata into an IPv6 address")
    func parsesAAAARecord() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = 1 // ::1
        let rdata = Data(bytes)
        let record = DNSWireFormat.parseRecord(domain: "localhost", type: .aaaa, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 60)
        #expect(record?.value == "::1")
        #expect(record?.type == .aaaa)
    }

    @Test("rejects an A record with the wrong rdata length")
    func rejectsMalformedARecord() {
        let rdata = Data([1, 2, 3]) // only 3 bytes
        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .a, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 300)
        #expect(record == nil)
    }

    // MARK: - MX

    @Test("parses an MX record's priority and mail exchange name")
    func parsesMXRecord() {
        var rdata = Data([0x00, 0x0A]) // priority 10
        rdata.append(contentsOf: encodeName("mail.example.com"))

        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .mx, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 3600)
        #expect(record?.priority == 10)
        #expect(record?.value == "mail.example.com")
    }

    // MARK: - TXT (multi-string)

    @Test("parses a TXT record with multiple character-strings, newline-joined")
    func parsesMultiStringTXTRecord() {
        let first = "v=spf1"
        let second = "include:_spf.google.com"
        var rdata = Data()
        rdata.append(UInt8(first.utf8.count))
        rdata.append(contentsOf: first.utf8)
        rdata.append(UInt8(second.utf8.count))
        rdata.append(contentsOf: second.utf8)

        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .txt, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 3600)
        #expect(record?.value == "v=spf1\ninclude:_spf.google.com")
    }

    // MARK: - SOA

    @Test("parses all seven SOA fields")
    func parsesSOARecord() {
        var rdata = Data()
        rdata.append(contentsOf: encodeName("ns1.example.com"))
        rdata.append(contentsOf: encodeName("admin.example.com"))
        for value: UInt32 in [2024_010_100, 3600, 900, 604_800, 300] {
            rdata.append(UInt8(value >> 24))
            rdata.append(UInt8((value >> 16) & 0xFF))
            rdata.append(UInt8((value >> 8) & 0xFF))
            rdata.append(UInt8(value & 0xFF))
        }

        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .soa, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 3600)
        let value = record?.value ?? ""
        #expect(value.contains("ns1.example.com"))
        #expect(value.contains("admin.example.com"))
        #expect(value.contains("Serial: 2024010100"))
        #expect(value.contains("Refresh: 3600"))
        #expect(value.contains("Retry: 900"))
        #expect(value.contains("Expire: 604800"))
        #expect(value.contains("Minimum: 300"))
    }

    // MARK: - SRV

    @Test("parses SRV priority, weight, port and target")
    func parsesSRVRecord() {
        var rdata = Data()
        rdata.append(contentsOf: [0x00, 0x0A]) // priority 10
        rdata.append(contentsOf: [0x00, 0x14]) // weight 20
        rdata.append(contentsOf: [0x01, 0xBB]) // port 443
        rdata.append(contentsOf: encodeName("sip.example.com"))

        let record = DNSWireFormat.parseRecord(
            domain: "_sip._tcp.example.com", type: .srv, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 60
        )
        #expect(record?.priority == 10)
        #expect(record?.value.contains("sip.example.com:443") == true)
        #expect(record?.value.contains("weight 20") == true)
    }

    // MARK: - CAA

    @Test("parses a CAA issue record")
    func parsesCAARecord() {
        var rdata = Data([0]) // flags = 0
        let tag = "issue"
        rdata.append(UInt8(tag.utf8.count))
        rdata.append(contentsOf: tag.utf8)
        rdata.append(contentsOf: "letsencrypt.org".utf8)

        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .caa, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 3600)
        #expect(record?.value.contains("issue") == true)
        #expect(record?.value.contains("letsencrypt.org") == true)
    }

    // MARK: - HTTPS (raw rdata, by design — see issue #322)

    @Test("HTTPS/SVCB rdata is surfaced as raw hex rather than parsed")
    func httpsRecordIsRawHex() {
        let rdata = Data([0x00, 0x01, 0x02, 0x03])
        let record = DNSWireFormat.parseRecord(domain: "example.com", type: .https, packet: rdata, rdataOffset: 0, rdataLength: rdata.count, ttl: 300)
        #expect(record?.value == "raw rdata: 00010203")
    }

    // MARK: - Name compression / hop limit

    @Test("decompresses a name via a pointer to an earlier valid name")
    func decompressesPointerToEarlierName() {
        var packet = Data()
        packet.append(contentsOf: encodeName("example.com")) // offset 0
        let pointerOffset = packet.count
        packet.append(contentsOf: [0xC0, 0x00]) // pointer -> offset 0

        var offset = pointerOffset
        let name = DNSWireFormat.parseDNSName(from: packet, offset: &offset)
        #expect(name == "example.com")
        #expect(offset == pointerOffset + 2)
    }

    @Test("rejects a self-referential compression pointer instead of hanging")
    func rejectsSelfReferentialPointer() {
        // Byte 0xC0,0x00 at offset 0 points at itself.
        let packet = Data([0xC0, 0x00])
        var offset = 0
        let name = DNSWireFormat.parseDNSName(from: packet, offset: &offset)
        #expect(name == nil)
    }

    @Test("rejects a pointer chain that exceeds the jump limit instead of hanging")
    func rejectsExcessivePointerChain() {
        // Each 2-byte slot at index i (i < 30) points to slot i+1; the last slot
        // points to itself, guaranteeing the jump limit is hit before termination.
        var packet = Data(repeating: 0, count: 62)
        for i in stride(from: 0, to: 60, by: 2) {
            let target = i + 2
            packet[i] = UInt8(0xC0 | (target >> 8))
            packet[i + 1] = UInt8(target & 0xFF)
        }
        packet[60] = 0xC0
        packet[61] = 60 // self-reference at the end

        var offset = 0
        let name = DNSWireFormat.parseDNSName(from: packet, offset: &offset)
        #expect(name == nil)
    }

    // MARK: - Reverse lookup names

    @Test("builds an in-addr.arpa name for an IPv4 address")
    func buildsIPv4ReverseName() {
        #expect(DNSWireFormat.reverseLookupName(for: "192.0.2.1") == "1.2.0.192.in-addr.arpa")
    }

    @Test("builds an ip6.arpa name for an IPv6 address")
    func buildsIPv6ReverseName() {
        let expected = "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa"
        #expect(DNSWireFormat.reverseLookupName(for: "2001:db8::1") == expected)
    }

    @Test("returns nil for a string that isn't an IPv4 or IPv6 address")
    func reverseLookupNameNilForNonIP() {
        #expect(DNSWireFormat.reverseLookupName(for: "example.com") == nil)
    }

    // MARK: - typeNumber <-> recordType round-trip

    @Test("typeNumber and recordType(forTypeNumber:) round-trip for every DNSRecordType")
    func typeNumberRoundTrips() {
        for type in DNSRecordType.allCases {
            let number = DNSWireFormat.typeNumber(for: type)
            #expect(DNSWireFormat.recordType(forTypeNumber: number) == type)
        }
    }

    // MARK: - Full response parsing (used by DNSUDPResolver)

    @Test("parseResponse throws nxdomain when RCODE is 3")
    func parseResponseThrowsNXDOMAIN() throws {
        var packet = Data()
        packet.append(contentsOf: [0x12, 0x34]) // ID
        packet.append(contentsOf: [0x81, 0x83]) // QR=1, RD=1, RCODE=3 (NXDOMAIN)
        packet.append(contentsOf: [0x00, 0x01]) // QDCOUNT
        packet.append(contentsOf: [0x00, 0x00]) // ANCOUNT
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: encodeName("nonexistent.example"))
        packet.append(contentsOf: [0x00, 0x01]) // QTYPE A
        packet.append(contentsOf: [0x00, 0x01]) // QCLASS IN

        #expect(throws: DNSError.self) {
            _ = try DNSWireFormat.parseResponse(packet, expectedID: 0x1234, domain: "nonexistent.example", type: .a)
        }
    }

    @Test("parseResponse throws noRecords when RCODE is 0 with an empty answer section")
    func parseResponseThrowsNoRecordsForEmptyAnswer() {
        var packet = Data()
        packet.append(contentsOf: [0x00, 0x01]) // ID
        packet.append(contentsOf: [0x81, 0x80]) // QR=1, RD=1, RCODE=0
        packet.append(contentsOf: [0x00, 0x01]) // QDCOUNT
        packet.append(contentsOf: [0x00, 0x00]) // ANCOUNT = 0
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: encodeName("example.com"))
        packet.append(contentsOf: [0x00, 0x0F]) // QTYPE MX
        packet.append(contentsOf: [0x00, 0x01]) // QCLASS IN

        #expect(throws: DNSError.self) {
            _ = try DNSWireFormat.parseResponse(packet, expectedID: 0x0001, domain: "example.com", type: .mx)
        }
    }

    @Test("parseResponse parses a real answer record")
    func parseResponseParsesAnswer() throws {
        var packet = Data()
        packet.append(contentsOf: [0x00, 0x02]) // ID
        packet.append(contentsOf: [0x81, 0x80]) // QR=1, RD=1, RCODE=0
        packet.append(contentsOf: [0x00, 0x01]) // QDCOUNT
        packet.append(contentsOf: [0x00, 0x01]) // ANCOUNT
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: [0x00, 0x00])
        packet.append(contentsOf: encodeName("example.com"))
        packet.append(contentsOf: [0x00, 0x01]) // QTYPE A
        packet.append(contentsOf: [0x00, 0x01]) // QCLASS IN

        // Answer: name (pointer back to question's QNAME at offset 12), TYPE A, CLASS IN, TTL, RDLENGTH, RDATA
        packet.append(contentsOf: [0xC0, 0x0C]) // pointer to offset 12 (the QNAME)
        packet.append(contentsOf: [0x00, 0x01]) // TYPE A
        packet.append(contentsOf: [0x00, 0x01]) // CLASS IN
        packet.append(contentsOf: [0x00, 0x00, 0x01, 0x2C]) // TTL = 300
        packet.append(contentsOf: [0x00, 0x04]) // RDLENGTH = 4
        packet.append(contentsOf: [93, 184, 216, 34])

        let records = try DNSWireFormat.parseResponse(packet, expectedID: 0x0002, domain: "example.com", type: .a)
        #expect(records.count == 1)
        #expect(records[0].value == "93.184.216.34")
        #expect(records[0].ttl == 300)
        #expect(records[0].name == "example.com")
    }

    // MARK: - Query construction

    @Test("buildQuery encodes id, QDCOUNT=1, the name and the qtype/qclass")
    func buildQueryEncodesExpectedFields() {
        let packet = DNSWireFormat.buildQuery(id: 0xABCD, domain: "example.com", type: .mx)
        #expect(packet.count >= 12)
        #expect(packet[0] == 0xAB && packet[1] == 0xCD)
        #expect(packet[4] == 0x00 && packet[5] == 0x01) // QDCOUNT = 1

        var offset = 12
        let name = DNSWireFormat.parseDNSName(from: packet, offset: &offset)
        #expect(name == "example.com")

        let qtype = (UInt16(packet[offset]) << 8) | UInt16(packet[offset + 1])
        #expect(qtype == DNSWireFormat.typeNumber(for: .mx))
    }
}
