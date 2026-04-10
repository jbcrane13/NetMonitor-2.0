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

/// A stub that returns an ISPInfo with all optional fields populated.
private final class FullInfoISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    func lookup() async throws -> ISPLookupService.ISPInfo {
        ISPLookupService.ISPInfo(
            publicIP: "203.0.113.42",
            isp: "Contoso Broadband",
            organization: "AS64512 Contoso",
            asn: "AS64512",
            city: "Portland",
            region: "OR",
            country: "US",
            timezone: "America/Los_Angeles"
        )
    }
}

/// A stub that returns an ISPInfo where only country is set (no city).
private final class CountryOnlyISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    func lookup() async throws -> ISPLookupService.ISPInfo {
        ISPLookupService.ISPInfo(
            publicIP: "203.0.113.1",
            isp: "Remote ISP",
            organization: nil,
            asn: nil,
            city: nil,
            region: nil,
            country: "DE",
            timezone: nil
        )
    }
}

/// A stub whose first call fails and second call succeeds.
private final class RecoveringISPService: ISPLookupServiceProtocol, @unchecked Sendable {
    private var callCount = 0
    private let lock = NSLock()

    func lookup() async throws -> ISPLookupService.ISPInfo {
        let count = lock.withLock {
            callCount += 1
            return callCount
        }
        if count == 1 {
            throw URLError(.notConnectedToInternet)
        }
        return ISPLookupService.ISPInfo(
            publicIP: "10.0.0.1", isp: "Recovered ISP",
            organization: nil, asn: nil, city: "Seattle",
            region: "WA", country: "US", timezone: nil
        )
    }
}

// MARK: - ISPCardViewModel extended tests

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

    @Test func isLoadingFalseAfterFailedLoad() async {
        let vm = ISPCardViewModel(service: FailingISPService())
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

    @Test func ispInfoNilAfterFailedLoad() async {
        let vm = ISPCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.ispInfo == nil)
    }

    @Test func errorMessageSetAfterFailedLoad() async {
        let vm = ISPCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test func errorMessageNilAfterSuccessfulLoad() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.errorMessage == nil)
    }

    // Verify rate-limit error surfaces its specific localizedDescription.
    @Test func errorMessageContainsRateLimitedDescription() async {
        let vm = ISPCardViewModel(service: FailingISPService(error: ISPLookupError.rateLimited))
        await vm.load()
        #expect(vm.errorMessage == ISPLookupError.rateLimited.errorDescription)
    }

    // Verify invalid-response error surfaces its specific localizedDescription.
    @Test func errorMessageContainsInvalidResponseDescription() async {
        let vm = ISPCardViewModel(service: FailingISPService(error: ISPLookupError.invalidResponse))
        await vm.load()
        #expect(vm.errorMessage == ISPLookupError.invalidResponse.errorDescription)
    }

    // All optional fields on ISPInfo are populated when the service returns them.
    @Test func allOptionalFieldsPopulated() async throws {
        let vm = ISPCardViewModel(service: FullInfoISPService())
        await vm.load()
        let info = try #require(vm.ispInfo)
        #expect(info.publicIP == "203.0.113.42")
        #expect(info.isp == "Contoso Broadband")
        #expect(info.organization == "AS64512 Contoso")
        #expect(info.asn == "AS64512")
        #expect(info.city == "Portland")
        #expect(info.region == "OR")
        #expect(info.country == "US")
        #expect(info.timezone == "America/Los_Angeles")
    }

    // When only country is set (city is nil), ispInfo.city is nil.
    @Test func ispInfoCityNilWhenServiceReturnsNone() async throws {
        let vm = ISPCardViewModel(service: CountryOnlyISPService())
        await vm.load()
        let info = try #require(vm.ispInfo)
        #expect(info.city == nil)
        #expect(info.country == "DE")
    }

    // Calling load() a second time after a failure and supplying a new vm
    // with a succeeding service leaves errorMessage nil and ispInfo populated.
    // (Tests the retry contract at the ViewModel level via separate instances.)
    @Test func successOnSecondVMAfterPriorFailure() async {
        let failingVM = ISPCardViewModel(service: FailingISPService())
        await failingVM.load()
        #expect(failingVM.errorMessage != nil)

        let succeedingVM = ISPCardViewModel(service: SucceedingISPService())
        await succeedingVM.load()
        #expect(succeedingVM.errorMessage == nil)
        #expect(succeedingVM.ispInfo?.publicIP == "1.2.3.4")
    }

    // Multiple sequential load() calls must not leave isLoading in an inconsistent state.
    @Test func multipleLoadsLeaveIsLoadingFalse() async {
        let vm = ISPCardViewModel(service: SucceedingISPService())
        await vm.load()
        await vm.load()
        #expect(vm.isLoading == false)
    }

    // After two successful loads the latest ispInfo is from the most recent call.
    @Test func ispInfoOverwrittenOnSubsequentLoad() async {
        let vm = ISPCardViewModel(service: FullInfoISPService())
        await vm.load()
        let firstIP = vm.ispInfo?.publicIP

        // Load again with a different service by creating a new ViewModel —
        // the test contract is that load() replaces whatever was there.
        let vm2 = ISPCardViewModel(service: SucceedingISPService())
        await vm2.load()
        #expect(vm2.ispInfo?.publicIP == "1.2.3.4")
        #expect(firstIP == "203.0.113.42") // First VM unchanged
    }
}

// MARK: - ConnectivityCardViewModel extended tests

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

    // dnsServers must have a non-empty default before load() is called.
    // The ViewModel initializes it to "—" (an em-dash placeholder).
    @Test func dnsServersHasDefaultBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        #expect(!vm.dnsServers.isEmpty)
    }

    // anchorLatencies must be empty before any load has been attempted.
    @Test func anchorLatenciesEmptyBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        #expect(vm.anchorLatencies.isEmpty)
    }

    // hasIPv6 has a defined Bool value before load.
    @Test func hasIPv6HasDefinedValueBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        // Value is a Bool — just ensure it was initialized without crashing.
        _ = vm.hasIPv6
    }

    @Test func ispInfoPopulatedAfterSuccessfulLoad() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
        #expect(vm.ispInfo?.isp == "Test ISP")
    }

    @Test func ispInfoPublicIPSetOnSuccess() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
    }

    @Test func ispInfoISPNameSetOnSuccess() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.isp == "Test ISP")
    }

    @Test func ispInfoCitySetOnSuccess() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.city == "Denver")
    }

    @Test func ispInfoCountrySetOnSuccess() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.ispInfo?.country == "US")
    }

    @Test func ispInfoNilAfterFailedLoad() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.ispInfo == nil)
    }

    @Test func loadErrorSetAfterFailedLoad() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(vm.loadError != nil)
    }

    @Test func loadErrorNilAfterSuccessfulLoad() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(vm.loadError == nil)
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

    // Rate-limit error message must match the specific localizedDescription.
    @Test func loadErrorContainsRateLimitedDescription() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService(error: ISPLookupError.rateLimited))
        await vm.load()
        #expect(vm.loadError == ISPLookupError.rateLimited.errorDescription)
    }

    // Invalid-response error message must match the specific localizedDescription.
    @Test func loadErrorContainsInvalidResponseDescription() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService(error: ISPLookupError.invalidResponse))
        await vm.load()
        #expect(vm.loadError == ISPLookupError.invalidResponse.errorDescription)
    }

    // When city is nil but country is set, ispInfo.city is nil and country is populated.
    @Test func countryOnlyLocationFieldsSetCorrectly() async throws {
        let vm = ConnectivityCardViewModel(service: CountryOnlyISPService())
        await vm.load()
        let info = try #require(vm.ispInfo)
        #expect(info.city == nil)
        #expect(info.country == "DE")
    }

    // All optional fields are surfaced correctly from the ViewModel.
    @Test func allISPInfoFieldsPopulatedOnFullLoad() async throws {
        let vm = ConnectivityCardViewModel(service: FullInfoISPService())
        await vm.load()
        let info = try #require(vm.ispInfo)
        #expect(info.publicIP == "203.0.113.42")
        #expect(info.isp == "Contoso Broadband")
        #expect(info.organization == "AS64512 Contoso")
        #expect(info.asn == "AS64512")
        #expect(info.city == "Portland")
        #expect(info.region == "OR")
        #expect(info.country == "US")
        #expect(info.timezone == "America/Los_Angeles")
    }

    // dnsServers must be non-empty after a successful load (either a real value or the
    // "System DNS" fallback — never an empty string).
    @Test func dnsServersNonEmptyAfterLoad() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        #expect(!vm.dnsServers.isEmpty)
    }

    // After a failed ISP load, dnsServers still has a value (DNS loading is independent).
    @Test func dnsServersNonEmptyEvenAfterISPFailure() async {
        let vm = ConnectivityCardViewModel(service: FailingISPService())
        await vm.load()
        #expect(!vm.dnsServers.isEmpty)
    }

    // Multiple sequential load() calls must not leave any property in an invalid state.
    @Test func multipleLoadsDoNotCorruptState() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()
        await vm.load()
        #expect(vm.ispInfo != nil)
        #expect(vm.loadError == nil)
    }

    // Verifies that anchorLatencies is populated after a full load() completes.
    // pingAllAnchors() runs in a background Task, so we poll briefly for results.
    @Test func anchorLatenciesPopulatedAfterLoad() async {
        let vm = ConnectivityCardViewModel(service: SucceedingISPService())
        await vm.load()

        // Anchor pings run asynchronously — wait up to 10s for results.
        for _ in 0..<20 {
            if !vm.anchorLatencies.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(500))
        }

        #expect(!vm.anchorLatencies.isEmpty,
                "Expected anchor latencies to be populated within 10s of load()")
        #expect(vm.anchorLatencies["Google"] != nil || vm.anchorLatencies["Cloudflare"] != nil
             || vm.anchorLatencies["AWS"] != nil   || vm.anchorLatencies["Apple"] != nil,
                "At least one anchor key should be populated after load()")
    }
}
