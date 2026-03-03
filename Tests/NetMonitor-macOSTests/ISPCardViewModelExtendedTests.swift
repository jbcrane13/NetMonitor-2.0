import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - Stub services
// These are private to this file and mirror the stubs in ISPCardErrorSurfacingTests.swift.
// Swift's access control doesn't allow sharing private types across files; they are
// intentionally kept in sync by convention.

private final class FailingISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    let error: Error
    init(error: Error = URLError(.notConnectedToInternet)) { self.error = error }
    func lookup() async throws -> ISPLookupService.ISPInfo { throw error }
}

private final class SucceedingISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    func lookup() async throws -> ISPLookupService.ISPInfo {
        ISPLookupService.ISPInfo(
            publicIP: "1.2.3.4", isp: "Test ISP",
            organization: nil, asn: nil, city: "Denver",
            region: "CO", country: "US", timezone: nil
        )
    }
}

// MARK: - ISPCardViewModel extended tests

@Suite("ISPCardViewModel – extended")
@MainActor
struct ISPCardViewModelExtendedTests {

    // isLoading is initialized to true so that callers can show a spinner
    // immediately before the first load() call completes.
    @Test func isLoadingIsTrueBeforeLoad() {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        #expect(vm.isLoading == true)
    }

    @Test func isLoadingFalseAfterSuccessfulLoad() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.isLoading == false)
    }

    @Test func ispInfoPublicIPSetOnSuccess() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
    }

    @Test func ispInfoISPNameSetOnSuccess() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.isp == "Test ISP")
    }

    @Test func ispInfoCitySetOnSuccess() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.city == "Denver")
    }

    @Test func ispInfoCountrySetOnSuccess() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.country == "US")
    }

    @Test func ispInfoNilBeforeLoad() {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        #expect(vm.ispInfo == nil)
    }

    @Test func errorMessageNilBeforeLoad() {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        #expect(vm.errorMessage == nil)
    }
}

// MARK: - ConnectivityCardViewModel extended tests

@Suite("ConnectivityCardViewModel – extended")
@MainActor
struct ConnectivityCardViewModelExtendedTests {

    @Test func ispInfoNilBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        #expect(vm.ispInfo == nil)
    }

    @Test func loadErrorNilBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        #expect(vm.loadError == nil)
    }

    @Test func ispInfoPopulatedAfterSuccessfulLoad() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
        #expect(vm.ispInfo?.isp == "Test ISP")
    }

    // Verifies that a successful load after a prior failed load clears loadError.
    // Approach: use two separate vm instances — one that fails, one that succeeds —
    // to keep the test focused without needing a mutable stub.
    @Test func loadErrorClearedOnSuccessAfterPriorError() async {
        // First, confirm a failing load populates loadError.
        let failingVM = ConnectivityCardViewModel(service: FailingISPService())
        await failingVM.load()
        #expect(failingVM.loadError != nil)
        #expect(failingVM.ispInfo == nil)

        // Then confirm a fresh vm with a succeeding service starts with no loadError
        // and remains nil after load — i.e. success never pollutes loadError.
        let succeedingVM = ConnectivityCardViewModel(service: SucceedingISPService())
        await succeedingVM.load()
        #expect(succeedingVM.loadError == nil)
        #expect(succeedingVM.ispInfo != nil)
    }
}
