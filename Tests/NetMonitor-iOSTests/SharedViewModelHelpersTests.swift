import Testing
import Foundation
@testable import NetMonitor_iOS
@testable import NetMonitorCore

/// Tests for the restoreSelectedNetwork helper function in SharedViewModelHelpers.
@MainActor
struct RestoreSelectedNetworkTests {

    // MARK: - Helpers

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suiteName = "test.restoreNetwork.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    private func cleanup(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeNetwork() -> NetworkUtilities.IPv4Network {
        // 192.168.1.0/24
        NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFFFF00
        )
    }

    private func makeProfile(id: UUID = UUID()) -> NetworkProfile {
        NetworkProfile(
            id: id,
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: makeNetwork(),
            connectionType: .wifi,
            name: "Test Network",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
    }

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

    // MARK: - Restoration succeeds

    @Test("Restores persisted profile ID when profile exists in available networks")
    func restoresPersistedProfile() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let profileID = UUID()
        let profile = makeProfile(id: profileID)
        let manager = makeManager(defaults: defaults, localProfile: profile)

        // Persist the profile ID
        defaults.set(profileID.uuidString, forKey: AppSettings.Keys.selectedNetworkProfileID)

        var selectedID: UUID? = nil
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [profile],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == profileID,
                "Should restore the persisted profile ID when it matches an available network")
    }

    // MARK: - Restoration fails: no persisted ID

    @Test("No-op when no profile ID is persisted")
    func noPersistedID() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let profile = makeProfile()
        let manager = makeManager(defaults: defaults, localProfile: profile)

        var selectedID: UUID? = nil
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [profile],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == nil,
                "selectedNetworkID should remain nil when nothing is persisted")
    }

    // MARK: - Restoration fails: profile not in available networks

    @Test("Clears persisted ID when profile is no longer available")
    func clearsPersistedIDWhenProfileNotAvailable() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let oldProfileID = UUID()
        let differentProfile = makeProfile()  // has a different ID
        let manager = makeManager(defaults: defaults, localProfile: differentProfile)

        // Persist an ID that's NOT in available networks
        defaults.set(oldProfileID.uuidString, forKey: AppSettings.Keys.selectedNetworkProfileID)

        var selectedID: UUID? = nil
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [differentProfile],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == nil, "selectedNetworkID should remain nil when profile is gone")
        // The persisted key should be cleared
        let persistedValue = defaults.string(forKey: AppSettings.Keys.selectedNetworkProfileID)
        #expect(persistedValue == nil,
                "Persisted profile ID should be removed when profile no longer exists")
    }

    // MARK: - Restoration fails: invalid UUID string

    @Test("Clears persisted ID when stored value is not a valid UUID")
    func clearsInvalidUUIDString() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let profile = makeProfile()
        let manager = makeManager(defaults: defaults, localProfile: profile)

        // Persist an invalid UUID string
        defaults.set("not-a-uuid", forKey: AppSettings.Keys.selectedNetworkProfileID)

        var selectedID: UUID? = nil
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [profile],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == nil, "selectedNetworkID should remain nil for invalid UUID")
        let persistedValue = defaults.string(forKey: AppSettings.Keys.selectedNetworkProfileID)
        #expect(persistedValue == nil, "Invalid persisted value should be cleaned up")
    }

    // MARK: - Restoration fails: empty available networks

    @Test("Clears persisted ID when available networks is empty")
    func clearsWhenNoNetworksAvailable() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let profileID = UUID()
        let manager = makeManager(defaults: defaults)

        defaults.set(profileID.uuidString, forKey: AppSettings.Keys.selectedNetworkProfileID)

        var selectedID: UUID? = nil
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == nil)
        let persistedValue = defaults.string(forKey: AppSettings.Keys.selectedNetworkProfileID)
        #expect(persistedValue == nil, "Persisted ID should be removed when no networks are available")
    }

    // MARK: - Existing selectedNetworkID is preserved on failure

    @Test("Pre-existing selectedNetworkID is preserved when restoration fails")
    func existingIDPreservedOnFailure() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let profile = makeProfile()
        let manager = makeManager(defaults: defaults, localProfile: profile)
        let existingID = UUID()

        // No persisted profile
        var selectedID: UUID? = existingID
        restoreSelectedNetwork(
            userDefaults: defaults,
            availableNetworks: [profile],
            networkProfileManager: manager,
            selectedNetworkID: &selectedID
        )

        #expect(selectedID == existingID,
                "Pre-existing selectedNetworkID should be left unchanged when restoration fails")
    }
}
