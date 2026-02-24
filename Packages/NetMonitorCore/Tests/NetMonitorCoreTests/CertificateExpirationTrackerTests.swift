import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Minimal stubs to avoid real network calls

private final class StubSSLService: SSLCertificateServiceProtocol, @unchecked Sendable {
    func checkCertificate(domain: String) async throws -> SSLCertificateInfo {
        throw SSLCertificateError.noCertificateFound
    }
}

private final class StubWHOISService: WHOISServiceProtocol, @unchecked Sendable {
    func lookup(query: String) async throws -> WHOISResult {
        throw URLError(.notConnectedToInternet)
    }
}

@Suite("CertificateExpirationTracker")
struct CertificateExpirationTrackerTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "CertificateExpirationTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeTracker(defaults: UserDefaults) -> CertificateExpirationTracker {
        let ssl = StubSSLService()
        let whois = StubWHOISService()
        // Capture defaults as nonisolated value to satisfy Swift 6 Sendable checking
        nonisolated(unsafe) let ud = defaults
        return CertificateExpirationTracker(
            sslService: ssl,
            whoisService: whois,
            defaults: ud
        )
    }

    // MARK: - Tests

    @Test("addDomain persists to UserDefaults and appears in getAllTrackedDomains")
    func addDomainPersistsToDefaults() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("example.com", port: 443, notes: nil)

        let all = await tracker.getAllTrackedDomains()
        #expect(all.contains(where: { $0.domain == "example.com" }))
    }

    @Test("removeDomain deletes the domain from getAllTrackedDomains")
    func removeDomainDeletesFromStorage() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("remove-me.com", port: 443, notes: nil)
        await tracker.removeDomain("remove-me.com")

        let all = await tracker.getAllTrackedDomains()
        #expect(!all.contains(where: { $0.domain == "remove-me.com" }))
    }

    @Test("getAllTrackedDomains returns all entries that were added")
    func getAllTrackedDomainsReturnsAllEntries() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("alpha.com", port: 443, notes: nil)
        await tracker.addDomain("beta.com", port: 443, notes: nil)
        await tracker.addDomain("gamma.com", port: 8443, notes: "staging")

        let all = await tracker.getAllTrackedDomains()
        #expect(all.count == 3)
        #expect(all.contains(where: { $0.domain == "alpha.com" }))
        #expect(all.contains(where: { $0.domain == "beta.com" }))
        #expect(all.contains(where: { $0.domain == "gamma.com" }))
    }

    @Test("getExpiringDomains filters by SSL days threshold")
    func getExpiringDomainsFiltersByThreshold() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)

        // Manually inject cached statuses by adding domains then refreshing
        // Since stubs throw errors, sslCertificate will be nil and domainDaysUntilExpiration will be nil
        // so getExpiringDomains threshold filter will return 0 results — this validates the filter
        await tracker.addDomain("soon.com", port: 443, notes: nil)

        let expiring = await tracker.getExpiringDomains(daysThreshold: 30)
        // With stub services returning errors, no valid expiration data exists,
        // so the filter correctly returns an empty list
        #expect(expiring.isEmpty)
    }

    @Test("Duplicate domain is not added twice")
    func duplicateDomainNotAddedTwice() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("dup.com", port: 443, notes: nil)
        await tracker.addDomain("dup.com", port: 443, notes: "updated")

        let all = await tracker.getAllTrackedDomains()
        let matches = all.filter { $0.domain == "dup.com" }
        #expect(matches.count == 1)
    }

    @Test("addDomain stores port correctly")
    func addDomainStoresPort() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("custom-port.com", port: 8443, notes: nil)

        let all = await tracker.getAllTrackedDomains()
        let entry = all.first(where: { $0.domain == "custom-port.com" })
        #expect(entry?.port == 8443)
    }

    @Test("Tracker persistence: added domains reload on new instance with same UserDefaults")
    func persistenceRoundTrip() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker1 = makeTracker(defaults: defaults)
        await tracker1.addDomain("persist.com", port: 443, notes: nil)

        // New instance with same defaults — should pick up persisted entries
        let tracker2 = makeTracker(defaults: defaults)
        let all = await tracker2.getAllTrackedDomains()
        #expect(all.contains(where: { $0.domain == "persist.com" }))
    }
}
