import Foundation
import Testing
@testable import NetMonitor_iOS

/// Area 6b: Silent failure error surfacing tests for GeoFenceManager persistence.
///
/// GeoFenceManager uses `try?` in two places:
///   - loadGeofences(): `try? JSONDecoder().decode([GeoFenceEntry].self, from: data)`
///   - saveGeofences(): `try? JSONEncoder().encode(geofences)`
///
/// When either fails, the error is silently swallowed:
///   - loadGeofences: geofences stays at [] (the init default) — no error shown
///   - saveGeofences: the encode failure is silently ignored, data is lost
///
/// These tests verify the GeoFenceEntry Codable contract and document the
/// silent failure behavior without modifying production code.
struct GeoFenceManagerErrorTests {

    // MARK: - GeoFenceEntry Codable Contract

    @Test("GeoFenceEntry encode/decode round-trip preserves all fields")
    func entryRoundTrip() throws {
        let entry = GeoFenceEntry(
            name: "Office",
            latitude: 39.7392,
            longitude: -104.9903,
            radius: 500,
            triggerOn: .both,
            isEnabled: true
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GeoFenceEntry.self, from: data)

        #expect(decoded.name == "Office")
        #expect(abs(decoded.latitude - 39.7392) < 0.0001)
        #expect(abs(decoded.longitude - -104.9903) < 0.0001)
        #expect(decoded.radius == 500)
        #expect(decoded.triggerOn == .both)
        #expect(decoded.isEnabled == true)
        #expect(decoded.id == entry.id)
    }

    @Test("GeoFenceEntry array encode/decode round-trip")
    func entryArrayRoundTrip() throws {
        let entries = [
            GeoFenceEntry(name: "Home", latitude: 40.0, longitude: -105.0, radius: 200, triggerOn: .enter),
            GeoFenceEntry(name: "Work", latitude: 39.7, longitude: -104.9, radius: 300, triggerOn: .exit),
        ]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([GeoFenceEntry].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Home")
        #expect(decoded[1].name == "Work")
        #expect(decoded[0].triggerOn == .enter)
        #expect(decoded[1].triggerOn == .exit)
    }

    @Test("Empty geofences array encodes and decodes correctly")
    func emptyArrayRoundTrip() throws {
        let entries: [GeoFenceEntry] = []
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([GeoFenceEntry].self, from: data)
        #expect(decoded.isEmpty)
    }

    // MARK: - Corrupted Data: loadGeofences Falls Back to Empty Array

    @Test("Corrupted JSON data: decode fails, geofences stays empty — error not surfaced")
    func corruptedDataFallsBackToEmpty() {
        // Simulate what loadGeofences() does with corrupted UserDefaults data:
        // guard let decoded = try? JSONDecoder().decode(...) else { return }
        let corruptedData = Data("not valid json at all".utf8)
        let decoded = try? JSONDecoder().decode([GeoFenceEntry].self, from: corruptedData)

        #expect(decoded == nil,
                "Corrupted JSON returns nil — loadGeofences silently falls back to empty array, no error shown to user")
    }

    @Test("Wrong-type JSON data: decode fails, geofences stays empty — error not surfaced")
    func wrongTypeJSONFallsBackToEmpty() {
        // JSON is valid but wrong structure (object instead of array)
        let wrongTypeData = Data("{\"name\": \"not an array\"}".utf8)
        let decoded = try? JSONDecoder().decode([GeoFenceEntry].self, from: wrongTypeData)

        #expect(decoded == nil,
                "Wrong-type JSON returns nil — loadGeofences silently falls back, user sees empty geofence list")
    }

    @Test("Partially corrupted array: entire decode fails (all-or-nothing)")
    func partiallyCorruptedArrayFailsEntirely() {
        // One valid entry + one invalid entry: JSONDecoder decodes all-or-nothing
        let json = """
        [
            {"id":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","name":"Valid","latitude":40.0,"longitude":-105.0,"radius":200,"triggerOn":"enter","isEnabled":true},
            {"corrupted": true}
        ]
        """
        let decoded = try? JSONDecoder().decode([GeoFenceEntry].self, from: Data(json.utf8))

        #expect(decoded == nil,
                "One corrupted entry causes the entire array decode to fail — all geofences lost, error not surfaced")
    }

    // MARK: - GeoFenceTrigger Enum Stability

    @Test("GeoFenceTrigger raw values are stable for persistence")
    func triggerRawValuesStable() {
        #expect(GeoFenceTrigger.enter.rawValue == "enter")
        #expect(GeoFenceTrigger.exit.rawValue == "exit")
        #expect(GeoFenceTrigger.both.rawValue == "both")
    }

    @Test("GeoFenceTrigger allCases has 3 entries")
    func triggerAllCasesCount() {
        #expect(GeoFenceTrigger.allCases.count == 3)
    }

    // MARK: - Radius Clamping

    @Test("GeoFenceEntry radius is clamped to 100...5000")
    func radiusClamped() {
        let tooSmall = GeoFenceEntry(name: "Small", latitude: 0, longitude: 0, radius: 10)
        #expect(tooSmall.radius == 100, "Radius below 100 should be clamped to 100")

        let tooLarge = GeoFenceEntry(name: "Large", latitude: 0, longitude: 0, radius: 10000)
        #expect(tooLarge.radius == 5000, "Radius above 5000 should be clamped to 5000")

        let normal = GeoFenceEntry(name: "Normal", latitude: 0, longitude: 0, radius: 500)
        #expect(normal.radius == 500, "Radius within range should be unchanged")
    }
}
