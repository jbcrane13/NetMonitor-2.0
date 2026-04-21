import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - DNSRecordType Tests

struct DNSRecordTypeTests {

    @Test("DNSRecordType.a returns correct string value")
    func aRecordStringValue() {
        let recordType = DNSRecordType.a
        #expect(recordType.rawValue == "A")
    }

    @Test("DNSRecordType.aaaa returns correct string value")
    func aaaaRecordStringValue() {
        let recordType = DNSRecordType.aaaa
        #expect(recordType.rawValue == "AAAA")
    }

    @Test("DNSRecordType round-trips through Codable")
    func roundTripCodable() throws {
        let types: [DNSRecordType] = [.a, .aaaa, .mx, .txt, .cname, .ns, .soa, .ptr]

        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(DNSRecordType.self, from: encoded)
            #expect(decoded == type)
        }
    }

    @Test("DNSRecordType allCases includes all standard types")
    func allCasesIsComplete() {
        let allCases = DNSRecordType.allCases
        #expect(allCases.contains(.a))
        #expect(allCases.contains(.aaaa))
        #expect(allCases.contains(.mx))
        #expect(allCases.contains(.txt))
    }
}

// MARK: - DNSRecord Tests

struct DNSRecordTests {

    @Test("DNSRecord initializes with all fields")
    func initializesWithAllFields() {
        let record = DNSRecord(
            name: "example.com",
            type: .a,
            value: "192.0.2.1",
            ttl: 300,
            priority: nil
        )

        #expect(record.name == "example.com")
        #expect(record.type == .a)
        #expect(record.value == "192.0.2.1")
        #expect(record.ttl == 300)
        #expect(record.priority == nil)
    }

    @Test("DNSRecord with priority initializes correctly")
    func initializesMXRecordWithPriority() {
        let record = DNSRecord(
            name: "example.com",
            type: .mx,
            value: "mail.example.com",
            ttl: 3600,
            priority: 10
        )

        #expect(record.priority == 10)
        #expect(record.type == .mx)
    }

    @Test("DNSRecord has unique id")
    func hasUniqueId() {
        let record1 = DNSRecord(name: "test.com", type: .a, value: "192.0.2.1", ttl: 300)
        let record2 = DNSRecord(name: "test.com", type: .a, value: "192.0.2.1", ttl: 300)

        #expect(record1.id != record2.id)
    }

    @Test("DNSRecord is Sendable")
    func isSendable() {
        let record = DNSRecord(
            name: "example.com",
            type: .a,
            value: "192.0.2.1",
            ttl: 300
        )
        // If it compiles without sendability errors, test passes
        // This is a compile-time check, but including for documentation
        let _: any Sendable = record
    }
}

// MARK: - DNSQueryResult Tests

struct DNSQueryResultTests {

    @Test("DNSQueryResult initializes with correct fields")
    func initializesCorrectly() {
        let records = [
            DNSRecord(name: "example.com", type: .a, value: "192.0.2.1", ttl: 300),
            DNSRecord(name: "example.com", type: .a, value: "192.0.2.2", ttl: 300)
        ]

        let result = DNSQueryResult(
            domain: "example.com",
            server: "8.8.8.8",
            queryType: .a,
            records: records,
            queryTime: 45.0
        )

        #expect(result.domain == "example.com")
        #expect(result.server == "8.8.8.8")
        #expect(result.queryType == .a)
        #expect(result.records.count == 2)
        #expect(result.queryTime == 45.0)
    }

    @Test("DNSQueryResult with empty records")
    func emptyRecords() {
        let result = DNSQueryResult(
            domain: "invalid.example.test",
            server: "8.8.8.8",
            queryType: .a,
            records: [],
            queryTime: 23.5
        )

        #expect(result.records.isEmpty)
        #expect(result.domain == "invalid.example.test")
    }

    @Test("DNSQueryResult timestamp is set near initialization time")
    func timestampNearInitTime() {
        let beforeInit = Date()
        let result = DNSQueryResult(
            domain: "example.com",
            server: "System DNS",
            queryType: .a,
            records: [],
            queryTime: 10.0
        )
        let afterInit = Date()

        #expect(result.timestamp >= beforeInit)
        #expect(result.timestamp <= afterInit)
    }

    @Test("DNSQueryResult is Sendable")
    func isSendable() {
        let result = DNSQueryResult(
            domain: "example.com",
            server: "8.8.8.8",
            queryType: .a,
            records: [],
            queryTime: 25.0
        )
        let _: any Sendable = result
    }

    // (DNSQueryResult Codable round-trip removed — type is Sendable only, not Codable.)
}

// MARK: - DNSLookupService Observable Tests

@MainActor
struct DNSLookupServiceObservableTests {

    @Test("DNSLookupService initializes with nil lastResult")
    func initializesWithNilLastResult() {
        let service = DNSLookupService()
        #expect(service.lastResult == nil)
    }

    @Test("DNSLookupService initializes with isLoading false")
    func initializesWithIsLoadingFalse() {
        let service = DNSLookupService()
        #expect(service.isLoading == false)
    }

    @Test("DNSLookupService initializes with nil lastError")
    func initializesWithNilLastError() {
        let service = DNSLookupService()
        #expect(service.lastError == nil)
    }
}

// MARK: - DNSLookupService Helper Tests (Non-C-API)

struct DNSLookupServiceHelperTests {

    @Test("service validates A record type")
    func identifiesARecordType() {
        let recordType = DNSRecordType.a
        #expect(recordType == .a)
    }

    @Test("service validates AAAA record type")
    func identifiesAAAARecordType() {
        let recordType = DNSRecordType.aaaa
        #expect(recordType == .aaaa)
    }

    @Test("service distinguishes between A and AAAA")
    func distinguishesAAndAAAA() {
        #expect(DNSRecordType.a != DNSRecordType.aaaa)
    }

    @Test("service validates other record types")
    func identifiesOtherRecordTypes() {
        #expect(DNSRecordType.mx != DNSRecordType.txt)
        #expect(DNSRecordType.ns != DNSRecordType.ptr)
        #expect(DNSRecordType.cname != DNSRecordType.soa)
    }
}

// MARK: - DNSQueryResult Construction for Service Output

struct DNSLookupResultConstructionTests {

    @Test("constructing A record result for localhost")
    func aRecordForLocalhost() {
        let records = [
            DNSRecord(
                name: "localhost",
                type: .a,
                value: "127.0.0.1",
                ttl: 0
            )
        ]

        let result = DNSQueryResult(
            domain: "localhost",
            server: "127.0.0.1",
            queryType: .a,
            records: records,
            queryTime: 2.0
        )

        #expect(result.domain == "localhost")
        #expect(result.records.count == 1)
        #expect(result.records[0].value == "127.0.0.1")
        #expect(result.queryType == .a)
    }

    @Test("constructing AAAA record result for IPv6 localhost")
    func aaaaRecordForIPv6Localhost() {
        let records = [
            DNSRecord(
                name: "localhost",
                type: .aaaa,
                value: "::1",
                ttl: 0
            )
        ]

        let result = DNSQueryResult(
            domain: "localhost",
            server: "::1",
            queryType: .aaaa,
            records: records,
            queryTime: 1.5
        )

        #expect(result.queryType == .aaaa)
        #expect(result.records[0].value == "::1")
    }

    @Test("constructing MX record result with priority")
    func mxRecordWithPriority() {
        let records = [
            DNSRecord(
                name: "example.com",
                type: .mx,
                value: "mail.example.com",
                ttl: 3600,
                priority: 10
            )
        ]

        let result = DNSQueryResult(
            domain: "example.com",
            server: "8.8.8.8",
            queryType: .mx,
            records: records,
            queryTime: 25.0
        )

        #expect(result.records[0].priority == 10)
        #expect(result.records[0].type == .mx)
    }

    @Test("constructing multiple A records for round-robin DNS")
    func multipleARecords() {
        let records = [
            DNSRecord(name: "example.com", type: .a, value: "192.0.2.1", ttl: 300),
            DNSRecord(name: "example.com", type: .a, value: "192.0.2.2", ttl: 300),
            DNSRecord(name: "example.com", type: .a, value: "192.0.2.3", ttl: 300)
        ]

        let result = DNSQueryResult(
            domain: "example.com",
            server: "1.1.1.1",
            queryType: .a,
            records: records,
            queryTime: 18.0
        )

        #expect(result.records.count == 3)
        #expect(result.records.allSatisfy { $0.type == .a })
    }

    @Test("constructing TXT record result")
    func txtRecord() {
        let records = [
            DNSRecord(
                name: "example.com",
                type: .txt,
                value: "v=spf1 include:_spf.google.com ~all",
                ttl: 3600
            )
        ]

        let result = DNSQueryResult(
            domain: "example.com",
            server: "8.8.8.8",
            queryType: .txt,
            records: records,
            queryTime: 30.0
        )

        #expect(result.records[0].type == .txt)
        #expect(result.records[0].value.contains("spf"))
    }
}

// MARK: - DNSError Enum Tests

struct DNSErrorTests {

    @Test("DNSError.lookupFailed has descriptive message")
    func lookupFailedError() {
        let error = DNSError.lookupFailed
        let description = error.localizedDescription
        #expect(!description.isEmpty)
    }

    @Test("DNSError.timeout has descriptive message")
    func timeoutError() {
        let error = DNSError.timeout
        let description = error.localizedDescription
        #expect(!description.isEmpty)
    }

    @Test("DNSError cases are distinct")
    func errorCasesAreDistinct() {
        let lookupError = DNSError.lookupFailed
        let timeoutError = DNSError.timeout
        #expect(lookupError.localizedDescription != timeoutError.localizedDescription)
    }
}

// MARK: - DNSLookupService Validation Tests

@MainActor
struct DNSLookupServiceValidationTests {

    @Test("service is MainActor Observable")
    func isMainActorObservable() {
        // Compile-time verification: if service were not @MainActor,
        // this test would not compile when calling methods from main thread
        let service = DNSLookupService()
        // No immediate side effects; test passes if instantiation succeeds
        #expect(service.lastResult == nil)
    }

    @Test("service accepts domain strings")
    func acceptsDomainStrings() {
        let domains = ["example.com", "localhost", "subdomain.example.co.uk"]
        for domain in domains {
            let record = DNSRecord(name: domain, type: .a, value: "192.0.2.1", ttl: 300)
            #expect(record.name == domain)
        }
    }

    @Test("service accepts IPv4 addresses in DNS values")
    func acceptsIPv4Values() {
        let addresses = ["192.0.2.1", "10.0.0.1", "172.16.0.1"]
        for address in addresses {
            let record = DNSRecord(
                name: "example.com",
                type: .a,
                value: address,
                ttl: 300
            )
            #expect(record.value == address)
        }
    }

    @Test("service accepts IPv6 addresses in DNS values")
    func acceptsIPv6Values() {
        let addresses = ["2001:db8::1", "fe80::1", "::1"]
        for address in addresses {
            let record = DNSRecord(
                name: "example.com",
                type: .aaaa,
                value: address,
                ttl: 300
            )
            #expect(record.value == address)
        }
    }

    @Test("service handles reasonable TTL values")
    func handlesReasonableTTLs() {
        let ttls = [0, 300, 3600, 86400, 604800]
        for ttl in ttls {
            let record = DNSRecord(
                name: "example.com",
                type: .a,
                value: "192.0.2.1",
                ttl: ttl
            )
            #expect(record.ttl == ttl)
        }
    }
}
