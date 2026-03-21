import Foundation

// MARK: - BlueprintFileError

public enum BlueprintFileError: Error, Sendable, Equatable {
    case bundleNotFound(URL)
    case blueprintJSONMissing
    case svgMissing(String)
    case corruptedJSON(String)
    case writeFailed(String)

    public var localizedDescription: String {
        switch self {
        case .bundleNotFound(let url):
            "Blueprint bundle not found at \(url.lastPathComponent)"
        case .blueprintJSONMissing:
            "blueprint.json is missing from the blueprint bundle"
        case .svgMissing(let name):
            "SVG file '\(name)' is missing from the blueprint bundle"
        case .corruptedJSON(let detail):
            "blueprint.json is corrupted: \(detail)"
        case .writeFailed(let detail):
            "Failed to write blueprint bundle: \(detail)"
        }
    }
}

// MARK: - BlueprintSaveLoadManager

/// Manages saving and loading BlueprintProject as .netmonblueprint directory bundles.
///
/// Bundle structure:
/// ```
/// project.netmonblueprint/
///   blueprint.json      — Serialized BlueprintProject (without SVG data inlined)
///   floor-1.svg         — SVG floor plan for floor 1
///   floor-2.svg         — SVG floor plan for floor 2 (if multi-floor)
///   model.usdz          — Optional 3D mesh from RoomPlan (future use)
/// ```
public struct BlueprintSaveLoadManager: Sendable {

    private static let blueprintJSONFilename = "blueprint.json"

    public init() {}

    // MARK: - Save

    public func save(project: BlueprintProject, to url: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw BlueprintFileError.writeFailed(
                    "Could not remove existing bundle: \(error.localizedDescription)"
                )
            }
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw BlueprintFileError.writeFailed(
                "Could not create bundle directory: \(error.localizedDescription)"
            )
        }

        // Save each floor's SVG as a separate file
        for (index, floor) in project.floors.enumerated() {
            let svgFilename = Self.svgFilename(forFloorIndex: index)
            let svgURL = url.appendingPathComponent(svgFilename)
            do {
                try floor.svgData.write(to: svgURL)
            } catch {
                throw BlueprintFileError.writeFailed(
                    "Could not write SVG for floor \(index): \(error.localizedDescription)"
                )
            }
        }

        // Encode project JSON with SVG data stripped out
        let strippedProject = projectWithEmptySVGData(project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(strippedProject)
        } catch {
            throw BlueprintFileError.writeFailed(
                "Could not encode blueprint JSON: \(error.localizedDescription)"
            )
        }

        let jsonURL = url.appendingPathComponent(Self.blueprintJSONFilename)
        do {
            try jsonData.write(to: jsonURL)
        } catch {
            throw BlueprintFileError.writeFailed(
                "Could not write blueprint.json: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Load

    public func load(from url: URL) throws -> BlueprintProject {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw BlueprintFileError.bundleNotFound(url)
        }

        let jsonURL = url.appendingPathComponent(Self.blueprintJSONFilename)
        guard fileManager.fileExists(atPath: jsonURL.path) else {
            throw BlueprintFileError.blueprintJSONMissing
        }

        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            throw BlueprintFileError.corruptedJSON(
                "Could not read file: \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var project: BlueprintProject
        do {
            project = try decoder.decode(BlueprintProject.self, from: jsonData)
        } catch {
            throw BlueprintFileError.corruptedJSON(error.localizedDescription)
        }

        // Restore SVG data from separate files
        for index in project.floors.indices {
            let svgFilename = Self.svgFilename(forFloorIndex: index)
            let svgURL = url.appendingPathComponent(svgFilename)
            guard fileManager.fileExists(atPath: svgURL.path) else {
                throw BlueprintFileError.svgMissing(svgFilename)
            }
            do {
                project.floors[index].svgData = try Data(contentsOf: svgURL)
            } catch {
                throw BlueprintFileError.svgMissing(svgFilename)
            }
        }

        return project
    }

    // MARK: - Conversion to FloorPlan

    /// Converts a BlueprintFloor's SVG into a FloorPlan for use in heatmap surveys.
    /// The floor plan is pre-calibrated from RoomPlan data (no manual calibration needed).
    public static func floorPlanFromBlueprint(
        _ floor: BlueprintFloor,
        renderWidth: Int = 2048
    ) -> FloorPlan {
        // Render SVG to PNG for the heatmap canvas
        let pngData = SVGRenderer.renderToPNG(
            svgData: floor.svgData,
            width: renderWidth,
            heightMeters: floor.heightMeters,
            widthMeters: floor.widthMeters
        )

        let aspectRatio = floor.heightMeters / max(floor.widthMeters, 0.001)
        let renderHeight = Int(Double(renderWidth) * aspectRatio)

        return FloorPlan(
            imageData: pngData,
            widthMeters: floor.widthMeters,
            heightMeters: floor.heightMeters,
            pixelWidth: renderWidth,
            pixelHeight: renderHeight,
            origin: .arGenerated,
            walls: floor.wallSegments
        )
    }

    // MARK: - Private

    private static func svgFilename(forFloorIndex index: Int) -> String {
        "floor-\(index + 1).svg"
    }

    private func projectWithEmptySVGData(_ project: BlueprintProject) -> BlueprintProject {
        var copy = project
        for index in copy.floors.indices {
            copy.floors[index].svgData = Data()
        }
        return copy
    }
}
