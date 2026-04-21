import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - WiFiBand Version Compatibility Tests

/// Contract tests for WiFiBand enum backward compatibility in survey files.
/// Verifies that old band values ("2.4 GHz", "5 GHz") decode correctly to
/// current enum cases, handles unknown band values gracefully, and survives
/// full round-trip through MeasurementPoint and survey serialization.
struct WiFiBandVersionCompatTests {

    // MARK: - MeasurementPoint JSON Fixtures

    private let measurementWith2_4GHz = """
    {
      "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
      "timestamp": 1700000000.0,
      "floorPlanX": 10.5,
      "floorPlanY": 20.3,
      "rssi": -65,
      "band": "2.4 GHz",
      "ssid": "HomeNetwork",
      "channel": 6
    }
    """.data(using: .utf8)!

    private let measurementWith5GHz = """
    {
      "id": "A47AC10B-58CC-4372-A567-0E02B2C3D480",
      "timestamp": 1700000000.0,
      "floorPlanX": 15.0,
      "floorPlanY": 25.0,
      "rssi": -55,
      "band": "5 GHz",
      "ssid": "HomeNetwork-5G",
      "channel": 36
    }
    """.data(using: .utf8)!

    private let measurementWith6GHz = """
    {
      "id": "B47AC10B-58CC-4372-A567-0E02B2C3D481",
      "timestamp": 1700000000.0,
      "floorPlanX": 12.0,
      "floorPlanY": 22.0,
      "rssi": -50,
      "band": "6 GHz",
      "ssid": "HomeNetwork-6G",
      "channel": 1
    }
    """.data(using: .utf8)!

    private let measurementWithUnknownBand = """
    {
      "id": "C47AC10B-58CC-4372-A567-0E02B2C3D482",
      "timestamp": 1700000000.0,
      "floorPlanX": 8.0,
      "floorPlanY": 18.0,
      "rssi": -70,
      "band": "7 GHz",
      "ssid": "FutureNetwork"
    }
    """.data(using: .utf8)!

    private let measurementWithNullBand = """
    {
      "id": "D47AC10B-58CC-4372-A567-0E02B2C3D483",
      "timestamp": 1700000000.0,
      "floorPlanX": 5.0,
      "floorPlanY": 15.0,
      "rssi": -75,
      "band": null,
      "ssid": "OldDevice"
    }
    """.data(using: .utf8)!

    // MARK: - Old Band String Decoding

    @Test("MeasurementPoint with '2.4 GHz' band string decodes to band2_4GHz")
    func band2_4GHzDecodes() throws {
        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: measurementWith2_4GHz
        )

        #expect(decoded.band == .band2_4GHz)
        #expect(decoded.rssi == -65)
        #expect(decoded.ssid == "HomeNetwork")
    }

    @Test("MeasurementPoint with '5 GHz' band string decodes to band5GHz")
    func band5GHzDecodes() throws {
        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: measurementWith5GHz
        )

        #expect(decoded.band == .band5GHz)
        #expect(decoded.rssi == -55)
        #expect(decoded.ssid == "HomeNetwork-5G")
    }

    @Test("MeasurementPoint with '6 GHz' band string decodes to band6GHz")
    func band6GHzDecodes() throws {
        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: measurementWith6GHz
        )

        #expect(decoded.band == .band6GHz)
        #expect(decoded.rssi == -50)
        #expect(decoded.channel == 1)
    }

    // MARK: - Unknown Band Value Handling

    @Test("MeasurementPoint with unknown band value ('7 GHz') fails decoding")
    func unknownBandValueThrows() throws {
        // When an enum receives an unknown raw value, JSONDecoder throws
        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                MeasurementPoint.self,
                from: measurementWithUnknownBand
            )
        }
    }

    // MARK: - Null Band (Forward Compatibility)

    @Test("MeasurementPoint with null band decodes band as nil")
    func nullBandDecodesAsNil() throws {
        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: measurementWithNullBand
        )

        #expect(decoded.band == nil)
        #expect(decoded.rssi == -75)
    }

    // MARK: - Round-Trip Encoding/Decoding

    @Test("WiFiBand enum round-trip: encode → decode → equality")
    func wifiBandRoundTrip() throws {
        let allBands: [WiFiBand] = [.band2_4GHz, .band5GHz, .band6GHz]

        for band in allBands {
            let point = MeasurementPoint(
                id: UUID(),
                rssi: -65,
                band: band
            )

            let encoded = try CompanionMessage.jsonEncoder.encode(point)
            let decoded = try CompanionMessage.jsonDecoder.decode(
                MeasurementPoint.self,
                from: encoded
            )

            #expect(decoded.band == band, "Band \(band.rawValue) failed round-trip")
        }
    }

    // MARK: - MeasurementPoint Full Round-Trip

    @Test("MeasurementPoint with all fields including band survives full round-trip")
    func measurementPointFullRoundTrip() throws {
        let original = MeasurementPoint(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1700000000),
            floorPlanX: 10.5,
            floorPlanY: 20.3,
            rssi: -65,
            noiseFloor: -90,
            snr: 25,
            ssid: "TestNetwork",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 6,
            frequency: 2437.0,
            band: .band2_4GHz,
            linkSpeed: 72,
            downloadSpeed: 45.5,
            uploadSpeed: 12.3,
            latency: 15.0,
            connectedAPName: "MainAP"
        )

        let encoded = try CompanionMessage.jsonEncoder.encode(original)
        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: encoded
        )

        #expect(decoded.id == original.id)
        #expect(decoded.band == .band2_4GHz)
        #expect(decoded.rssi == -65)
        #expect(decoded.ssid == "TestNetwork")
        #expect(decoded.linkSpeed == 72)
        #expect(decoded.downloadSpeed == 45.5)
        #expect(decoded.channel == 6)
    }

    // MARK: - Missing Band Field (Backward Compat)

    @Test("MeasurementPoint without band field decodes with band as nil")
    func measurementPointMissingBandDecodesAsNil() throws {
        let noBandField = """
        {
          "id": "E47AC10B-58CC-4372-A567-0E02B2C3D484",
          "timestamp": 1700000000.0,
          "floorPlanX": 5.0,
          "floorPlanY": 15.0,
          "rssi": -75,
          "ssid": "VeryOldDevice"
        }
        """.data(using: .utf8)!

        let decoded = try CompanionMessage.jsonDecoder.decode(
            MeasurementPoint.self,
            from: noBandField
        )

        #expect(decoded.band == nil)
        #expect(decoded.ssid == "VeryOldDevice")
    }
}
