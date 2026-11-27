import Foundation
import NetMonitorCore
import SwiftData

@MainActor
extension NetMonitorApp {
    /// The profile manager and the network identity store (#628 PR B). The store opens first, so a
    /// first launch migrates the networks known before this build, not one this launch just named.
    /// Under UI tests both use throwaway defaults, and `UITEST_IDENTITY=ask` a fixture network.
    /// Made once per launch: setup reruns when the main window is recreated, and a second manager
    /// would lack the identity hook, and a second store location would empty a UI test's store.
    static func makeProfileManager(context: ModelContext, uiTesting: Bool) -> (NetworkProfileManager, NetworkIdentityStore) {
        if let launchProfiles {
            return launchProfiles
        }
        let defaults = uiTesting ? NetworkProfileDefaults.launchDefaults : .standard
        weak var manager: NetworkProfileManager?
        let store = MacNetworkIdentity.openStore(
            at: .make(), profileDefaults: defaults, context: context, profileIDs: { manager?.profiles.map(\.id) ?? [] }
        )
        let profileManager = uiTesting
            ? NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: UITestIdentityFixture.activeProfilesProvider)
            : NetworkProfileManager()
        manager = profileManager
        launchProfiles = (profileManager, store)
        return (profileManager, store)
    }

    private static var launchProfiles: (NetworkProfileManager, NetworkIdentityStore)?
}
