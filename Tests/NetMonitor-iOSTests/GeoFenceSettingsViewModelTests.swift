import Foundation
import CoreLocation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// NOTE: These tests use GeoFenceManager and GeoFenceEntry, the types present in
// NetMonitor-iOS/Platform/GeoFenceManager.swift.
// API changed from original placeholders: GeoFenceService/NetworkProfileManager/GeoFenceSettingsViewModel
// were never implemented; GeoFenceManager is the actual service type.

@MainActor
struct GeoFenceSettingsViewModelTests {

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
        // API changed: radius clamping is performed in GeoFenceEntry.init, not GeoFenceService.
        let entry = GeoFenceEntry(
            name: "SmallFence",
            latitude: 0,
            longitude: 0,
            radius: 10
        )
        #expect(entry.radius == 100)
    }

    @Test func radiusIsClampedToMaximum() {
        // API changed: radius clamping is performed in GeoFenceEntry.init, not GeoFenceService.
        let entry = GeoFenceEntry(
            name: "HugeFence",
            latitude: 0,
            longitude: 0,
            radius: 99999
        )
        #expect(entry.radius == 5000)
    }

    @Test func isAuthorizedFalseByDefault() {
        // API changed: isAuthorized is a computed property on GeoFenceManager, not GeoFenceSettingsViewModel.
        let manager = GeoFenceManager()
        if manager.authorizationStatus == .notDetermined {
            #expect(manager.isAuthorized == false)
        }
    }

    @Test func geoFenceEntryHasCorrectDefaultTrigger() {
        let entry = GeoFenceEntry(
            name: "DefaultTriggerFence",
            latitude: 37.0,
            longitude: -122.0
        )
        // API changed: was configureGeoFence(trustedType:), now triggerOn stored on entry directly.
        #expect(entry.triggerOn == .enter)
        #expect(entry.isEnabled == true)
    }

    @Test func geoFenceEntryCoordinatesArePreserved() {
        let lat = 37.3317
        let lon = -122.0301
        let entry = GeoFenceEntry(name: "CoordFence", latitude: lat, longitude: lon, radius: 300)
        #expect(entry.latitude == lat)
        #expect(entry.longitude == lon)
        #expect(entry.radius == 300)
    }
}

// MARK: - GeoFenceManager Edge Case Tests

@MainActor
struct GeoFenceManagerEdgeCaseTests {

    @Test func removeGeofencesByOffsetWorks() {
        let manager = GeoFenceManager()
        let before = manager.geofences.count
        let e1 = GeoFenceEntry(name: "Offset1-\(UUID().uuidString)", latitude: 0, longitude: 0)
        let e2 = GeoFenceEntry(name: "Offset2-\(UUID().uuidString)", latitude: 1, longitude: 1)
        manager.addGeofence(e1)
        manager.addGeofence(e2)
        #expect(manager.geofences.count == before + 2)

        // Remove entries added at end via IndexSet
        let lastTwo = IndexSet([manager.geofences.count - 2, manager.geofences.count - 1])
        manager.removeGeofences(at: lastTwo)
        #expect(manager.geofences.count == before)
    }

    @Test func geoFenceTriggerDisplayNamesAreNonEmpty() {
        for trigger in GeoFenceTrigger.allCases {
            #expect(!trigger.displayName.isEmpty)
        }
    }

    @Test func geoFenceEventFieldsArePopulated() {
        // API changed: GeoFenceEvent uses geofenceName/trigger/timestamp, not regionID/profileID/eventType.
        let event = GeoFenceEvent(geofenceName: "Home", trigger: .enter, timestamp: Date())
        #expect(!event.geofenceName.isEmpty)
        #expect(event.trigger == .enter)
    }
}
