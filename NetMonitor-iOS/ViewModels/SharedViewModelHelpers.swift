import Foundation
import NetMonitorCore

// MARK: - Network Profile Restoration

/// Restores the previously selected network profile from persisted storage.
///
/// Looks up the saved profile ID in `userDefaults`, validates it against
/// `availableNetworks`, and switches to it via `networkProfileManager`.
/// Clears the persisted value if the profile is no longer available.
///
/// - Parameters:
///   - userDefaults: The `UserDefaults` instance holding the persisted profile ID.
///   - availableNetworks: The current list of available network profiles.
///   - networkProfileManager: The manager used to switch the active profile.
///   - selectedNetworkID: Updated in-place with the restored profile ID, or left
///     unchanged when restoration fails.
@MainActor
func restoreSelectedNetwork(
    userDefaults: UserDefaults,
    availableNetworks: [NetworkProfile],
    networkProfileManager: NetworkProfileManager,
    selectedNetworkID: inout UUID?
) {
    guard let rawValue = userDefaults.string(forKey: AppSettings.Keys.selectedNetworkProfileID),
          let persistedID = UUID(uuidString: rawValue),
          availableNetworks.contains(where: { $0.id == persistedID }),
          networkProfileManager.switchProfile(id: persistedID) else {
        userDefaults.removeObject(forKey: AppSettings.Keys.selectedNetworkProfileID)
        return
    }

    selectedNetworkID = persistedID
}
