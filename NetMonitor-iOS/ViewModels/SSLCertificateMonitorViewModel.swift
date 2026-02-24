import Foundation
import NetMonitorCore

/// ViewModel for the SSL Certificate & Domain Expiration Monitor.
@MainActor
@Observable
final class SSLCertificateMonitorViewModel {

    // MARK: - Input

    var domain: String = ""
    var port: String = "443"

    // MARK: - State

    var isLoading: Bool = false
    var currentResult: DomainExpirationStatus?
    var trackedDomains: [DomainExpirationStatus] = []
    var errorMessage: String?
    var notes: String = ""
    var showingAddToWatchList: Bool = false

    // MARK: - Dependencies

    private let tracker: any CertificateExpirationTrackerProtocol

    init(tracker: any CertificateExpirationTrackerProtocol = CertificateExpirationTracker()) {
        self.tracker = tracker
    }

    // MARK: - Computed

    var canQuery: Bool {
        !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var parsedPort: Int {
        Int(port) ?? 443
    }

    // MARK: - Actions

    func queryDomain() async {
        guard canQuery else { return }
        isLoading = true
        errorMessage = nil

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)

        if let result = await tracker.refreshDomain(trimmedDomain) {
            currentResult = result
        } else {
            currentResult = nil
            errorMessage = "Could not retrieve certificate information"
        }

        isLoading = false
    }

    func addToWatchList() async {
        guard let result = currentResult else { return }
        await tracker.addDomain(result.domain, port: result.port, notes: notes.isEmpty ? nil : notes)
        notes = ""
        showingAddToWatchList = false
        trackedDomains = await tracker.getAllTrackedDomains()
    }

    func removeFromWatchList(domain: String) async {
        await tracker.removeDomain(domain)
        trackedDomains = await tracker.getAllTrackedDomains()
    }

    func clearResults() {
        currentResult = nil
        errorMessage = nil
    }

    func loadTrackedDomains() async {
        trackedDomains = await tracker.getAllTrackedDomains()
    }

    func refreshAll() async {
        isLoading = true
        trackedDomains = await tracker.refreshAllDomains()
        isLoading = false
    }
}
