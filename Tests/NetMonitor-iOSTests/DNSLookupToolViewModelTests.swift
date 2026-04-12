import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@MainActor
struct DNSLookupToolViewModelTests {

    @Test func initialState() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        #expect(vm.domain == "")
        #expect(vm.recordType == .a)
        #expect(vm.isLoading == false)
        #expect(vm.result == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialDomainIsSet() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService(), initialDomain: "example.com")
        #expect(vm.domain == "example.com")
    }

    @Test func recordTypesContainsExpectedValues() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        #expect(vm.recordTypes.contains(.a))
        #expect(vm.recordTypes.contains(.aaaa))
        #expect(vm.recordTypes.contains(.mx))
        #expect(vm.recordTypes.contains(.txt))
        #expect(vm.recordTypes.contains(.cname))
        #expect(vm.recordTypes.contains(.ns))
        #expect(vm.recordTypes.count == DNSRecordType.allCases.count)
    }

    @Test func canStartLookupFalseWhenDomainEmpty() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        vm.domain = ""
        #expect(vm.canStartLookup == false)
    }

    @Test func canStartLookupFalseWhenDomainIsWhitespace() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        vm.domain = "   "
        #expect(vm.canStartLookup == false)
    }

    @Test func canStartLookupTrueWithValidDomain() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        vm.domain = "example.com"
        #expect(vm.canStartLookup == true)
    }

    @Test func canStartLookupFalseWhileLoading() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        vm.domain = "example.com"
        vm.isLoading = true
        #expect(vm.canStartLookup == false)
    }

    @Test func clearResultsResetsState() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        vm.result = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 5)
        vm.errorMessage = "timeout"
        vm.clearResults()
        #expect(vm.result == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func lookupSuccessSetsResult() async {
        let mock = MockDNSLookupService()
        mock.mockResult = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 12)
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "example.com"
        await vm.lookup()
        #expect(vm.result != nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func lookupFailureSetsErrorMessage() async {
        let mock = MockDNSLookupService()
        mock.mockResult = nil
        mock.lastError = "DNS resolution failed"
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "nonexistent.invalid"
        await vm.lookup()
        #expect(vm.result == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func lookupIgnoredWhenCannotStart() async {
        let mock = MockDNSLookupService()
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "" // cannot start
        await vm.lookup()
        #expect(vm.result == nil)
        #expect(vm.isLoading == false)
    }
}

// MARK: - Error & Edge Case Tests

@MainActor
struct DNSLookupToolViewModelErrorTests {

    @Test func emptyDomainPreventsLookupFromStarting() async {
        let mock = MockDNSLookupService()
        mock.mockResult = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 1)
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = ""
        await vm.lookup()
        // result must remain nil — lookup was blocked
        #expect(vm.result == nil)
    }

    @Test func whitespaceOnlyDomainPreventsLookup() async {
        let mock = MockDNSLookupService()
        mock.mockResult = DNSQueryResult(domain: "test.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 1)
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "   "
        await vm.lookup()
        #expect(vm.result == nil)
        #expect(vm.isLoading == false)
    }

    @Test func clearResultsResetsAllStateIncludingDomain() async {
        let mock = MockDNSLookupService()
        mock.mockResult = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 5)
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "example.com"
        await vm.lookup()
        #expect(vm.result != nil)

        vm.clearResults()
        #expect(vm.result == nil)
        #expect(vm.errorMessage == nil)
        // domain input is preserved (not part of clearResults)
        #expect(vm.domain == "example.com")
    }

    @Test func clearResultsAfterErrorClearsErrorMessage() async {
        let mock = MockDNSLookupService()
        mock.mockResult = nil
        mock.lastError = "Lookup failed"
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "bad.invalid"
        await vm.lookup()
        #expect(vm.errorMessage != nil)

        vm.clearResults()
        #expect(vm.errorMessage == nil)
        #expect(vm.result == nil)
    }

    @Test func lookupSetsLoadingFalseAfterCompletion() async {
        let mock = MockDNSLookupService()
        mock.mockResult = nil
        let vm = DNSLookupToolViewModel(dnsService: mock)
        vm.domain = "example.com"
        await vm.lookup()
        #expect(vm.isLoading == false)
    }
}
