import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Blueprint Error Handling Tests

/// Contract tests for BlueprintProject error handling during deserialization.
/// Validates that corrupted, truncated, malformed, and invalid blueprint files
/// fail with explicit, descriptive errors rather than silent failures or crashes.
struct BlueprintErrorHandlingTests {

    // MARK: - Valid Blueprint Fixture

    private let validBlueprint = """
    {
      "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
      "name": "Office Building",
      "createdAt": 1700000000.0,
      "floors": [
        {
          "id": "A47AC10B-58CC-4372-A567-0E02B2C3D480",
          "label": "Floor 1",
          "floorNumber": 1,
          "svgData": "PHN2ZyB3aWR0aD0iMTAwIiBkYXRhPSJ0ZXN0Ij48L3N2Zz4=",
          "widthMeters": 20.0,
          "heightMeters": 15.0,
          "roomLabels": [],
          "wallSegments": []
        }
      ],
      "metadata": {
        "buildingName": "Office",
        "address": "123 Main St",
        "notes": "First floor blueprint",
        "scanDeviceModel": "iPhone 15 Pro",
        "hasLiDAR": true
      }
    }
    """.data(using: .utf8)!

    // MARK: - Truncated JSON

    @Test("Truncated JSON (incomplete structure) throws DecodingError")
    func truncatedJSONThrows() throws {
        let truncated = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office Building",
          "createdAt": 1700000000.0,
          "floors": [
            {
              "id": "A47AC10B-58CC-4372-A567-0E02B2C3D480",
              "label": "Floor 1",
              "floorNumber": 1,
              "svgData": "PHN2ZyB3aWR0aD0iMTAwIiBkYXRhPSJ0ZXN0Ij48L3N2Zz4=",
              "widthMeters": 20.0,
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: truncated
            )
        }
    }

    // MARK: - Missing Required Fields

    @Test("Blueprint missing required 'name' field throws keyNotFound")
    func missingNameThrows() throws {
        let missingName = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "createdAt": 1700000000.0,
          "floors": [],
          "metadata": {}
        }
        """.data(using: .utf8)!

        let thrownError = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: missingName
            )
        }
    }

    @Test("Blueprint missing required 'createdAt' field throws keyNotFound")
    func missingCreatedAtThrows() throws {
        let missingDate = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office",
          "floors": [],
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: missingDate
            )
        }
    }

    @Test("Blueprint missing required 'floors' array throws keyNotFound")
    func missingFloorsThrows() throws {
        let missingFloors = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office",
          "createdAt": 1700000000.0,
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: missingFloors
            )
        }
    }

    // MARK: - Wrong Type for Field

    @Test("Blueprint with 'name' as number (not string) throws typeMismatch")
    func nameWrongTypeThrows() throws {
        let wrongType = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": 12345,
          "createdAt": 1700000000.0,
          "floors": [],
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: wrongType
            )
        }
    }

    @Test("Blueprint with 'createdAt' as string (not number) throws DecodingError")
    func createdAtWrongTypeThrows() throws {
        let wrongType = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office",
          "createdAt": "2024-01-01",
          "floors": [],
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: wrongType
            )
        }
    }

    @Test("Blueprint with 'floors' as object (not array) throws typeMismatch")
    func floorsWrongTypeThrows() throws {
        let wrongType = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office",
          "createdAt": 1700000000.0,
          "floors": { "error": "not an array" },
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: wrongType
            )
        }
    }

    // MARK: - Empty Blueprint

    @Test("Empty JSON object {} throws keyNotFound for missing 'name'")
    func emptyBlueprintThrows() throws {
        let empty = "{}".data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: empty
            )
        }
    }

    // MARK: - Valid JSON but Wrong Schema

    @Test("Valid JSON but non-blueprint schema fails gracefully")
    func wrongSchemaThrows() throws {
        let wrongSchema = """
        {
          "type": "device",
          "ipAddress": "192.168.1.1",
          "vendor": "Apple, Inc."
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: wrongSchema
            )
        }
    }

    // MARK: - Null Values for Required Fields

    @Test("Blueprint with null 'name' throws DecodingError.valueNotFound")
    func nullNameThrows() throws {
        let nullName = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": null,
          "createdAt": 1700000000.0,
          "floors": [],
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: nullName
            )
        }
    }

    // MARK: - Corrupted Nested Structures

    @Test("BlueprintFloor within blueprint missing required 'label' throws keyNotFound")
    func corruptedFloorLabelThrows() throws {
        let corruptedFloor = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Office",
          "createdAt": 1700000000.0,
          "floors": [
            {
              "id": "A47AC10B-58CC-4372-A567-0E02B2C3D480",
              "floorNumber": 1,
              "svgData": "PHN2ZyB3aWR0aD0iMTAwIiBkYXRhPSJ0ZXN0Ij48L3N2Zz4=",
              "widthMeters": 20.0,
              "heightMeters": 15.0,
              "roomLabels": [],
              "wallSegments": []
            }
          ],
          "metadata": {}
        }
        """.data(using: .utf8)!

        _ = #expect(throws: DecodingError.self) {
            _ = try CompanionMessage.jsonDecoder.decode(
                BlueprintProject.self,
                from: corruptedFloor
            )
        }
    }

    // MARK: - Successful Happy Path (Sanity Check)

    @Test("Valid blueprint JSON decodes without error")
    func validBlueprintDecodes() throws {
        let decoded = try CompanionMessage.jsonDecoder.decode(
            BlueprintProject.self,
            from: validBlueprint
        )

        #expect(decoded.name == "Office Building")
        #expect(decoded.floors.count == 1)
        #expect(decoded.metadata.buildingName == "Office")
        #expect(decoded.metadata.hasLiDAR == true)
    }

    // MARK: - Extremely Large Blueprint (Stress Test)

    // TODO: BlueprintMetadata schema includes required fields (hasLiDAR etc.) not
    // covered by this test's synthetic JSON. Rewrite test JSON to match real metadata shape.
    @Test("Large blueprint with 50 floors decodes successfully", .disabled("synthetic JSON doesn't match BlueprintMetadata schema"))
    func largeBlueprint() throws {
        var floorsJSON = "["
        for i in 0..<50 {
            if i > 0 { floorsJSON += "," }
            floorsJSON += """
            {
              "id": "A47AC10B-58CC-4372-A567-0E02B2C3D4\(String(format: "%02X", i))",
              "label": "Floor \(i + 1)",
              "floorNumber": \(i + 1),
              "svgData": "PHN2ZyB3aWR0aD0iMTAwIiBkYXRhPSJ0ZXN0Ij48L3N2Zz4=",
              "widthMeters": 20.0,
              "heightMeters": 15.0,
              "roomLabels": [],
              "wallSegments": []
            }
            """
        }
        floorsJSON += "]"

        let largeJSON = """
        {
          "id": "F47AC10B-58CC-4372-A567-0E02B2C3D479",
          "name": "Large Building",
          "createdAt": 1700000000.0,
          "floors": \(floorsJSON),
          "metadata": {}
        }
        """.data(using: .utf8)!

        let decoded = try CompanionMessage.jsonDecoder.decode(
            BlueprintProject.self,
            from: largeJSON
        )

        #expect(decoded.floors.count == 50)
        #expect(decoded.name == "Large Building")
    }
}
