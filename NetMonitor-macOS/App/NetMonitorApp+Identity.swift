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
        let profileManager: NetworkProfileManager
        #if DEBUG
        profileManager = uiTesting
            ? NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: UITestIdentityFixture.activeProfilesProvider)
            : NetworkProfileManager(userDefaults: defaults)
        #else
        profileManager = NetworkProfileManager(userDefaults: defaults)
        #endif
        manager = profileManager
        launchProfiles = (profileManager, store)
        return (profileManager, store)
    }

    /// Identification for a UI-test launch: the Debug fixture (`UITestIdentityFixture`), else no hint.
    static func attachUITestIdentity(
        _ store: NetworkIdentityStore, discovery: DeviceDiscoveryCoordinator, profileManager: NetworkProfileManager
    ) {
        #if DEBUG
        UITestIdentityFixture.attach(store, discovery: discovery, profileManager: profileManager)
        #else
        MacNetworkIdentity.attach(
            store: store, discovery: discovery, profileManager: profileManager, readHint: { _ in .absent }
        ) { [weak profileManager] in
            profileManager?.detectLocalNetwork()
        }
        #endif
    }

    private static var launchProfiles: (NetworkProfileManager, NetworkIdentityStore)?
}
