import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("HeatmapDashboardViewModel")
@MainActor
struct HeatmapDashboardViewModelTests {

    // MARK: - Helpers

    /// Creates a temporary directory to use as a mock Documents directory.
    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeatmapDashboardTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Creates a mock .netmonsurvey bundle with valid survey.json in the given directory.
    private func createMockSurveyBundle(
        in directory: URL,
        name: String,
        pointCount: Int = 0,
        createdAt: Date = Date()
    ) throws -> URL {
        let bundleName = "\(name).netmonsurvey"
        let bundleURL = directory.appendingPathComponent(bundleName)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let project = SurveyProject(
            name: name,
            createdAt: createdAt,
            floorPlan: FloorPlan(
                imageData: Data(),
                widthMeters: 10.0,
                heightMeters: 8.0,
                pixelWidth: 800,
                pixelHeight: 600,
                origin: .drawn
            ),
            measurementPoints: (0..<pointCount).map { index in
                MeasurementPoint(
                    floorPlanX: Double(index) / 10.0,
                    floorPlanY: Double(index) / 10.0,
                    rssi: -50 - index
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(project)
        try jsonData.write(to: bundleURL.appendingPathComponent("survey.json"))

        return bundleURL
    }

    /// Creates a ViewModel that uses a custom mock FileManager pointing to a temp directory.
    /// Since FileManager is hard to mock for `urls(for:in:)`, we use a subclass.
    private func makeViewModel(documentsDir: URL) -> HeatmapDashboardViewModel {
        let mockFM = MockDocumentsFileManager(documentsDir: documentsDir)
        return HeatmapDashboardViewModel(fileManager: mockFM)
    }

    // MARK: - Tests

    @Test func initialStateIsEmpty() {
        let vm = HeatmapDashboardViewModel()
        #expect(vm.projects.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.showNewProjectSheet == false)
    }

    @Test func loadProjectsFindsNoProjectsInEmptyDirectory() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(vm.projects.isEmpty)
        #expect(vm.isLoading == false)
    }

    @Test func loadProjectsFindsSingleProject() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createMockSurveyBundle(in: tempDir, name: "Office Survey", pointCount: 5)

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(vm.projects.count == 1)
        #expect(vm.projects[0].name == "Office Survey")
        #expect(vm.projects[0].pointCount == 5)
    }

    @Test func loadProjectsFindsMultipleProjectsSortedByDateDescending() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let olderDate = Date(timeIntervalSince1970: 1_000_000)
        let newerDate = Date(timeIntervalSince1970: 2_000_000)

        try createMockSurveyBundle(in: tempDir, name: "Older Project", createdAt: olderDate)
        try createMockSurveyBundle(in: tempDir, name: "Newer Project", createdAt: newerDate)

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(vm.projects.count == 2)
        #expect(vm.projects[0].name == "Newer Project")
        #expect(vm.projects[1].name == "Older Project")
    }

    @Test func loadProjectsSkipsInvalidBundles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a valid bundle
        try createMockSurveyBundle(in: tempDir, name: "Valid Project")

        // Create an invalid bundle (directory with wrong extension)
        let invalidDir = tempDir.appendingPathComponent("NotASurvey.txt")
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)

        // Create a bundle with corrupt JSON
        let corruptBundle = tempDir.appendingPathComponent("Corrupt.netmonsurvey")
        try FileManager.default.createDirectory(at: corruptBundle, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: corruptBundle.appendingPathComponent("survey.json"))

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(vm.projects.count == 1)
        #expect(vm.projects[0].name == "Valid Project")
    }

    @Test func deleteProjectRemovesFromListAndFileSystem() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = try createMockSurveyBundle(in: tempDir, name: "Delete Me", pointCount: 3)

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(vm.projects.count == 1)
        #expect(FileManager.default.fileExists(atPath: bundleURL.path))

        vm.deleteProject(vm.projects[0])

        #expect(vm.projects.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: bundleURL.path))
    }

    @Test func projectSummaryFormattedDateIsNotEmpty() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createMockSurveyBundle(in: tempDir, name: "Date Test")

        let vm = makeViewModel(documentsDir: tempDir)
        vm.loadProjects()

        #expect(!vm.projects[0].formattedDate.isEmpty)
    }

    @Test func projectSummaryPointCountLabel() {
        let onePoint = HeatmapProjectSummary(
            id: UUID(),
            name: "Test",
            createdAt: Date(),
            pointCount: 1,
            surveyMode: .blueprint,
            bundleURL: URL(fileURLWithPath: "/tmp")
        )
        #expect(onePoint.pointCountLabel == "1 point")

        let multiplePoints = HeatmapProjectSummary(
            id: UUID(),
            name: "Test",
            createdAt: Date(),
            pointCount: 42,
            surveyMode: .blueprint,
            bundleURL: URL(fileURLWithPath: "/tmp")
        )
        #expect(multiplePoints.pointCountLabel == "42 points")

        let zeroPoints = HeatmapProjectSummary(
            id: UUID(),
            name: "Test",
            createdAt: Date(),
            pointCount: 0,
            surveyMode: .blueprint,
            bundleURL: URL(fileURLWithPath: "/tmp")
        )
        #expect(zeroPoints.pointCountLabel == "0 points")
    }

    @Test func loadProjectsSetsLoadingDuringExecution() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = makeViewModel(documentsDir: tempDir)
        // After synchronous call, isLoading should be back to false
        vm.loadProjects()
        #expect(vm.isLoading == false)
    }
}

// MARK: - Mock FileManager

/// A FileManager subclass that overrides `urls(for:in:)` to return a custom directory.
/// Used for testing without touching the real Documents directory.
private final class MockDocumentsFileManager: FileManager, @unchecked Sendable {
    private let documentsDir: URL

    init(documentsDir: URL) {
        self.documentsDir = documentsDir
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return [documentsDir]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
