import Foundation
import Testing
@testable import NetMonitorCore

/// Tests that verify NetworkProfileManager and CertificateExpirationTracker handle
/// corrupted, missing, and partial UserDefaults JSON gracefully — without crashing
/// and without silently returning stale or incorrect state.
///
/// Key gap addressed: `guard let decoded = try? JSONDecoder().decode(...)` in both
/// loadProfiles() and the CertificateExpirationTracker init silently swallows
/// decode errors and returns an empty collection. These tests document and verify
/// that behavior (no crash, empty result) and ensure valid data round-trips correctly.
struct NetworkProfileManagerRobustnessTests {

    // MARK: - Helpers

    @MainActor
    private func makeManager(defaults: UserDefaults) -> NetworkProfileManager {
        NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )
    }

    private func makeFreshDefaults() -> (UserDefaults, String) {
        let suite = "NetworkProfileManagerRobustnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    /// Build a minimal NetworkProfile that round-trips through JSON correctly.
    private func makeManualProfile(
        gateway: String = "10.10.0.1",
        subnet: String = "10.10.0.0/24",
        name: String = "Test Network"
    ) -> NetworkProfile {
        let parts = subnet.split(separator: "/")
        let baseIP = String(parts[0])
        let prefix = Int(parts[1]) ?? 24
        let rawAddress = NetworkUtilities.ipv4ToUInt32(baseIP) ?? 0
        let netmask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        let networkAddress = rawAddress & netmask
        let broadcastAddress = networkAddress | ~netmask
        let interfaceAddress = NetworkUtilities.ipv4ToUInt32(gateway) ?? (networkAddress &+ 1)
        let network = NetworkUtilities.IPv4Network(
            networkAddress: networkAddress,
            broadcastAddress: broadcastAddress,
            interfaceAddress: interfaceAddress,
            netmask: netmask
        )
        return NetworkProfile(
            id: UUID(),
            interfaceName: "manual-\(gateway)",
            ipAddress: gateway,
            network: network,
            connectionType: .ethernet,
            name: name,
            gatewayIP: gateway,
            subnet: subnet,
            isLocal: false,
            discoveryMethod: .manual
        )
    }

    // MARK: - Valid JSON round-trip

    @Test("loadProfiles reads valid JSON from UserDefaults and populates profiles array")
    @MainActor
    func loadsValidJSONFromDefaults() throws {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Seed valid JSON directly so we bypass the manager's own write path.
        let profile = makeManualProfile(gateway: "10.0.1.1", subnet: "10.0.1.0/24", name: "Seeded")
        let encoded = try JSONEncoder().encode([profile])
        defaults.set(encoded, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)

        let loaded = manager.profiles.first(where: { $0.gatewayIP == "10.0.1.1" })
        #expect(loaded != nil, "Manager must surface the seeded profile")
        #expect(loaded?.name == "Seeded")
        #expect(loaded?.subnet == "10.0.1.0/24")
    }

    @Test("Encode → UserDefaults → decode round-trip preserves all required profile fields")
    @MainActor
    func encodeDecodeRoundTripPreservesAllFields() throws {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let profile = makeManualProfile(gateway: "172.20.0.1", subnet: "172.20.0.0/16", name: "Round-trip")
        let encoded = try JSONEncoder().encode([profile])
        defaults.set(encoded, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        let loaded = manager.profiles.first(where: { $0.id == profile.id })

        #expect(loaded != nil)
        #expect(loaded?.id == profile.id)
        #expect(loaded?.interfaceName == profile.interfaceName)
        #expect(loaded?.ipAddress == profile.ipAddress)
        #expect(loaded?.connectionType == profile.connectionType)
        #expect(loaded?.name == profile.name)
        #expect(loaded?.gatewayIP == profile.gatewayIP)
        #expect(loaded?.subnet == profile.subnet)
        #expect(loaded?.isLocal == profile.isLocal)
        #expect(loaded?.discoveryMethod == profile.discoveryMethod)
    }

    @Test("Multiple profiles are all loaded when stored data is valid")
    @MainActor
    func multipleProfilesAreLoadedFromValidJSON() throws {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let p1 = makeManualProfile(gateway: "10.1.0.1", subnet: "10.1.0.0/24", name: "Alpha")
        let p2 = makeManualProfile(gateway: "10.2.0.1", subnet: "10.2.0.0/24", name: "Beta")
        let p3 = makeManualProfile(gateway: "10.3.0.1", subnet: "10.3.0.0/24", name: "Gamma")
        let encoded = try JSONEncoder().encode([p1, p2, p3])
        defaults.set(encoded, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        let names = manager.profiles.map(\.name)

        #expect(names.contains("Alpha"))
        #expect(names.contains("Beta"))
        #expect(names.contains("Gamma"))
    }

    // MARK: - Corrupted UserDefaults data

    @Test("Corrupted UserDefaults data (random bytes) does not crash and yields empty profiles")
    @MainActor
    func corruptedDataDoesNotCrashAndYieldsEmptyProfiles() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Write random bytes — not valid JSON.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
        defaults.set(garbage, forKey: "netmonitor.networkProfiles")

        // Must not crash; profiles should be empty (activeProfilesProvider returns []).
        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    @Test("Partial JSON (truncated array) does not crash and yields empty profiles")
    @MainActor
    func truncatedJSONDoesNotCrashAndYieldsEmptyProfiles() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Truncated JSON — decoder will fail.
        let partial = Data("[{\"id\":\"not-a-uuid\",\"interfaceName\":\"en0\"".utf8)
        defaults.set(partial, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    @Test("Completely invalid JSON string does not crash and yields empty profiles")
    @MainActor
    func invalidJSONStringDoesNotCrashAndYieldsEmptyProfiles() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let notJSON = Data("not valid json at all !!!".utf8)
        defaults.set(notJSON, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    @Test("Empty Data stored in UserDefaults does not crash and yields empty profiles")
    @MainActor
    func emptyDataDoesNotCrashAndYieldsEmptyProfiles() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data(), forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    @Test("JSON object (not an array) does not crash and yields empty profiles")
    @MainActor
    func jsonObjectInsteadOfArrayDoesNotCrash() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Valid JSON but a single object, not an array — decoder will fail for [NetworkProfile].
        let json = Data("{\"id\":\"00000000-0000-0000-0000-000000000000\"}".utf8)
        defaults.set(json, forKey: "netmonitor.networkProfiles")

        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    // MARK: - Persistence after write

    @Test("After addProfile, new manager instance loaded from same UserDefaults reads the profile back")
    @MainActor
    func persistenceAfterAddProfile() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let managerA = makeManager(defaults: defaults)
        let added = managerA.addProfile(gateway: "10.50.0.1", subnet: "10.50.0.0/24", name: "Persisted Lab")
        #expect(added != nil)

        // New manager from same defaults — should reload the persisted profile.
        let managerB = makeManager(defaults: defaults)
        let found = managerB.profiles.first(where: { $0.gatewayIP == "10.50.0.1" })
        #expect(found != nil, "New manager must reload the persisted profile")
        #expect(found?.name == "Persisted Lab")
        #expect(found?.subnet == "10.50.0.0/24")
    }

    @Test("After removeProfile, new manager instance does not surface the removed profile")
    @MainActor
    func persistenceAfterRemoveProfile() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let managerA = makeManager(defaults: defaults)
        let added = managerA.addProfile(gateway: "10.60.0.1", subnet: "10.60.0.0/24", name: "Ephemeral")
        guard let added else { return }

        managerA.removeProfile(id: added.id)

        let managerB = makeManager(defaults: defaults)
        #expect(!managerB.profiles.contains(where: { $0.id == added.id }),
                "Removed profile must not reappear after reloading from UserDefaults")
    }

    // MARK: - Missing key in UserDefaults

    @Test("Missing UserDefaults key (never written) yields empty profiles and does not crash")
    @MainActor
    func missingDefaultsKeyYieldsEmptyProfiles() {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // No data written at all — defaults.data(forKey:) returns nil.
        let manager = makeManager(defaults: defaults)
        #expect(manager.profiles.isEmpty)
    }

    // MARK: - Isolation between UserDefaults suites

    @Test("Profiles written to one UserDefaults suite are not visible in a different suite")
    @MainActor
    func profilesDoNotLeakBetweenSuites() {
        let (defaultsA, suiteA) = makeFreshDefaults()
        let (defaultsB, suiteB) = makeFreshDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let managerA = makeManager(defaults: defaultsA)
        managerA.addProfile(gateway: "10.70.0.1", subnet: "10.70.0.0/24", name: "Suite A Profile")

        let managerB = makeManager(defaults: defaultsB)
        #expect(!managerB.profiles.contains(where: { $0.gatewayIP == "10.70.0.1" }),
                "Profiles from suite A must not bleed into suite B")
    }
}

// MARK: - CertificateExpirationTracker UserDefaults Robustness

struct CertificateExpirationTrackerRobustnessTests {

    // MARK: - Stubs (no real network calls)

    private final class StubSSL: SSLCertificateServiceProtocol, @unchecked Sendable {
        func checkCertificate(domain: String) async throws -> SSLCertificateInfo {
            throw SSLCertificateError.noCertificateFound
        }
    }

    private final class StubWHOIS: WHOISServiceProtocol, @unchecked Sendable {
        func lookup(query: String) async throws -> WHOISResult {
            throw URLError(.notConnectedToInternet)
        }
    }

    // MARK: - Helpers

    private func makeFreshDefaults() -> (UserDefaults, String) {
        let suite = "CertificateExpirationTrackerRobustnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeTracker(defaults: UserDefaults) -> CertificateExpirationTracker {
        nonisolated(unsafe) let ud = defaults
        return CertificateExpirationTracker(
            sslService: StubSSL(),
            whoisService: StubWHOIS(),
            defaults: ud
        )
    }

    // MARK: - Corrupted data at init

    @Test("Corrupted UserDefaults bytes do not crash tracker init and yield empty domain list")
    func corruptedDataDoesNotCrashTrackerInit() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            Data([0xFF, 0xFE, 0x00, 0x01, 0xAB, 0xCD]),
            forKey: "CertificateExpirationTracker.entries"
        )

        let tracker = makeTracker(defaults: defaults)
        let all = await tracker.getAllTrackedDomains()
        #expect(all.isEmpty, "Corrupted init data must not surface any domains")
    }

    @Test("Partial JSON in UserDefaults does not crash tracker init and yields empty domain list")
    func partialJSONDoesNotCrashTrackerInit() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            Data("[{\"domain\":\"incomplete\"".utf8),
            forKey: "CertificateExpirationTracker.entries"
        )

        let tracker = makeTracker(defaults: defaults)
        let all = await tracker.getAllTrackedDomains()
        #expect(all.isEmpty)
    }

    @Test("JSON object (not array) in UserDefaults does not crash tracker init")
    func jsonObjectInsteadOfArrayDoesNotCrashTracker() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            Data("{\"domain\":\"single.com\",\"port\":443}".utf8),
            forKey: "CertificateExpirationTracker.entries"
        )

        let tracker = makeTracker(defaults: defaults)
        let all = await tracker.getAllTrackedDomains()
        // A JSON object is not a [TrackedEntry] array — must silently yield empty list.
        #expect(all.isEmpty)
    }

    // MARK: - Persistence round-trip

    @Test("addDomain persists and a new tracker instance loaded from same defaults reads it back")
    func addDomainPersistenceRoundTrip() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker1 = makeTracker(defaults: defaults)
        await tracker1.addDomain("roundtrip.com", port: 443, notes: "prod")

        let tracker2 = makeTracker(defaults: defaults)
        let all = await tracker2.getAllTrackedDomains()

        let entry = all.first(where: { $0.domain == "roundtrip.com" })
        #expect(entry != nil, "Entry must survive persistence round-trip")
        #expect(entry?.port == 443)
        #expect(entry?.notes == "prod")
    }

    @Test("Multiple domains survive persistence round-trip in correct order")
    func multipleDomainsRoundTrip() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker1 = makeTracker(defaults: defaults)
        await tracker1.addDomain("alpha.example.com", port: 443, notes: nil)
        await tracker1.addDomain("beta.example.com", port: 8443, notes: "staging")
        await tracker1.addDomain("gamma.example.com", port: 443, notes: nil)

        let tracker2 = makeTracker(defaults: defaults)
        let all = await tracker2.getAllTrackedDomains()

        #expect(all.count == 3)
        let domains = all.map(\.domain)
        #expect(domains.contains("alpha.example.com"))
        #expect(domains.contains("beta.example.com"))
        #expect(domains.contains("gamma.example.com"))

        let beta = all.first(where: { $0.domain == "beta.example.com" })
        #expect(beta?.port == 8443)
        #expect(beta?.notes == "staging")
    }

    @Test("After removeDomain, new tracker instance loaded from same defaults does not show the domain")
    func removeDomainPersistenceRoundTrip() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker1 = makeTracker(defaults: defaults)
        await tracker1.addDomain("toremove.com", port: 443, notes: nil)
        await tracker1.addDomain("tokeep.com", port: 443, notes: nil)
        await tracker1.removeDomain("toremove.com")

        let tracker2 = makeTracker(defaults: defaults)
        let all = await tracker2.getAllTrackedDomains()

        #expect(!all.contains(where: { $0.domain == "toremove.com" }),
                "Removed domain must not reappear after reload")
        #expect(all.contains(where: { $0.domain == "tokeep.com" }),
                "Retained domain must still be present after reload")
    }

    // MARK: - UserDefaults suite isolation

    @Test("Domains written to one UserDefaults suite are not visible in a different suite")
    func domainsDoNotLeakBetweenSuites() async {
        let (defaultsA, suiteA) = makeFreshDefaults()
        let (defaultsB, suiteB) = makeFreshDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let trackerA = makeTracker(defaults: defaultsA)
        await trackerA.addDomain("only-in-a.com", port: 443, notes: nil)

        let trackerB = makeTracker(defaults: defaultsB)
        let allB = await trackerB.getAllTrackedDomains()

        #expect(!allB.contains(where: { $0.domain == "only-in-a.com" }),
                "Domains from suite A must not bleed into suite B tracker")
    }

    // MARK: - Missing key

    @Test("Missing UserDefaults key at init yields empty domain list and does not crash")
    func missingDefaultsKeyYieldsEmptyDomainList() async {
        let (defaults, suite) = makeFreshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // No data written — defaults.data(forKey:) returns nil.
        let tracker = makeTracker(defaults: defaults)
        let all = await tracker.getAllTrackedDomains()
        #expect(all.isEmpty)
    }
}
