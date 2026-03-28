import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - Stub service for ConnectivityCardViewModel tests

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
            organization: nil, asn: nil, city: "Boston",
            region: "MA", country: "US", timezone: nil
        )
    }
}

// MARK: - ConnectivityCardViewModel init state tests

@MainActor
struct ConnectivityCardViewModelInitTests {

    @Test("ispInfo is nil before load")
    func ispInfoNilBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        #expect(vm.ispInfo == nil)
    }

    @Test("loadError is nil before load")
    func loadErrorNilBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        #expect(vm.loadError == nil)
    }

    @Test("dnsServers has em-dash placeholder before load")
    func dnsServersDefaultPlaceholder() {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        #expect(vm.dnsServers == "\u{2014}")
    }

    @Test("hasIPv6 is false before load")
    func hasIPv6FalseBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        #expect(vm.hasIPv6 == false)
    }

    @Test("anchorLatencies is empty before load")
    func anchorLatenciesEmptyBeforeLoad() {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        #expect(vm.anchorLatencies.isEmpty)
    }
}

// MARK: - ConnectivityCardViewModel ISP loading tests

@MainActor
struct ConnectivityCardViewModelISPLoadTests {

    @Test("successful load populates ispInfo with public IP")
    func loadPopulatesPublicIP() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.publicIP == "93.184.216.34")
    }

    @Test("successful load populates ispInfo ISP name")
    func loadPopulatesISPName() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.ispInfo?.isp == "Example ISP")
    }

    @Test("successful load leaves loadError nil")
    func loadLeavesLoadErrorNil() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        #expect(vm.loadError == nil)
    }

    @Test("failed load sets loadError with localized description")
    func failedLoadSetsLoadError() async {
        let err = URLError(.timedOut)
        let vm = ConnectivityCardViewModel(service: StubISPService(error: err))
        await vm.load()
        #expect(vm.loadError == err.localizedDescription)
    }

    @Test("failed load leaves ispInfo nil")
    func failedLoadLeavesISPInfoNil() async {
        let vm = ConnectivityCardViewModel(service: StubISPService(error: URLError(.cannotFindHost)))
        await vm.load()
        #expect(vm.ispInfo == nil)
    }
}

// MARK: - ConnectivityCardViewModel DNS loading tests

@MainActor
struct ConnectivityCardViewModelDNSTests {

    @Test("dnsServers is non-empty after load (reads system DNS or falls back)")
    func dnsServersNonEmptyAfterLoad() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        #expect(!vm.dnsServers.isEmpty)
    }

    @Test("dnsServers is not the initial placeholder after load")
    func dnsServersChangesAfterLoad() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        // After load, dnsServers should be either real DNS addresses or "System DNS"
        // but NOT the initial em-dash placeholder
        #expect(vm.dnsServers != "\u{2014}")
    }

    @Test("dnsServers loads independently of ISP lookup failure")
    func dnsServersLoadsDespiteISPFailure() async {
        let vm = ConnectivityCardViewModel(service: StubISPService(error: URLError(.notConnectedToInternet)))
        await vm.load()
        // DNS loading is synchronous and local; should succeed even when ISP lookup fails
        #expect(!vm.dnsServers.isEmpty)
        #expect(vm.dnsServers != "\u{2014}")
    }
}

// MARK: - ConnectivityCardViewModel IPv6 tests

@MainActor
struct ConnectivityCardViewModelIPv6Tests {

    @Test("hasIPv6 is a Bool after load (system-dependent)")
    func hasIPv6IsBoolAfterLoad() async {
        let vm = ConnectivityCardViewModel(service: StubISPService())
        await vm.load()
        // We can't assert true/false since it depends on the test machine,
        // but we verify it runs without crashing and produces a valid result
        _ = vm.hasIPv6
    }

    @Test("hasIPv6 loads independently of ISP lookup failure")
    func hasIPv6LoadsDespiteISPFailure() async {
        let vm = ConnectivityCardViewModel(service: StubISPService(error: URLError(.notConnectedToInternet)))
        await vm.load()
        // IPv6 detection is local; should not be affected by ISP failure
        _ = vm.hasIPv6
    }
}
