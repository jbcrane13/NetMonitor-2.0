import Foundation
import Testing
@testable import NetMonitorCore

/// Extended tests for NetworkProfileManager.
/// Does NOT duplicate the tests in NetworkProfileManagerTests.swift.
@Suite("NetworkProfileManager Extended")
struct NetworkProfileManagerExtendedTests {

    // MARK: - Helpers (mirrors the pattern in NetworkProfileManagerTests)

    @MainActor
    private func makeManager(
        defaults: UserDefaults,
        localProfile: NetworkProfile? = nil
    ) -> NetworkProfileManager {
        let provider: @Sendable () -> [NetworkProfile] = {
            if let p = localProfile { return [p] }
            return []
        }
        return NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: provider)
    }

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suite = "NetworkProfileManagerExtendedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func clear(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeLocalProfile(subnet: String = "192.168.1.0/24", ip: String = "192.168.1.10") -> NetworkProfile {
        let parts = subnet.split(separator: "/")
        let baseIP = String(parts[0])
        let prefix = Int(parts[1]) ?? 24
        let rawAddress = NetworkUtilities.ipv4ToUInt32(baseIP) ?? 0
        let netmask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        let networkAddress = rawAddress & netmask
        let broadcastAddress = networkAddress | ~netmask
        let interfaceAddress = networkAddress &+ 2
        let network = NetworkUtilities.IPv4Network(
            networkAddress: networkAddress,
            broadcastAddress: broadcastAddress,
            interfaceAddress: interfaceAddress,
            netmask: netmask
        )
        return NetworkProfile(
            id: NetworkProfile.stableID(for: "en0"),
            interfaceName: "en0",
            ipAddress: ip,
            network: network,
            connectionType: .wifi,
            name: "WiFi - \(subnet)",
            gatewayIP: NetworkUtilities.uint32ToIPv4(networkAddress &+ 1),
            subnet: subnet,
            isLocal: true,
            discoveryMethod: .auto
        )
    }

    // MARK: - Tests

    @Test("addProfile: returned profile has correct gateway and subnet fields")
    @MainActor
    func addProfileFieldsAreCorrect() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let profile = manager.addProfile(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Office")

        #expect(profile != nil)
        #expect(profile?.gatewayIP == "10.0.0.1")
        #expect(profile?.subnet == "10.0.0.0/24")
        #expect(profile?.name == "Office")
        #expect(profile?.discoveryMethod == .manual)
        #expect(profile?.isLocal == false)
    }

    @Test("addProfile: profile is added to profiles array")
    @MainActor
    func addProfileAppendsToArray() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let beforeCount = manager.profiles.count
        let added = manager.addProfile(gateway: "172.16.0.1", subnet: "172.16.0.0/24", name: "VPN")

        #expect(added != nil)
        #expect(manager.profiles.count == beforeCount + 1)
        #expect(manager.profiles.contains(where: { $0.id == added!.id }))
    }

    @Test("removeProfile: removes profile by ID and returns true")
    @MainActor
    func removeProfileByID() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let added = manager.addProfile(gateway: "10.5.0.1", subnet: "10.5.0.0/24", name: "Temp")
        guard let added else {
            Issue.record("addProfile returned nil")
            return
        }

        let removed = manager.removeProfile(id: added.id)
        #expect(removed == true)
        #expect(!manager.profiles.contains(where: { $0.id == added.id }))
    }

    @Test("removeProfile: returns false for unknown ID")
    @MainActor
    func removeProfileUnknownIDReturnsFalse() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let result = manager.removeProfile(id: UUID())
        #expect(result == false)
    }

    @Test("Duplicate gateway detection: adding same gateway+subnet updates existing profile")
    @MainActor
    func duplicateGatewayUpdatesExisting() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let first = manager.addProfile(gateway: "10.10.0.1", subnet: "10.10.0.0/24", name: "First")
        let second = manager.addProfile(gateway: "10.10.0.1", subnet: "10.10.0.0/24", name: "Updated")

        #expect(first?.id == second?.id)
        // Only one profile with this gateway should exist
        let matching = manager.profiles.filter { $0.gatewayIP == "10.10.0.1" && $0.subnet == "10.10.0.0/24" }
        #expect(matching.count == 1)
        #expect(matching.first?.name == "Updated")
    }

    @Test("UserDefaults persistence round-trip: profiles survive manager re-creation")
    @MainActor
    func userDefaultsPersistenceRoundTrip() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let localProfile = makeLocalProfile()

        let managerA = makeManager(defaults: defaults, localProfile: localProfile)
        managerA.addProfile(gateway: "192.168.99.1", subnet: "192.168.99.0/24", name: "PersistTest")

        // Re-create with fresh manager instance against same UserDefaults
        let managerB = makeManager(defaults: defaults, localProfile: localProfile)
        let found = managerB.profiles.first(where: { $0.gatewayIP == "192.168.99.1" })
        #expect(found != nil)
        #expect(found?.name == "PersistTest")
    }

    @Test("Empty name falls back to network CIDR label")
    @MainActor
    func emptyNameFallsBackToCIDR() {
        let (defaults, suite) = makeUserDefaults()
        defer { clear(defaults, suiteName: suite) }

        let manager = makeManager(defaults: defaults)
        let profile = manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "   ")

        #expect(profile != nil)
        // Resolved name should contain the CIDR, not be blank
        #expect(profile?.name.isEmpty == false)
        #expect(profile?.name.contains("10.20.0.0/24") == true)
    }
}
