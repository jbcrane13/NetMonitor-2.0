import XCTest
@testable import NetMonitorCore

/// Contract tests for the .netmonsurvey file format save/load mechanics.
/// This prevents agents from straying from the PRD requirements for file serialization.
final class ProjectSaveLoadContractTests: XCTestCase {

    var tempDirectoryURL: URL!
    var testProjectURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        testProjectURL = tempDirectoryURL.appendingPathComponent("test.netmonsurvey")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    func testNetmonsurveyIsDirectoryBundle() throws {
        // According to the PRD, .netmonsurvey is a directory bundle containing:
        // - survey.json
        // - floorplan.png

        // This test requires a mocked implementation of SurveyProject and ProjectSaveLoadManager
        // Since the models might not exist yet, we rely on compiler errors initially.

        let dummyProject = SurveyProject(
            id: UUID(),
            name: "Test Survey",
            createdAt: Date(),
            floorPlan: FloorPlan(id: UUID(), imageData: Data(), widthMeters: 10, heightMeters: 10, pixelWidth: 1000, pixelHeight: 1000, origin: .imported),
            measurementPoints: [],
            surveyMode: .blueprint,
            metadata: SurveyMetadata(buildingName: "HQ", floorNumber: "1", notes: "Test")
        )

        let manager = ProjectSaveLoadManager()
        try manager.save(project: dummyProject, to: testProjectURL)

        // Assert it is a directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: testProjectURL.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists, "The .netmonsurvey bundle must exist")
        XCTAssertTrue(isDirectory.boolValue, "The .netmonsurvey file must be a directory bundle (FileWrapper)")

        // Assert required contents
        let jsonURL = testProjectURL.appendingPathComponent("survey.json")
        let imageURL = testProjectURL.appendingPathComponent("floorplan.png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path), "Bundle must contain survey.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path), "Bundle must contain floorplan.png")
    }
}
