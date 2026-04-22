import Foundation
import NetMonitorCore
import RoomPlan
import UIKit

// MARK: - BlueprintBuilder

/// Off-main pipeline that converts an array of `CapturedRoomData` (one per room scanned)
/// into a complete `BlueprintProject` with preview image and on-disk save.
///
/// The pipeline runs in phases and reports progress so the UI can show which step is running:
///   1. `mergingRooms` — `StructureBuilder` stitches per-room captures into a unified `CapturedStructure`
///   2. `generatingBlueprint` — geometry is normalized and grouped by story into `BlueprintFloor`s
///   3. `renderingPreview` — a PNG preview is rendered for the UI
///   4. `saving` — the project is auto-saved to Documents/Blueprints
///
/// Each phase has its own timeout; the merge phase also falls back to the single-room
/// `RoomBuilder` path if `StructureBuilder` fails with a single input.
actor BlueprintBuilder {

    // MARK: - Types

    enum Phase: String, Equatable {
        case mergingRooms
        case generatingBlueprint
        case renderingPreview
        case saving
    }

    enum BuildError: Error, LocalizedError {
        case noRooms
        case mergeTimedOut
        case mergeFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .noRooms:
                "No rooms were captured. Scan at least one room before finishing."
            case .mergeTimedOut:
                "Merging rooms took too long. Try finishing with fewer rooms or rescan."
            case .mergeFailed(let detail):
                "Failed to merge captured rooms: \(detail)"
            case .saveFailed(let detail):
                "Failed to save blueprint: \(detail)"
            }
        }
    }

    struct Input {
        let capturedRooms: [CapturedRoomData]
        let projectName: String
        let buildingName: String?
        let floorLabel: String
        let floorNumber: Int
        let hasLiDAR: Bool
        let deviceModel: String
    }

    struct Output {
        let blueprint: BlueprintProject
        let previewPNGData: Data
        let localSaveURL: URL?
    }

    typealias ProgressHandler = @Sendable (Phase) async -> Void

    // MARK: - Timeouts

    /// Per-room `RoomBuilder` primary attempt (with beautification).
    private static let roomBuilderPrimaryTimeout: Duration = .seconds(45)
    /// Per-room `RoomBuilder` fallback attempt (no beautification) — typically faster.
    private static let roomBuilderFallbackTimeout: Duration = .seconds(30)
    /// `StructureBuilder` merge of all rooms into a shared coordinate space.
    private static let mergeTimeout: Duration = .seconds(60)
    /// Fallback (no beautification) merge when the primary times out.
    private static let fallbackMergeTimeout: Duration = .seconds(30)

    // MARK: - Pipeline

    func build(input: Input, progress: ProgressHandler) async throws -> Output {
        guard !input.capturedRooms.isEmpty else { throw BuildError.noRooms }

        await progress(.mergingRooms)
        let geometry = try await mergeAndAdapt(capturedRooms: input.capturedRooms)

        await progress(.generatingBlueprint)
        let blueprint = buildBlueprint(geometry: geometry, input: input)

        await progress(.renderingPreview)
        let previewData = renderPreview(blueprint: blueprint)

        await progress(.saving)
        let url = autoSave(blueprint: blueprint)

        return Output(blueprint: blueprint, previewPNGData: previewData, localSaveURL: url)
    }

    // MARK: - Merge + adapt

    /// Converts `[CapturedRoomData]` → `[CapturedRoomGeometry]` in two phases:
    ///
    /// 1. **Per-room build**: `RoomBuilder` processes each `CapturedRoomData` into a
    ///    `CapturedRoom`. Each room has its own timeout; rooms that time out are
    ///    retried without beautification, then dropped if they still fail.
    /// 2. **Structure merge**: `StructureBuilder` stitches the completed
    ///    `CapturedRoom`s into a `CapturedStructure` with a shared coordinate space.
    ///    If the merge fails, each room is rendered independently (loses cross-room
    ///    alignment but still produces a usable blueprint).
    private func mergeAndAdapt(capturedRooms: [CapturedRoomData]) async throws -> [CapturedRoomGeometry] {
        let builtRooms = try await buildEachRoom(capturedRooms: capturedRooms)

        // Single room: skip StructureBuilder — the merge is a no-op and it only slows things down.
        if builtRooms.count == 1 {
            return [RoomPlanGeometryAdapter.extractRoom(builtRooms[0], fallbackIndex: 0)]
        }

        // Multi-room: merge with StructureBuilder for a unified world space.
        do {
            let structure = try await runStructureBuilder(
                rooms: builtRooms,
                beautify: true,
                timeout: Self.mergeTimeout
            )
            return RoomPlanGeometryAdapter.extractRooms(from: structure)
        } catch AsyncTimeoutError.timedOut {
            do {
                let structure = try await runStructureBuilder(
                    rooms: builtRooms,
                    beautify: false,
                    timeout: Self.fallbackMergeTimeout
                )
                return RoomPlanGeometryAdapter.extractRooms(from: structure)
            } catch {
                return builtRooms.enumerated().map { index, room in
                    RoomPlanGeometryAdapter.extractRoom(room, fallbackIndex: index)
                }
            }
        } catch {
            return builtRooms.enumerated().map { index, room in
                RoomPlanGeometryAdapter.extractRoom(room, fallbackIndex: index)
            }
        }
    }

    /// Runs `RoomBuilder` on each `CapturedRoomData` sequentially. Individual rooms
    /// that time out with beautification are retried without it; rooms that still
    /// fail are skipped rather than killing the whole scan.
    private func buildEachRoom(capturedRooms: [CapturedRoomData]) async throws -> [CapturedRoom] {
        var results: [CapturedRoom] = []
        results.reserveCapacity(capturedRooms.count)

        for data in capturedRooms {
            do {
                let room = try await runRoomBuilder(data: data, beautify: true, timeout: Self.roomBuilderPrimaryTimeout)
                results.append(room)
            } catch AsyncTimeoutError.timedOut {
                // Beautification can hang on complex rooms — retry without it.
                do {
                    let room = try await runRoomBuilder(data: data, beautify: false, timeout: Self.roomBuilderFallbackTimeout)
                    results.append(room)
                } catch {
                    // Skip this room — the user still gets the rest.
                    continue
                }
            } catch {
                continue
            }
        }

        if results.isEmpty {
            throw BuildError.mergeTimedOut
        }
        return results
    }

    private nonisolated func runStructureBuilder(
        rooms: [CapturedRoom],
        beautify: Bool,
        timeout: Duration
    ) async throws -> CapturedStructure {
        return try await AsyncTimeout.run(timeout: timeout) {
            // StructureBuilder is not Sendable — create inside closure to avoid capture.
            let builder = beautify
                ? StructureBuilder(options: [.beautifyObjects])
                : StructureBuilder(options: [])
            return try await builder.capturedStructure(from: rooms)
        }
    }

    private nonisolated func runRoomBuilder(
        data: CapturedRoomData,
        beautify: Bool,
        timeout: Duration
    ) async throws -> CapturedRoom {
        return try await AsyncTimeout.run(timeout: timeout) {
            let builder = beautify
                ? RoomBuilder(options: .beautifyObjects)
                : RoomBuilder(options: [])
            return try await builder.capturedRoom(from: data)
        }
    }

    // MARK: - Blueprint assembly

    private func buildBlueprint(geometry: [CapturedRoomGeometry], input: Input) -> BlueprintProject {
        let metadata = BlueprintMetadata(
            buildingName: input.buildingName,
            scanDeviceModel: input.deviceModel,
            hasLiDAR: input.hasLiDAR
        )

        var blueprint = MultiRoomBlueprintBuilder.buildProject(
            name: input.projectName,
            rooms: geometry,
            defaultFloorLabelPrefix: "Floor",
            metadata: metadata
        )

        // When the whole scan landed on one floor, respect the user-entered floor label/number.
        if blueprint.floors.count == 1 {
            blueprint.floors[0].label = input.floorLabel
            blueprint.floors[0].floorNumber = input.floorNumber
        }

        return blueprint
    }

    // MARK: - Preview

    private func renderPreview(blueprint: BlueprintProject) -> Data {
        guard let floor = blueprint.floors.first else { return Data() }
        return SVGRenderer.renderWallsToPNG(
            walls: floor.wallSegments,
            roomLabels: floor.roomLabels,
            widthMeters: floor.widthMeters,
            heightMeters: floor.heightMeters,
            renderWidth: 800
        )
    }

    // MARK: - Save

    private func autoSave(blueprint: BlueprintProject) -> URL? {
        let fileName = blueprint.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let blueprintsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blueprints", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: blueprintsDir, withIntermediateDirectories: true)
            let url = blueprintsDir.appendingPathComponent("\(fileName).netmonblueprint")
            try BlueprintSaveLoadManager().save(project: blueprint, to: url)
            return url
        } catch {
            return nil
        }
    }
}
