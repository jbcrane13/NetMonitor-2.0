import ARKit
import Foundation
import NetMonitorCore
import RoomPlan
import UIKit

// MARK: - RoomPlanScanState

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

    /// Current phase inside `.processing` — drives the progress subtitle in the UI.
    var processingPhase: BlueprintBuilder.Phase = .mergingRooms

    /// Number of rooms whose `CapturedRoomData` has been collected so far. Drives the
    /// "N rooms captured" counters during scanning, between rooms, and during processing.
    private(set) var roomsCapturedCount: Int = 0

    // MARK: - User-editable metadata (preserved API for existing tests)

    var projectName: String = "Room Scan"
    var buildingName: String = ""
    var floorLabel: String = "Floor 1"
    var floorNumber: Int = 1

    var showShareSheet = false
    var showNameEditor = false
    var exportedFileURL: URL?

    // MARK: - Scan output

    private(set) var completedBlueprint: BlueprintProject?
    private(set) var previewImage: UIImage?
    /// Local URL where the blueprint was auto-saved when the scan completed.
    private(set) var localSaveURL: URL?

    // MARK: - LiDAR

    var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - Capture accumulation

    /// Per-room captures collected while the user walks from room to room.
    /// Emptied on `resetScan`.
    private var capturedRoomData: [CapturedRoomData] = []

    // MARK: - Pipeline actor

    private let builder = BlueprintBuilder()
    private var buildTask: Task<Void, Never>?

    // MARK: - Scan flow

    /// Called when the user taps Start. Initializes accumulation and enters the scanning state.
    func startScanning() {
        capturedRoomData = []
        roomsCapturedCount = 0
        scanState = .scanning
    }

    /// Appends the data from one completed room. Called by the view controller after each
    /// `RoomCaptureSession` finishes (either because the user tapped "Next Room" or "Finish").
    func didCompleteRoom(_ data: CapturedRoomData) {
        capturedRoomData.append(data)
        roomsCapturedCount = capturedRoomData.count
    }

    /// Runs the full merge → floor plan → render → save pipeline off the main actor.
    /// Must be called after at least one `didCompleteRoom(_:)`.
    func finalizeScan() {
        guard !capturedRoomData.isEmpty else {
            scanState = .error(BlueprintBuilder.BuildError.noRooms.errorDescription ?? "No rooms captured.")
            return
        }

        processingPhase = .mergingRooms
        scanState = .processing

        let input = BlueprintBuilder.Input(
            capturedRooms: capturedRoomData,
            projectName: projectName.isEmpty ? "Room Scan" : projectName,
            buildingName: buildingName.isEmpty ? nil : buildingName,
            floorLabel: floorLabel,
            floorNumber: floorNumber,
            hasLiDAR: isLiDARAvailable,
            deviceModel: UIDevice.current.model
        )

        buildTask?.cancel()
        buildTask = Task<Void, Never> { [builder, weak self] in
            do {
                let output = try await builder.build(input: input) { [weak self] phase in
                    await self?.applyPhase(phase)
                }
                await self?.applyBuildResult(output)
            } catch let error as BlueprintBuilder.BuildError {
                await self?.applyError(error.errorDescription ?? "Processing failed.")
            } catch is CancellationError {
                // Intentionally cancelled (user reset or view torn down).
            } catch {
                await self?.applyError(error.localizedDescription)
            }
        }
    }

    private func applyPhase(_ phase: BlueprintBuilder.Phase) {
        processingPhase = phase
    }

    private func applyError(_ message: String) {
        scanState = .error(message)
    }

    private func applyBuildResult(_ output: BlueprintBuilder.Output) {
        completedBlueprint = output.blueprint
        localSaveURL = output.localSaveURL
        previewImage = UIImage(data: output.previewPNGData)
        scanState = .complete
    }

    // MARK: - Scan error

    func handleScanError(_ error: Error) {
        scanState = .error(error.localizedDescription)
    }

    // MARK: - Reset

    func resetScan() {
        buildTask?.cancel()
        buildTask = nil
        capturedRoomData = []
        roomsCapturedCount = 0
        scanState = .idle
        completedBlueprint = nil
        previewImage = nil
        exportedFileURL = nil
        localSaveURL = nil
    }

    // MARK: - Export

    func exportBlueprint() {
        guard var blueprint = completedBlueprint else { return }

        blueprint.name = projectName.isEmpty ? "Room Scan" : projectName
        blueprint.metadata.buildingName = buildingName.isEmpty ? nil : buildingName
        if blueprint.floors.count == 1 {
            blueprint.floors[0].label = floorLabel
            blueprint.floors[0].floorNumber = floorNumber
        }
        completedBlueprint = blueprint

        let fileName = blueprint.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).netmonblueprint")

        let snapshot = blueprint
        Task<Void, Never> { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BlueprintSaveLoadManager().saveAsArchive(project: snapshot, to: tempURL)
                }.value
                await self?.applyExportSuccess(url: tempURL)
            } catch {
                await self?.applyError("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyExportSuccess(url: URL) {
        exportedFileURL = url
        showShareSheet = true
    }
}
