import Foundation
import Testing
@testable import NetMonitorCore

/// `savedProfiles(in:)` / `savedLocalProfile(in:)` read the saved list without writing (#491).
@Suite("NetworkProfileManager saved profiles")
@MainActor
struct NetworkProfileManagerSavedProfilesTests {
    private static func localProfile() -> NetworkProfile {
        NetworkProfile(
            id: NetworkProfile.stableID(for: "en0"),
            interfaceName: "en0",
            ipAddress: "192.0.2.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC000_0200, broadcastAddress: 0xC000_02FF, interfaceAddress: 0xC000_020A, netmask: 0xFFFF_FF00
            ),
            connectionType: .wifi,
            name: "Wi-Fi",
            gatewayIP: "192.0.2.1",
            subnet: "192.0.2.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
    }

    @Test func readsTheLocalProfileAndNetworksOtherManagersAddedWithoutWriting() throws {
        let suite = "NetworkProfileManagerSavedProfilesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = Self.localProfile()
        let first = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [local] })
        // A second manager, like a view model's, adds a network after the first was built.
        let second = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [local] })
        let lab = try #require(second.addProfile(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Lab"))
        let before = defaults.data(forKey: "netmonitor.networkProfiles")

        let saved = NetworkProfileManager.savedProfiles(in: defaults)
        let savedLocal = NetworkProfileManager.savedLocalProfile(in: defaults)

        #expect(saved.contains { $0.id == lab.id })
        #expect(savedLocal?.id == first.localProfile?.id)
        #expect(defaults.data(forKey: "netmonitor.networkProfiles") == before, "Reading must not write")
    }

    @Test func nothingSavedReadsAsNothing() throws {
        let suite = "NetworkProfileManagerSavedProfilesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(NetworkProfileManager.savedProfiles(in: defaults).isEmpty)
        #expect(NetworkProfileManager.savedLocalProfile(in: defaults) == nil)
    }
}
