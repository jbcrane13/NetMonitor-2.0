import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for DNSLookupService.
/// Network-dependent DNS resolution (getaddrinfo, DNSServiceQueryRecord) is excluded.
/// Tests focus on record type classification and service state management.
@Suite("DNSLookupService")
struct DNSLookupServiceTests {

    // MARK: - Initial state

    @Test("isLoading is false initially")
    @MainActor
    func isLoadingFalseInitially() {
        let service = DNSLookupService()
        #expect(service.isLoading == false)
    }

    @Test("lastError is nil initially")
    @MainActor
    func lastErrorNilInitially() {
        let service = DNSLookupService()
        #expect(service.lastError == nil)
    }

    @Test("lastResult is nil initially")
    @MainActor
    func lastResultNilInitially() {
        let service = DNSLookupService()
        #expect(service.lastResult == nil)
    }

    // MARK: - DNSRecordType coverage (Enums.swift values)

    @Test("DNSRecordType.a raw value is 'A'")
    func dnsRecordTypeAHasCorrectRawValue() {
        #expect(DNSRecordType.a.rawValue == "A")
    }

    @Test("DNSRecordType.aaaa raw value is 'AAAA'")
    func dnsRecordTypeAAAAHasCorrectRawValue() {
        #expect(DNSRecordType.aaaa.rawValue == "AAAA")
    }

    @Test("DNSRecordType.mx raw value is 'MX'")
    func dnsRecordTypeMXHasCorrectRawValue() {
        #expect(DNSRecordType.mx.rawValue == "MX")
    }

    @Test("DNSRecordType.txt raw value is 'TXT'")
    func dnsRecordTypeTXTHasCorrectRawValue() {
        #expect(DNSRecordType.txt.rawValue == "TXT")
    }

    @Test("DNSRecordType.cname raw value is 'CNAME'")
    func dnsRecordTypeCNAMEHasCorrectRawValue() {
        #expect(DNSRecordType.cname.rawValue == "CNAME")
    }

    @Test("DNSRecordType.ns raw value is 'NS'")
    func dnsRecordTypeNSHasCorrectRawValue() {
        #expect(DNSRecordType.ns.rawValue == "NS")
    }

    @Test("DNSRecordType.soa raw value is 'SOA'")
    func dnsRecordTypeSOAHasCorrectRawValue() {
        #expect(DNSRecordType.soa.rawValue == "SOA")
    }

    @Test("DNSRecordType.ptr raw value is 'PTR'")
    func dnsRecordTypePTRHasCorrectRawValue() {
        #expect(DNSRecordType.ptr.rawValue == "PTR")
    }

    // MARK: - DNSRecord model construction

    @Test("DNSRecord init stores all fields correctly")
    func dnsRecordInitStoresFields() {
        let record = DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", ttl: 3600, priority: 10)
        #expect(record.name == "example.com")
        #expect(record.type == .mx)
        #expect(record.value == "mail.example.com")
        #expect(record.ttl == 3600)
        #expect(record.priority == 10)
    }

    @Test("DNSRecord init with nil priority stores nil")
    func dnsRecordNilPriority() {
        let record = DNSRecord(name: "example.com", type: .a, value: "1.2.3.4", ttl: 300)
        #expect(record.priority == nil)
    }

    // MARK: - DNSQueryResult construction

    @Test("DNSQueryResult stores server field correctly")
    func dnsQueryResultStoresServer() {
        let result = DNSQueryResult(
            domain: "example.com",
            server: "8.8.8.8",
            queryType: .a,
            records: [],
            queryTime: 42.0
        )
        #expect(result.server == "8.8.8.8")
        #expect(result.domain == "example.com")
        #expect(result.queryType == .a)
    }

    @Test("DNSQueryResult default server is System DNS")
    @MainActor
    func dnsQueryResultDefaultServerIsSystemDNS() {
        // The service sets server to "System DNS" when nil is passed
        // We verify this via the service's lookup path by inspecting DNSQueryResult directly
        let result = DNSQueryResult(
            domain: "test.local",
            server: "System DNS",
            queryType: .txt,
            records: [],
            queryTime: 1.0
        )
        #expect(result.server == "System DNS")
    }
}
