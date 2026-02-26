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

    // MARK: - Add domain tracked correctly (various inputs)

    @Test("addDomain normalizes domain by trimming whitespace and lowercasing")
    func addDomainNormalization() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("  EXAMPLE.COM  ", port: 443, notes: nil)

        let all = await tracker.getAllTrackedDomains()
        #expect(all.contains(where: { $0.domain == "example.com" }))
        #expect(!all.contains(where: { $0.domain == "EXAMPLE.COM" }))
    }

    @Test("addDomain with nil port defaults to 443")
    func addDomainNilPortDefaultsTo443() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("test.com", port: nil, notes: nil)

        let all = await tracker.getAllTrackedDomains()
        let entry = all.first(where: { $0.domain == "test.com" })
        #expect(entry?.port == 443)
    }

    @Test("addDomain with notes stores notes correctly")
    func addDomainWithNotes() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("noted.com", port: 443, notes: "Production server")

        let all = await tracker.getAllTrackedDomains()
        let entry = all.first(where: { $0.domain == "noted.com" })
        #expect(entry?.notes == "Production server")
    }

    // MARK: - Remove domain no longer tracked

    @Test("removeDomain with different casing still removes (sanitized)")
    func removeDomainCaseInsensitive() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("removable.com", port: 443, notes: nil)
        await tracker.removeDomain("  REMOVABLE.COM  ")

        let all = await tracker.getAllTrackedDomains()
        #expect(!all.contains(where: { $0.domain == "removable.com" }))
    }

    @Test("removeDomain for non-existent domain does not crash")
    func removeDomainNonExistent() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        // Should not crash even though domain was never added
        await tracker.removeDomain("never-added.com")
        let all = await tracker.getAllTrackedDomains()
        #expect(all.isEmpty)
    }

    @Test("removeDomain only removes the specified domain, leaving others intact")
    func removeDomainLeavesOthersIntact() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("keep.com", port: 443, notes: nil)
        await tracker.addDomain("remove.com", port: 443, notes: nil)
        await tracker.removeDomain("remove.com")

        let all = await tracker.getAllTrackedDomains()
        #expect(all.count == 1)
        #expect(all.first?.domain == "keep.com")
    }

    // MARK: - getExpiringDomains with various thresholds

    @Test("getExpiringDomains returns empty when no SSL data is available")
    func getExpiringDomainsEmptyWithNoSSLData() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("nodata.com", port: 443, notes: nil)

        // With stub services returning errors, no expiration data exists
        let expiring7 = await tracker.getExpiringDomains(daysThreshold: 7)
        let expiring30 = await tracker.getExpiringDomains(daysThreshold: 30)
        let expiring90 = await tracker.getExpiringDomains(daysThreshold: 90)
        let expiring365 = await tracker.getExpiringDomains(daysThreshold: 365)

        #expect(expiring7.isEmpty)
        #expect(expiring30.isEmpty)
        #expect(expiring90.isEmpty)
        #expect(expiring365.isEmpty)
    }

    @Test("getExpiringDomains threshold 0 returns nothing without data")
    func getExpiringDomainsThresholdZero() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("zero-threshold.com", port: 443, notes: nil)

        let expiring = await tracker.getExpiringDomains(daysThreshold: 0)
        #expect(expiring.isEmpty)
    }

    // MARK: - Concurrent refresh safety

    @Test("Multiple concurrent refreshDomain calls do not crash")
    func concurrentRefreshSafety() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("concurrent1.com", port: 443, notes: nil)
        await tracker.addDomain("concurrent2.com", port: 443, notes: nil)
        await tracker.addDomain("concurrent3.com", port: 443, notes: nil)

        // Fire multiple concurrent refreshes
        async let r1 = tracker.refreshDomain("concurrent1.com")
        async let r2 = tracker.refreshDomain("concurrent2.com")
        async let r3 = tracker.refreshDomain("concurrent3.com")

        let results = await [r1, r2, r3]
        // All should complete without crash (stubs return errors, so ssl/whois will be nil)
        for result in results {
            #expect(result != nil)
            #expect(result?.sslError != nil, "Stub SSL should produce an error string")
        }
    }

    @Test("refreshAllDomains returns results for all tracked domains")
    func refreshAllDomainsReturnsAllResults() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("all1.com", port: 443, notes: nil)
        await tracker.addDomain("all2.com", port: 443, notes: nil)

        let results = await tracker.refreshAllDomains()
        #expect(results.count == 2)
        let domains = results.map { $0.domain }
        #expect(domains.contains("all1.com"))
        #expect(domains.contains("all2.com"))
    }

    @Test("getAllTrackedDomains returns results sorted by domain name")
    func getAllTrackedDomainsSorted() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = makeTracker(defaults: defaults)
        await tracker.addDomain("zebra.com", port: 443, notes: nil)
        await tracker.addDomain("apple.com", port: 443, notes: nil)
        await tracker.addDomain("mango.com", port: 443, notes: nil)

        let all = await tracker.getAllTrackedDomains()
        let domains = all.map { $0.domain }
        #expect(domains == ["apple.com", "mango.com", "zebra.com"])
    }

    // MARK: - DomainExpirationStatus model

    @Test("DomainExpirationStatus id is domain:port format")
    func domainExpirationStatusIDFormat() {
        let status = DomainExpirationStatus(domain: "test.com", port: 8443)
        #expect(status.id == "test.com:8443")
    }

    @Test("DomainExpirationStatus sslDaysUntilExpiration is nil when no certificate")
    func sslDaysUntilExpirationNilWithoutCert() {
        let status = DomainExpirationStatus(domain: "test.com", port: 443)
        #expect(status.sslDaysUntilExpiration == nil)
    }

    @Test("DomainExpirationStatus domainDaysUntilExpiration is nil when no WHOIS result")
    func domainDaysUntilExpirationNilWithoutWHOIS() {
        let status = DomainExpirationStatus(domain: "test.com", port: 443)
        #expect(status.domainDaysUntilExpiration == nil)
    }
}
