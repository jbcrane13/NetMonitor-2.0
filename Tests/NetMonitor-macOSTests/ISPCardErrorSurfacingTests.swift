import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - Stub services

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

// MARK: - ISPCardViewModel error surfacing tests

@MainActor
struct ISPCardViewModelErrorTests {

    @Test func errorMessageSetWhenLookupFails() async {
        let vm = ISPCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.ispInfo == nil)
        #expect(vm.isLoading == false)
    }

    @Test func errorMessageNilWhenLookupSucceeds() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.ispInfo?.isp == "Test ISP")
        #expect(vm.isLoading == false)
    }

    @Test func errorMessageContainsLocalizedDescription() async {
        let vm = ISPCardViewModel(service: FailingISPService(error: ISPLookupError.rateLimited))
        await vm.load()
        #expect(vm.errorMessage == ISPLookupError.rateLimited.errorDescription)
    }
}

// MARK: - ConnectivityCardViewModel error surfacing tests

@MainActor
struct ConnectivityCardViewModelErrorTests {

    @Test func loadErrorSetWhenLookupFails() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.loadError != nil)
        #expect(vm.ispInfo == nil)
    }

    @Test func loadErrorNilWhenLookupSucceeds() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.loadError == nil)
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
    }

    @Test func loadErrorContainsLocalizedDescription() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService(error: ISPLookupError.invalidResponse))
        await vm.load()
        #expect(vm.loadError == ISPLookupError.invalidResponse.errorDescription)
    }
}
