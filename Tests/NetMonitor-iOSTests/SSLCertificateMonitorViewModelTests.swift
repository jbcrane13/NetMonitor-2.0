import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("SSLCertificateMonitorViewModel")
@MainActor
struct SSLCertificateMonitorViewModelTests {

    @Test func initialState() {
        let vm = SSLCertificateMonitorViewModel(tracker: MockCertificateExpirationTracker())
        #expect(vm.domain == "")
        #expect(vm.port == "443")
        #expect(vm.isLoading == false)
        #expect(vm.currentResult == nil)
        #expect(vm.trackedDomains.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func canQueryUsesTrimmedDomain() {
        let vm = SSLCertificateMonitorViewModel(tracker: MockCertificateExpirationTracker())
        vm.domain = "   "
        #expect(vm.canQuery == false)

        vm.domain = " example.com "
        #expect(vm.canQuery == true)
    }

    @Test func parsedPortFallsBackTo443ForInvalidInput() {
        let vm = SSLCertificateMonitorViewModel(tracker: MockCertificateExpirationTracker())
        vm.port = "9443"
        #expect(vm.parsedPort == 9443)

        vm.port = "not-a-port"
        #expect(vm.parsedPort == 443)
    }

    @Test func queryDomainSuccessSetsResultAndClearsError() async {
        let tracker = MockCertificateExpirationTracker()
        let status = DomainExpirationStatus(
            domain: "example.com",
            port: 443,
            sslCertificate: nil,
            sslError: nil,
            whoisResult: nil,
            whoisError: nil
        )
        await tracker.setRefreshResult(status, for: "example.com")

        let vm = SSLCertificateMonitorViewModel(tracker: tracker)
        vm.domain = " example.com "
        vm.errorMessage = "old error"

        await vm.queryDomain()

        #expect(vm.errorMessage == nil)
        #expect(vm.currentResult?.domain == "example.com")
        #expect(vm.isLoading == false)
    }

    @Test func queryDomainFailureSetsErrorMessage() async {
        let tracker = MockCertificateExpirationTracker()
        await tracker.setRefreshResult(nil, for: "example.com")

        let vm = SSLCertificateMonitorViewModel(tracker: tracker)
        vm.domain = "example.com"

        await vm.queryDomain()

        #expect(vm.currentResult == nil)
        #expect(vm.errorMessage == "Could not retrieve certificate information")
        #expect(vm.isLoading == false)
    }

    @Test func addAndRemoveWatchListRefreshesTrackedDomains() async {
        let tracker = MockCertificateExpirationTracker()
        let vm = SSLCertificateMonitorViewModel(tracker: tracker)

        vm.currentResult = DomainExpirationStatus(domain: "example.com", port: 443)
        vm.notes = "Prod"

        await vm.addToWatchList()

        #expect(vm.notes == "")
        #expect(vm.showingAddToWatchList == false)
        #expect(vm.trackedDomains.count == 1)
        #expect(vm.trackedDomains.first?.domain == "example.com")
        #expect(vm.trackedDomains.first?.notes == "Prod")

        await vm.removeFromWatchList(domain: "example.com")
        #expect(vm.trackedDomains.isEmpty)
    }

    @Test func clearResultsResetsResultAndError() {
        let vm = SSLCertificateMonitorViewModel(tracker: MockCertificateExpirationTracker())
        vm.currentResult = DomainExpirationStatus(domain: "example.com", port: 443)
        vm.errorMessage = "error"

        vm.clearResults()

        #expect(vm.currentResult == nil)
        #expect(vm.errorMessage == nil)
    }
}

private actor MockCertificateExpirationTracker: CertificateExpirationTrackerProtocol {
    private var trackedByID: [String: DomainExpirationStatus] = [:]
    private var refreshByDomain: [String: DomainExpirationStatus?] = [:]

    func setRefreshResult(_ result: DomainExpirationStatus?, for domain: String) {
        refreshByDomain[domain] = result
    }

    func addDomain(_ domain: String, port: Int?, notes: String?) async {
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = DomainExpirationStatus(
            domain: cleanDomain,
            port: port ?? 443,
            notes: notes,
            sslCertificate: nil,
            sslError: nil,
            whoisResult: nil,
            whoisError: nil
        )
        trackedByID[status.id] = status
    }

    func removeDomain(_ domain: String) async {
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        trackedByID = trackedByID.filter { _, value in
            value.domain != cleanDomain
        }
    }

    func refreshDomain(_ domain: String) async -> DomainExpirationStatus? {
        if let configured = refreshByDomain[domain] {
            return configured
        }

        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trackedByID.values.first(where: { $0.domain == cleanDomain })
    }

    func refreshAllDomains() async -> [DomainExpirationStatus] {
        Array(trackedByID.values).sorted { $0.domain < $1.domain }
    }

    func getAllTrackedDomains() async -> [DomainExpirationStatus] {
        Array(trackedByID.values).sorted { $0.domain < $1.domain }
    }

    func getExpiringDomains(daysThreshold: Int) async -> [DomainExpirationStatus] {
        let all = Array(trackedByID.values)
        return all.filter { status in
            let ssl = status.sslDaysUntilExpiration.map { $0 <= daysThreshold } ?? false
            let domain = status.domainDaysUntilExpiration.map { $0 <= daysThreshold } ?? false
            return ssl || domain
        }
    }
}
