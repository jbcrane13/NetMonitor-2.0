import ARKit
import Foundation
import NetMonitorCore
import RoomPlan
import simd
import UIKit

// MARK: - ScanState

enum RoomPlanScanState: Equatable {
    case idle
    case scanning
    case processing
    case complete
    case error(String)
}

// MARK: - RoomPlanScannerViewModel

@MainActor
@Observable
final class RoomPlanScannerViewModel {

    // MARK: - State

    var scanState: RoomPlanScanState = .idle
    var projectName: String = "Room Scan"
    var buildingName: String = ""
    var floorLabel: String = "Floor 1"
    var floorNumber: Int = 1

    private(set) var completedBlueprint: BlueprintProject?
    private(set) var previewImage: UIImage?

    var showShareSheet = false
    var showNameEditor = false
    var exportedFileURL: URL?

    var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - RoomPlan Session

    private var capturedRoom: CapturedRoom?

    /// Local URL where the blueprint was auto-saved on scan completion.
    private(set) var localSaveURL: URL?

    // MARK: - Scan Control

    func processCapturedRoom(_ room: CapturedRoom) {
        scanState = .processing
        capturedRoom = room

        let blueprint = buildBlueprint(from: room)
        completedBlueprint = blueprint

        // Generate a preview image from the floor plan
        // On iOS, UIImage can't render SVG — use direct Core Graphics renderer
        if let floor = blueprint.floors.first {
            #if canImport(UIKit)
            let pngData = SVGRenderer.renderWallsToPNG(
                walls: floor.wallSegments,
                roomLabels: floor.roomLabels,
                widthMeters: floor.widthMeters,
                heightMeters: floor.heightMeters,
                renderWidth: 800
            )
            #else
            let pngData = SVGRenderer.renderToPNG(
                svgData: floor.svgData,
                width: 800,
                heightMeters: floor.heightMeters,
                widthMeters: floor.widthMeters
            )
            #endif
            previewImage = UIImage(data: pngData)
        }

        // Auto-save locally so the blueprint exists without requiring an export tap
        autoSaveBlueprint(blueprint)

        scanState = .complete
    }

    private func autoSaveBlueprint(_ blueprint: BlueprintProject) {
        let fileName = blueprint.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let blueprintsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blueprints", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: blueprintsDir, withIntermediateDirectories: true)
            let url = blueprintsDir.appendingPathComponent("\(fileName).netmonblueprint")
            let manager = BlueprintSaveLoadManager()
            try manager.save(project: blueprint, to: url)
            localSaveURL = url
        } catch {
            // Non-fatal — user can still export manually
            localSaveURL = nil
        }
    }

    func handleScanError(_ error: Error) {
        scanState = .error(error.localizedDescription)
    }

    func resetScan() {
        scanState = .idle
        capturedRoom = nil
        completedBlueprint = nil
        previewImage = nil
        exportedFileURL = nil
        localSaveURL = nil
    }

    // MARK: - Export

    func exportBlueprint() {
        guard var blueprint = completedBlueprint else { return }

        // Update metadata from user input
        blueprint.name = projectName.isEmpty ? "Room Scan" : projectName
        blueprint.metadata.buildingName = buildingName.isEmpty ? nil : buildingName
        if !blueprint.floors.isEmpty {
            blueprint.floors[0].label = floorLabel
            blueprint.floors[0].floorNumber = floorNumber
        }
        completedBlueprint = blueprint

        let fileName = blueprint.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).netmonblueprint")

        do {
            let manager = BlueprintSaveLoadManager()
            try manager.saveAsArchive(project: blueprint, to: tempURL)
            exportedFileURL = tempURL
            showShareSheet = true
        } catch {
            scanState = .error("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Build Blueprint from CapturedRoom

    private func buildBlueprint(from room: CapturedRoom) -> BlueprintProject {
        let walls = extractWallSegments(from: room)
        let (widthMeters, heightMeters, offsetX, offsetZ) = calculateBounds(walls: walls)

        let normalizedWalls = walls.map { wall in
            WallSegment(
                id: wall.id,
                startX: wall.startX - offsetX,
                startY: wall.startY - offsetZ,
                endX: wall.endX - offsetX,
                endY: wall.endY - offsetZ,
                thickness: wall.thickness
            )
        }

        let roomLabels = extractRoomLabels(
            from: room,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            offsetX: offsetX,
            offsetZ: offsetZ
        )

        let svgData = SVGFloorPlanGenerator.generateSVG(
            walls: normalizedWalls,
            roomLabels: roomLabels,
            widthMeters: widthMeters,
            heightMeters: heightMeters
        )

        let floor = BlueprintFloor(
            label: floorLabel,
            floorNumber: floorNumber,
            svgData: svgData,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            roomLabels: roomLabels,
            wallSegments: normalizedWalls
        )

        let deviceModel = UIDevice.current.model
        let metadata = BlueprintMetadata(
            buildingName: buildingName.isEmpty ? nil : buildingName,
            scanDeviceModel: deviceModel,
            hasLiDAR: isLiDARAvailable
        )

        return BlueprintProject(
            name: projectName.isEmpty ? "Room Scan" : projectName,
            floors: [floor],
            metadata: metadata
        )
    }

    // MARK: - Wall Extraction

    private func extractWallSegments(from room: CapturedRoom) -> [WallSegment] {
        var segments: [WallSegment] = []

        for wall in room.walls {
            let transform = wall.transform
            let halfWidth = wall.dimensions.x / 2
            let thickness = wall.dimensions.z

            // Compute wall endpoints in world coordinates by transforming local-space endpoints
            let localStart = simd_float4(-halfWidth, 0, 0, 1)
            let localEnd = simd_float4(halfWidth, 0, 0, 1)

            let worldStart = simd_mul(transform, localStart)
            let worldEnd = simd_mul(transform, localEnd)

            segments.append(WallSegment(
                startX: Double(worldStart.x),
                startY: Double(worldStart.z),
                endX: Double(worldEnd.x),
                endY: Double(worldEnd.z),
                thickness: max(Double(thickness), 0.1)
            ))
        }

        for door in room.doors {
            let transform = door.transform
            let halfWidth = door.dimensions.x / 2

            let localStart = simd_float4(-halfWidth, 0, 0, 1)
            let localEnd = simd_float4(halfWidth, 0, 0, 1)

            let worldStart = simd_mul(transform, localStart)
            let worldEnd = simd_mul(transform, localEnd)

            segments.append(WallSegment(
                startX: Double(worldStart.x),
                startY: Double(worldStart.z),
                endX: Double(worldEnd.x),
                endY: Double(worldEnd.z),
                thickness: 0.03
            ))
        }

        return segments
    }

    // MARK: - Room Labels

    private func extractRoomLabels(
        from room: CapturedRoom,
        widthMeters: Double,
        heightMeters: Double,
        offsetX: Double,
        offsetZ: Double
    ) -> [RoomLabel] {
        guard widthMeters > 0, heightMeters > 0 else { return [] }

        var labels: [RoomLabel] = []

        // Use wall positions to infer room centers — group walls by proximity
        // For CapturedRoom, walls belong to the overall room structure
        // We create a single label at the centroid of all walls if no sections available
        if !room.walls.isEmpty {
            let centerX = room.walls.reduce(0.0) { sum, wall in
                sum + Double(wall.transform.columns.3.x)
            } / Double(room.walls.count)

            let centerZ = room.walls.reduce(0.0) { sum, wall in
                sum + Double(wall.transform.columns.3.z)
            } / Double(room.walls.count)

            let normalizedX = (centerX - offsetX) / widthMeters
            let normalizedY = (centerZ - offsetZ) / heightMeters

            labels.append(RoomLabel(
                text: "Room",
                normalizedX: max(0, min(1, normalizedX)),
                normalizedY: max(0, min(1, normalizedY))
            ))
        }

        return labels
    }

    // MARK: - Bounds

    private func calculateBounds(walls: [WallSegment]) -> (width: Double, height: Double, offsetX: Double, offsetZ: Double) {
        guard !walls.isEmpty else { return (10, 10, 0, 0) }

        var minX = Double.infinity
        var maxX = -Double.infinity
        var minZ = Double.infinity
        var maxZ = -Double.infinity

        for wall in walls {
            minX = min(minX, wall.startX, wall.endX)
            maxX = max(maxX, wall.startX, wall.endX)
            minZ = min(minZ, wall.startY, wall.endY)
            maxZ = max(maxZ, wall.startY, wall.endY)
        }

        let margin = 0.5
        let width = max(maxX - minX + margin * 2, 1.0)
        let height = max(maxZ - minZ + margin * 2, 1.0)

        return (width, height, minX - margin, minZ - margin)
    }
}
