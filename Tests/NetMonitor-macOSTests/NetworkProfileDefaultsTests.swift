import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// #346: UI-test launches keep their network list out of the user's defaults and start empty.
@Suite("NetworkProfileDefaults")
@MainActor
struct NetworkProfileDefaultsTests {
    /// `NetworkProfileManager`'s storage key. The test host's standard defaults are the app's
    /// real domain, so this suite only ever reads it there.
    private let profilesKey = "netmonitor.networkProfiles"

    @Test func uiTestLaunchUsesAnEmptiedSuiteAndLeavesStandardAlone() throws {
        let suiteName = "netmonitor.test.profiles.\(UUID().uuidString)"
        let stale = try #require(UserDefaults(suiteName: suiteName))
        defer { stale.removePersistentDomain(forName: suiteName) }
        stale.set(Data("stale".utf8), forKey: profilesKey)
        let standardBefore = UserDefaults.standard.data(forKey: profilesKey)

        let defaults = NetworkProfileDefaults.make(arguments: ["NetMonitor", "--uitesting"], uiTestSuite: suiteName)

        // Stop here otherwise: the rest would write a network into the app's real domain.
        try #require(defaults !== UserDefaults.standard, "UI-test launches must not save networks to the user's defaults")
        #expect(defaults.data(forKey: profilesKey) == nil, "A UI-test launch should start without the last run's networks")

        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [] })
        let added = manager.addProfile(gateway: "10.34.6.1", subnet: "10.34.6.0/24", name: "UI Test Network")
        #expect(added != nil)
        #expect(defaults.data(forKey: profilesKey) != nil, "The added network should be saved in the UI-test suite")
        #expect(UserDefaults.standard.data(forKey: profilesKey) == standardBefore,
                "Adding a network under UI testing must leave the standard domain untouched")

        // The next launch empties the suite again.
        let relaunch = NetworkProfileDefaults.make(arguments: ["NetMonitor", "--uitesting"], uiTestSuite: suiteName)
        let relaunched = NetworkProfileManager(userDefaults: relaunch, activeProfilesProvider: { [] })
        #expect(relaunched.profiles.isEmpty, "A relaunch should not bring back the network the last launch added")
    }

    @Test func normalLaunchUsesStandardDefaults() {
        #expect(NetworkProfileDefaults.make(arguments: ["NetMonitor"]) === UserDefaults.standard)
    }
}
