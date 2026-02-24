import Foundation
import CoreLocation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// NOTE: GeoFenceService, GeoFenceSettingsViewModel, GeoFenceManager, and GeoFenceEntry
// types are not yet implemented. These tests are placeholders for when the GeoFence
// feature is fully built. All tests are disabled until the types exist.
//
// To re-enable: remove the #if false / #endif guards.

#if false

@Suite("GeoFenceSettingsViewModel")
@MainActor
struct GeoFenceSettingsViewModelTests {

    @Test func refreshLoadsProfilesFromProfileManager() {
        let context = isolatedDefaults()
        defer { cleanup(context) }

        let profileManager = NetworkProfileManager(
            userDefaults: context.defaults,
            activeProfilesProvider: { [] }
        )
        let geoFenceService = GeoFenceService(userDefaults: context.defaults)

        let profile = profileManager.addProfile(
            gateway: "192.168.1.1",
            subnet: "192.168.1.0/24",
            name: "Home"
        )

        let vm = GeoFenceSettingsViewModel(
            geoFenceService: geoFenceService,
            profileManager: profileManager
        )
        vm.refresh()

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.name == "Home")
        #expect(vm.profileName(for: profile?.id ?? UUID()) == "Home")
    }

    @Test func configureAndDisableGeoFenceUpdatesSettings() {
        let context = isolatedDefaults()
        defer { cleanup(context) }

        let profileManager = NetworkProfileManager(
            userDefaults: context.defaults,
            activeProfilesProvider: { [] }
        )
        let geoFenceService = GeoFenceService(userDefaults: context.defaults)

        guard let profile = profileManager.addProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Office"
        ) else {
            Issue.record("Expected profile to be created")
            return
        }

        let vm = GeoFenceSettingsViewModel(
            geoFenceService: geoFenceService,
            profileManager: profileManager
        )

        vm.configureGeoFence(
            for: profile,
            center: CLLocationCoordinate2D(latitude: 37.3317, longitude: -122.0301),
            radius: 150,
            trustedType: .trusted
        )

        let enabledSettings = vm.settings(for: profile.id)
        #expect(enabledSettings?.isEnabled == true)
        #expect(enabledSettings?.trustedType == .trusted)
        #expect(enabledSettings?.region != nil)
        #expect(enabledSettings?.region?.radius == 150)

        vm.disableGeoFence(for: profile)

        let disabledSettings = vm.settings(for: profile.id)
        #expect(disabledSettings?.isEnabled == false)
        #expect(disabledSettings?.region == nil)
    }

    @Test func clearEventHistoryResetsRecentEvents() {
        let context = isolatedDefaults()
        defer { cleanup(context) }

        let profileManager = NetworkProfileManager(
            userDefaults: context.defaults,
            activeProfilesProvider: { [] }
        )
        let geoFenceService = GeoFenceService(userDefaults: context.defaults)

        let vm = GeoFenceSettingsViewModel(
            geoFenceService: geoFenceService,
            profileManager: profileManager
        )

        vm.recentEvents = [
            GeoFenceEvent(
                regionID: UUID(),
                profileID: UUID(),
                eventType: .entry,
                latitude: 37.0,
                longitude: -122.0
            )
        ]

        vm.clearEventHistory()

        #expect(vm.recentEvents.isEmpty)
    }

    @Test func isAuthorizedReflectsAuthorizationStatus() {
        let context = isolatedDefaults()
        defer { cleanup(context) }

        let vm = GeoFenceSettingsViewModel(
            geoFenceService: GeoFenceService(userDefaults: context.defaults),
            profileManager: NetworkProfileManager(userDefaults: context.defaults, activeProfilesProvider: { [] })
        )

        vm.authorizationStatus = .notDetermined
        #expect(vm.isAuthorized == false)

        vm.authorizationStatus = .authorizedWhenInUse
        #expect(vm.isAuthorized == true)

        vm.authorizationStatus = .authorizedAlways
        #expect(vm.isAuthorized == true)
    }

    private func isolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "GeoFenceSettingsViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func cleanup(_ context: (defaults: UserDefaults, suiteName: String)) {
        context.defaults.removePersistentDomain(forName: context.suiteName)
    }
}

// MARK: - GeoFenceManager Edge Case Tests

@Suite("GeoFenceManager Edge Cases")
@MainActor
struct GeoFenceManagerEdgeCaseTests {

    @Test func addGeofenceAppearsInList() {
        let manager = GeoFenceManager()
        let initialCount = manager.geofences.count
        let entry = GeoFenceEntry(
            name: "TestFence-\(UUID().uuidString)",
            latitude: 37.3317,
            longitude: -122.0301,
            radius: 200,
            triggerOn: .enter
        )
        manager.addGeofence(entry)
        #expect(manager.geofences.count == initialCount + 1)
        #expect(manager.geofences.contains(where: { $0.id == entry.id }))
        manager.removeGeofence(entry)
    }

    @Test func removeGeofenceRemovesFromList() {
        let manager = GeoFenceManager()
        let entry = GeoFenceEntry(
            name: "RemoveFence-\(UUID().uuidString)",
            latitude: 37.0,
            longitude: -122.0,
            radius: 150,
            triggerOn: .exit
        )
        manager.addGeofence(entry)
        #expect(manager.geofences.contains(where: { $0.id == entry.id }))
        manager.removeGeofence(entry)
        #expect(!manager.geofences.contains(where: { $0.id == entry.id }))
    }

    @Test func toggleEnabledFlipsEnabledState() {
        let manager = GeoFenceManager()
        let entry = GeoFenceEntry(
            name: "ToggleFence-\(UUID().uuidString)",
            latitude: 37.0,
            longitude: -122.0,
            radius: 200,
            isEnabled: true
        )
        manager.addGeofence(entry)
        guard let index = manager.geofences.firstIndex(where: { $0.id == entry.id }) else {
            Issue.record("Entry not found after add")
            return
        }
        let waEnabled = manager.geofences[index].isEnabled
        manager.toggleEnabled(manager.geofences[index])
        #expect(manager.geofences[index].isEnabled == !waEnabled)
        manager.removeGeofence(manager.geofences[index])
    }

    @Test func radiusIsClampedToMinimum() {
        let entry = GeoFenceEntry(
            name: "SmallFence",
            latitude: 0,
            longitude: 0,
            radius: 10
        )
        #expect(entry.radius == 100)
    }

    @Test func radiusIsClampedToMaximum() {
        let entry = GeoFenceEntry(
            name: "HugeFence",
            latitude: 0,
            longitude: 0,
            radius: 99999
        )
        #expect(entry.radius == 5000)
    }

    @Test func isAuthorizedFalseByDefault() {
        let manager = GeoFenceManager()
        if manager.authorizationStatus == .notDetermined {
            #expect(manager.isAuthorized == false)
        }
    }
}

#endif
