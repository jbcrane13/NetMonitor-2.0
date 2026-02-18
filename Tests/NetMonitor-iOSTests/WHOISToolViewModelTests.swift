import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("WHOISToolViewModel")
@MainActor
struct WHOISToolViewModelTests {

    @Test func initialState() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        #expect(vm.domain == "")
        #expect(vm.isLoading == false)
        #expect(vm.result == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialDomainIsSet() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService(), initialDomain: "example.com")
        #expect(vm.domain == "example.com")
    }

    @Test func canStartLookupFalseWhenDomainEmpty() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        vm.domain = ""
        #expect(vm.canStartLookup == false)
    }

    @Test func canStartLookupFalseWhenDomainIsWhitespace() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        vm.domain = "   "
        #expect(vm.canStartLookup == false)
    }

    @Test func canStartLookupTrueWithValidDomain() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        vm.domain = "example.com"
        #expect(vm.canStartLookup == true)
    }

    @Test func canStartLookupFalseWhileLoading() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        vm.domain = "example.com"
        vm.isLoading = true
        #expect(vm.canStartLookup == false)
    }

    @Test func clearResultsResetsState() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        vm.result = WHOISResult(query: "example.com", rawData: "raw data")
        vm.errorMessage = "some error"
        vm.clearResults()
        #expect(vm.result == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func lookupSuccessSetsResult() async {
        let mock = MockWHOISService()
        mock.mockResult = WHOISResult(query: "example.com", registrar: "IANA", rawData: "raw")
        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = "example.com"
        await vm.lookup()
        #expect(vm.result != nil)
        #expect(vm.result?.query == "example.com")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func lookupFailureSetsErrorMessage() async {
        let mock = MockWHOISService()
        mock.shouldThrow = true
        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = "example.com"
        await vm.lookup()
        #expect(vm.result == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func lookupIgnoredWhenDomainEmpty() async {
        let mock = MockWHOISService()
        let vm = WHOISToolViewModel(whoisService: mock)
        vm.domain = ""
        await vm.lookup()
        #expect(vm.result == nil)
        #expect(vm.isLoading == false)
    }
}
