import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - GeoFenceManager Tests
//
// INTEGRATION GAP: CLLocationManager cannot be mocked in unit tests.
// Region monitoring (startMonitoring/stopMonitoring), authorization requests,
// and delegate callbacks require a device with location services.
// These tests cover the data management layer: CRUD, JSON persistence,
// model validation, and geofence entry logic.

@MainActor
struct GeoFenceManagerTests {

    // Reset persisted state before each test to ensure clean slate
    init() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
    }

    // MARK: - GeoFenceEntry Model Tests

    @Test("GeoFenceEntry radius is clamped to 100...5000")
    func radiusClampedToValidRange() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let tooSmall = GeoFenceEntry(name: "A", latitude: 0, longitude: 0, radius: 10)
        #expect(tooSmall.radius == 100)

        let tooLarge = GeoFenceEntry(name: "B", latitude: 0, longitude: 0, radius: 99999)
        #expect(tooLarge.radius == 5000)

        let justRight = GeoFenceEntry(name: "C", latitude: 0, longitude: 0, radius: 500)
        #expect(justRight.radius == 500)
    }

    @Test("GeoFenceEntry radius clamps lower boundary exactly at 100")
    func radiusLowerBoundary() {
        let atBoundary = GeoFenceEntry(name: "X", latitude: 0, longitude: 0, radius: 100)
        #expect(atBoundary.radius == 100)

        let belowBoundary = GeoFenceEntry(name: "Y", latitude: 0, longitude: 0, radius: 99)
        #expect(belowBoundary.radius == 100)
    }

    @Test("GeoFenceEntry radius clamps upper boundary exactly at 5000")
    func radiusUpperBoundary() {
        let atBoundary = GeoFenceEntry(name: "X", latitude: 0, longitude: 0, radius: 5000)
        #expect(atBoundary.radius == 5000)

        let aboveBoundary = GeoFenceEntry(name: "Y", latitude: 0, longitude: 0, radius: 5001)
        #expect(aboveBoundary.radius == 5000)
    }

    @Test("GeoFenceEntry defaults to enter trigger and enabled")
    func defaultTriggerAndEnabled() {
        let entry = GeoFenceEntry(name: "Office", latitude: 37.7749, longitude: -122.4194)
        #expect(entry.triggerOn == .enter)
        #expect(entry.isEnabled == true)
        #expect(entry.radius == 200)
    }

    @Test("GeoFenceEntry preserves all fields")
    func entryPreservesFields() {
        let id = UUID()
        let entry = GeoFenceEntry(
            id: id,
            name: "Home",
            latitude: 40.7128,
            longitude: -74.0060,
            radius: 300,
            triggerOn: .both,
            isEnabled: false
        )
        #expect(entry.id == id)
        #expect(entry.name == "Home")
        #expect(entry.latitude == 40.7128)
        #expect(entry.longitude == -74.0060)
        #expect(entry.radius == 300)
        #expect(entry.triggerOn == .both)
        #expect(entry.isEnabled == false)
    }

    // MARK: - GeoFenceTrigger

    @Test("GeoFenceTrigger has correct display names")
    func triggerDisplayNames() {
        #expect(GeoFenceTrigger.enter.displayName == "On Enter")
        #expect(GeoFenceTrigger.exit.displayName == "On Exit")
        #expect(GeoFenceTrigger.both.displayName == "On Enter & Exit")
    }

    @Test("GeoFenceTrigger raw values are stable strings")
    func triggerRawValues() {
        #expect(GeoFenceTrigger.enter.rawValue == "enter")
        #expect(GeoFenceTrigger.exit.rawValue == "exit")
        #expect(GeoFenceTrigger.both.rawValue == "both")
    }

    @Test("GeoFenceTrigger has exactly 3 cases")
    func triggerAllCases() {
        #expect(GeoFenceTrigger.allCases.count == 3)
    }

    // MARK: - GeoFenceEntry Codable (JSON persistence)

    @Test("GeoFenceEntry round-trips through JSON encoding/decoding")
    func entryRoundTripsJSON() throws {
        let original = GeoFenceEntry(
            name: "Work",
            latitude: 51.5074,
            longitude: -0.1278,
            radius: 1000,
            triggerOn: .exit,
            isEnabled: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeoFenceEntry.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.latitude == original.latitude)
        #expect(decoded.longitude == original.longitude)
        #expect(decoded.radius == original.radius)
        #expect(decoded.triggerOn == original.triggerOn)
        #expect(decoded.isEnabled == original.isEnabled)
    }

    @Test("GeoFenceEntry array round-trips through JSON for UserDefaults persistence")
    func entryArrayRoundTripsJSON() throws {
        let entries = [
            GeoFenceEntry(name: "Home", latitude: 40.0, longitude: -74.0, triggerOn: .enter),
            GeoFenceEntry(name: "Work", latitude: 41.0, longitude: -73.0, triggerOn: .exit),
            GeoFenceEntry(name: "Gym", latitude: 42.0, longitude: -72.0, triggerOn: .both, isEnabled: false)
        ]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([GeoFenceEntry].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].name == "Home")
        #expect(decoded[1].name == "Work")
        #expect(decoded[2].name == "Gym")
        #expect(decoded[2].isEnabled == false)
    }

    // MARK: - GeoFenceManager CRUD

    @Test("addGeofence appends entry to geofences array")
    func addGeofenceAppendsEntry() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()
        let entry = GeoFenceEntry(name: "Test", latitude: 0, longitude: 0)

        manager.addGeofence(entry)

        #expect(manager.geofences.count == 1)
        #expect(manager.geofences.first?.name == "Test")
    }

    @Test("addGeofence multiple entries accumulate")
    func addMultipleGeofences() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()

        manager.addGeofence(GeoFenceEntry(name: "A", latitude: 0, longitude: 0))
        manager.addGeofence(GeoFenceEntry(name: "B", latitude: 1, longitude: 1))
        manager.addGeofence(GeoFenceEntry(name: "C", latitude: 2, longitude: 2))

        #expect(manager.geofences.count == 3)
    }

    @Test("removeGeofence removes the correct entry by ID")
    func removeGeofenceByEntry() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()
        let entry1 = GeoFenceEntry(name: "Keep", latitude: 0, longitude: 0)
        let entry2 = GeoFenceEntry(name: "Remove", latitude: 1, longitude: 1)

        manager.addGeofence(entry1)
        manager.addGeofence(entry2)
        manager.removeGeofence(entry2)

        #expect(manager.geofences.count == 1)
        #expect(manager.geofences.first?.name == "Keep")
    }

    @Test("removeGeofences at IndexSet removes correct entries")
    func removeGeofencesAtOffsets() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()
        manager.addGeofence(GeoFenceEntry(name: "A", latitude: 0, longitude: 0))
        manager.addGeofence(GeoFenceEntry(name: "B", latitude: 1, longitude: 1))
        manager.addGeofence(GeoFenceEntry(name: "C", latitude: 2, longitude: 2))

        manager.removeGeofences(at: IndexSet(integer: 1))

        #expect(manager.geofences.count == 2)
        #expect(manager.geofences[0].name == "A")
        #expect(manager.geofences[1].name == "C")
    }

    @Test("toggleEnabled flips the isEnabled flag")
    func toggleEnabledFlipsFlag() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()
        let entry = GeoFenceEntry(name: "Toggle", latitude: 0, longitude: 0, isEnabled: true)
        manager.addGeofence(entry)

        #expect(manager.geofences[0].isEnabled == true)

        manager.toggleEnabled(entry)
        #expect(manager.geofences[0].isEnabled == false)

        // Toggle again to re-enable
        manager.toggleEnabled(manager.geofences[0])
        #expect(manager.geofences[0].isEnabled == true)
    }

    @Test("toggleEnabled on nonexistent entry does nothing")
    func toggleEnabledNoopForUnknownEntry() {
        #if DEBUG
        GeoFenceManager.shared.resetForTesting()
        #endif
        let manager = GeoFenceManager()
        let existing = GeoFenceEntry(name: "Exists", latitude: 0, longitude: 0)
        manager.addGeofence(existing)

        let unknown = GeoFenceEntry(name: "Ghost", latitude: 99, longitude: 99)
        manager.toggleEnabled(unknown)

        #expect(manager.geofences.count == 1)
        #expect(manager.geofences[0].isEnabled == true)
    }

    // MARK: - GeoFenceEvent

    @Test("GeoFenceEvent stores all properties")
    func geoFenceEventProperties() {
        let now = Date()
        let event = GeoFenceEvent(geofenceName: "Office", trigger: .enter, timestamp: now)
        #expect(event.geofenceName == "Office")
        #expect(event.trigger == .enter)
        #expect(event.timestamp == now)
    }

}
