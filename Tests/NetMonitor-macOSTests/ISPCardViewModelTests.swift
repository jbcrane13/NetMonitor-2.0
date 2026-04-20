import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - Stub services

private final class StubISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    let info: ISPLookupService.ISPInfo?
    let error: Error?

    init(
        info: ISPLookupService.ISPInfo? = nil,
        error: Error? = nil
    ) {
        self.info = info
        self.error = error
    }

    func lookup() async throws -> ISPLookupService.ISPInfo {
        if let error { throw error }
        return info ?? ISPLookupService.ISPInfo(
            publicIP: "93.184.216.34", isp: "Example ISP",
            organization: "AS13335 Cloudflare", asn: "AS13335",
            city: "Boston", region: "MA", country: "US",
            timezone: "America/New_York"
        )
    }
}

/// Tracks how many times lookup() is called, for verifying refresh behavior.
private final class CountingISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.withLock { _callCount } }

    func lookup() async throws -> ISPLookupService.ISPInfo {
        lock.withLock { _callCount += 1 }
        return ISPLookupService.ISPInfo(
            publicIP: "10.0.0.\(callCount)", isp: "Counting ISP",
            organization: nil, asn: nil, city: nil,
            region: nil, country: "US", timezone: nil
        )
    }
}

// MARK: - ISPCardViewModelTests

@MainActor
struct ISPCardViewModelTests {

    // MARK: - Initial state

    @Test("Initial state has nil ispInfo")
    func initialStateISPInfoNil() {
        let vm = ISPCardViewModel(service: StubISPService())
        #expect(vm.ispInfo == nil)
    }

    @Test("Initial state has isLoading true")
    func initialStateIsLoadingTrue() {
        let vm = ISPCardViewModel(service: StubISPService())
        #expect(vm.isLoading == true)
    }

    @Test("Initial state has nil errorMessage")
    func initialStateErrorMessageNil() {
        let vm = ISPCardViewModel(service: StubISPService())
        #expect(vm.errorMessage == nil)
    }

    // MARK: - ISP name populated

    @Test("ISP name populated from lookup service")
    func ispNamePopulated() async {
        let vm = ISPCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.isp == "Example ISP")
    }

    // MARK: - AS number populated

    @Test("AS number populated from lookup service")
    func asNumberPopulated() async {
        let vm = ISPCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.asn == "AS13335")
    }

    @Test("Organization populated from lookup service")
    func organizationPopulated() async {
        let vm = ISPCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.organization == "AS13335 Cloudflare")
    }

    // MARK: - Public IP displayed

    @Test("Public IP populated from lookup service")
    func publicIPPopulated() async {
        let vm = ISPCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "93.184.216.34")
    }

    // MARK: - Error state

    @Test("Error from lookup sets errorMessage")
    func errorFromLookupSetsErrorMessage() async {
        let vm = ISPCardViewModel(service: StubISPService(error: URLError(.timedOut)))
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.ispInfo == nil)
    }

    @Test("Error message contains localized description of the thrown error")
    func errorMessageMatchesLocalizedDescription() async {
        let err = URLError(.notConnectedToInternet)
        let vm = ISPCardViewModel(service: StubISPService(error: err))
        await vm.load()
        #expect(vm.errorMessage == err.localizedDescription)
    }

    @Test("ISPLookupError.rateLimited surfaces its errorDescription")
    func rateLimitedErrorSurfaced() async {
        let vm = ISPCardViewModel(service: StubISPService(error: ISPLookupError.rateLimited))
        await vm.load()
        #expect(vm.errorMessage == ISPLookupError.rateLimited.errorDescription)
    }

    @Test("ISPLookupError.invalidResponse surfaces its errorDescription")
    func invalidResponseErrorSurfaced() async {
        let vm = ISPCardViewModel(service: StubISPService(error: ISPLookupError.invalidResponse))
        await vm.load()
        #expect(vm.errorMessage == ISPLookupError.invalidResponse.errorDescription)
    }

    // MARK: - Loading state during fetch

    @Test("isLoading becomes false after successful load")
    func isLoadingFalseAfterSuccess() async {
        let vm = ISPCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.isLoading == false)
    }

    @Test("isLoading becomes false after failed load")
    func isLoadingFalseAfterFailure() async {
        let vm = ISPCardViewModel(service: StubISPService(error: URLError(.timedOut)))
        await vm.load()
        #expect(vm.isLoading == false)
    }

    // MARK: - Refresh triggers new lookup

    @Test("Calling load() again triggers a new lookup")
    func refreshTriggersNewLookup() async {
        let counting = CountingISPService()
        let vm = ISPCardViewModel(service: counting)
        await vm.load()
        #expect(counting.callCount == 1)
        await vm.load()
        #expect(counting.callCount == 2)
    }

    @Test("Refresh updates publicIP when service returns new data")
    func refreshUpdatesData() async {
        let counting = CountingISPService()
        let vm = ISPCardViewModel(service: counting)
        await vm.load()
        let firstIP = vm.ispInfo?.publicIP
        await vm.load()
        let secondIP = vm.ispInfo?.publicIP
        // CountingISPService returns different IPs per call
        #expect(firstIP != secondIP)
    }
}
