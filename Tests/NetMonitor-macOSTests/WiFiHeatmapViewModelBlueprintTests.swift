import Foundation
import Testing
@testable import NetMonitor_macOS
import NetMonitorCore

struct WiFiHeatmapViewModelBlueprintTests {

    // MARK: - Happy Path

    @Test @MainActor
    func importBlueprintCreatesSurveyProject() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.surveyProject != nil)
    }

    @Test @MainActor
    func importBlueprintSetsProjectName() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint(name: "Office Blueprint")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.surveyProject?.name == "Office Blueprint")
    }

    @Test @MainActor
    func importBlueprintSetsIsCalibrated() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.isCalibrated == true)
    }

    @Test @MainActor
    func importBlueprintSetsIsCalibratingFalse() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        // Set isCalibrating to true first to verify it gets cleared
        vm.isCalibrating = true
        try vm.importBlueprint(from: url)
        #expect(vm.isCalibrating == false)
    }

    @Test @MainActor
    func importBlueprintClearsMeasurementPoints() throws {
        let vm = WiFiHeatmapViewModel()
        // Pre-populate with a measurement point
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60)
        ]
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test @MainActor
    func importBlueprintClearsHeatmap() throws {
        let vm = WiFiHeatmapViewModel()
        // Simulate pre-existing heatmap state
        vm.isHeatmapGenerated = true
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.heatmapCGImage == nil)
        #expect(vm.isHeatmapGenerated == false)
    }

    @Test @MainActor
    func importBlueprintPreservesBuildingName() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint(buildingName: "Headquarters")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        #expect(vm.surveyProject?.metadata.buildingName == "Headquarters")
    }

    @Test @MainActor
    func importBlueprintFloorPlanDimensions() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint(widthMeters: 12.0, heightMeters: 9.5)
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        let floorPlan = try #require(vm.surveyProject?.floorPlan)
        #expect(floorPlan.widthMeters == 12.0)
        #expect(floorPlan.heightMeters == 9.5)
    }

    @Test @MainActor
    func importBlueprintFloorPlanOrigin() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprint()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importBlueprint(from: url)
        let floorPlan = try #require(vm.surveyProject?.floorPlan)
        #expect(floorPlan.origin == .arGenerated)
    }

    // MARK: - Error Cases

    @Test @MainActor
    func importBlueprintMissingFileThrows() throws {
        let vm = WiFiHeatmapViewModel()
        let bogusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent.netmonblueprint")
        #expect(throws: (any Error).self) {
            try vm.importBlueprint(from: bogusURL)
        }
    }

    @Test @MainActor
    func importBlueprintEmptyFloorsThrows() throws {
        let vm = WiFiHeatmapViewModel()
        let url = try createTestBlueprintWithNoFloors()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect {
            try vm.importBlueprint(from: url)
        } throws: { error in
            (error as? HeatmapError) == .noFloorPlan
        }
    }

    // MARK: - Error Message Property

    @Test @MainActor
    func errorMessageIsNilInitially() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor
    func errorMessageCanBeSet() {
        let vm = WiFiHeatmapViewModel()
        vm.errorMessage = "Something went wrong"
        #expect(vm.errorMessage == "Something went wrong")
        vm.errorMessage = nil
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Helpers

    private func createTestBlueprint(
        name: String = "Test Blueprint",
        widthMeters: Double = 8.0,
        heightMeters: Double = 6.0,
        buildingName: String? = "Test Building"
    ) throws -> URL {
        let svgData = SVGFloorPlanGenerator.generateSVG(
            walls: [WallSegment(startX: 0, startY: 0, endX: 8, endY: 0)],
            roomLabels: [RoomLabel(text: "Room", normalizedX: 0.5, normalizedY: 0.5)],
            widthMeters: widthMeters,
            heightMeters: heightMeters
        )
        let floor = BlueprintFloor(
            svgData: svgData,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            roomLabels: [RoomLabel(text: "Room", normalizedX: 0.5, normalizedY: 0.5)],
            wallSegments: [WallSegment(startX: 0, startY: 0, endX: 8, endY: 0)]
        )
        let blueprint = BlueprintProject(
            name: name,
            floors: [floor],
            metadata: BlueprintMetadata(buildingName: buildingName, hasLiDAR: true)
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: blueprint, to: tempURL)
        return tempURL
    }

    private func createTestBlueprintWithNoFloors() throws -> URL {
        let blueprint = BlueprintProject(
            name: "Empty Blueprint",
            floors: [],
            metadata: BlueprintMetadata()
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".netmonblueprint")
        let manager = BlueprintSaveLoadManager()
        try manager.save(project: blueprint, to: tempURL)
        return tempURL
    }
}
