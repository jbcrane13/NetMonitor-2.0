import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("DNSLookupToolViewModel")
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
        #expect(vm.recordTypes.count == 6)
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
