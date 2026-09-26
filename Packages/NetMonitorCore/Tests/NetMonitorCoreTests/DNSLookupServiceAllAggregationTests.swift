import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for `DNSLookupService.performAll`, the aggregation core behind the "All
/// record types" mode (issue #322). A fake `fetch` closure stands in for the real
/// network path so these run deterministically offline.
struct DNSLookupServiceAllAggregationTests {

    @Test("aggregates successful per-type results, preserving requested type order")
    func aggregatesSuccessfulResults() async {
        let types: [DNSRecordType] = [.a, .aaaa, .mx]
        let fake: @Sendable (String, DNSRecordType, String?) async throws -> [DNSRecord] = { domain, type, _ in
            switch type {
            case .a: return [DNSRecord(name: domain, type: .a, value: "1.2.3.4", ttl: 60)]
            case .aaaa: return [DNSRecord(name: domain, type: .aaaa, value: "::1", ttl: 60)]
            case .mx: return [DNSRecord(name: domain, type: .mx, value: "mail.example.com", ttl: 3600, priority: 10)]
            default: return []
            }
        }

        let outcomes = await DNSLookupService.performAll(domain: "example.com", types: types, server: nil, fetch: fake)

        #expect(outcomes.count == 3)
        #expect(outcomes.map(\.type) == types)
        #expect(outcomes[0].records.first?.value == "1.2.3.4")
        #expect(outcomes[1].records.first?.value == "::1")
        #expect(outcomes[2].records.first?.priority == 10)
        #expect(outcomes.allSatisfy { $0.errorDescription == nil })
    }

    @Test("captures a per-type failure without failing the whole aggregation")
    func toleratesPerTypeFailure() async {
        let types: [DNSRecordType] = [.a, .caa]
        let fake: @Sendable (String, DNSRecordType, String?) async throws -> [DNSRecord] = { domain, type, _ in
            if type == .caa {
                throw DNSError.noRecords(domain: domain, type: .caa)
            }
            return [DNSRecord(name: domain, type: .a, value: "1.2.3.4", ttl: 60)]
        }

        let outcomes = await DNSLookupService.performAll(domain: "example.com", types: types, server: nil, fetch: fake)

        #expect(outcomes.count == 2)
        let aOutcome = outcomes.first { $0.type == .a }
        let caaOutcome = outcomes.first { $0.type == .caa }
        #expect(aOutcome?.records.isEmpty == false)
        #expect(aOutcome?.errorDescription == nil)
        #expect(caaOutcome?.records.isEmpty == true)
        #expect(caaOutcome?.errorDescription != nil)
    }

    @Test("every type failing surfaces an outcome list with no records anywhere")
    func allTypesFailing() async {
        let types: [DNSRecordType] = [.a, .aaaa]
        let fake: @Sendable (String, DNSRecordType, String?) async throws -> [DNSRecord] = { _, _, _ in
            throw DNSError.timeout
        }

        let outcomes = await DNSLookupService.performAll(domain: "example.com", types: types, server: nil, fetch: fake)

        #expect(outcomes.count == 2)
        #expect(outcomes.flatMap(\.records).isEmpty)
        #expect(outcomes.allSatisfy { $0.errorDescription != nil })
    }
}
