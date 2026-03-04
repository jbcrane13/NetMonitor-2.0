import CoreGraphics
import Foundation
import ImageIO

// MARK: - SurveyFileError

/// Errors that can occur when saving or loading `.netmonsurvey` bundle files.
///
/// Conforms to `LocalizedError` to match the project's `NetworkError` pattern,
/// providing `errorDescription` for user-facing display and `failureReason` for detail.
public enum SurveyFileError: LocalizedError, Sendable, Equatable, CustomStringConvertible {
    /// The survey.json file is missing or contains invalid JSON.
    case corruptJSON(String)
    /// The floorplan.png file is missing from the bundle.
    case missingFloorPlan(String)
    /// A file system operation failed (e.g., directory creation, write).
    case fileSystemError(String)
    /// The bundle directory does not exist or is not a directory.
    case bundleNotFound(String)

    public var description: String {
        switch self {
        case .corruptJSON(let message):
            return "Corrupt JSON: \(message)"
        case .missingFloorPlan(let message):
            return "Missing floor plan: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .bundleNotFound(let message):
            return "Bundle not found: \(message)"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .corruptJSON:
            return "The survey file contains invalid data."
        case .missingFloorPlan:
            return "The floor plan image is missing from the survey file."
        case .fileSystemError:
            return "A file system error occurred while saving or loading the survey."
        case .bundleNotFound:
            return "The survey file could not be found."
        }
    }

    public var failureReason: String? {
        switch self {
        case .corruptJSON(let message):
            return message
        case .missingFloorPlan(let message):
            return message
        case .fileSystemError(let message):
            return message
        case .bundleNotFound(let message):
            return message
        }
    }
}

// MARK: - SurveyFileManager

/// Manages saving and loading `.netmonsurvey` bundle files.
///
/// A `.netmonsurvey` bundle is a directory containing:
/// - `survey.json` — serialized `SurveyProject` (with `imageData` replaced by empty `Data`)
/// - `floorplan.png` — the floor plan image as a PNG file
/// - `heatmap-cache/` — optional directory for pre-rendered heatmap images
///
/// On save, the floor plan's `imageData` is extracted and written as `floorplan.png`,
/// while `survey.json` stores a lightweight version without the raw image bytes.
/// On load, `floorplan.png` is read back and injected into the `FloorPlan.imageData` field.
public enum SurveyFileManager {

    // MARK: - Constants

    private static let surveyJSONFilename = "survey.json"
    private static let floorplanPNGFilename = "floorplan.png"

    // MARK: - Save

    /// Saves a `SurveyProject` to a `.netmonsurvey` bundle at the given URL.
    ///
    /// - Parameters:
    ///   - project: The survey project to save.
    ///   - bundleURL: The file URL for the `.netmonsurvey` bundle directory.
    /// - Throws: `SurveyFileError` if the save operation fails.
    public static func save(_ project: SurveyProject, to bundleURL: URL) throws {
        let fileManager = FileManager.default

        // Remove existing bundle if present (overwrite)
        if fileManager.fileExists(atPath: bundleURL.path) {
            do {
                try fileManager.removeItem(at: bundleURL)
            } catch {
                throw SurveyFileError.fileSystemError(
                    "Failed to remove existing bundle at \(bundleURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        // Create the bundle directory
        do {
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        } catch {
            throw SurveyFileError.fileSystemError(
                "Failed to create bundle directory at \(bundleURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        // Extract imageData before encoding JSON
        let imageData = project.floorPlan.imageData

        // Create a copy of the project with empty imageData for the JSON file
        var jsonProject = project
        jsonProject.floorPlan.imageData = Data()

        // Encode project to JSON (without image data)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data
        do {
            jsonData = try encoder.encode(jsonProject)
        } catch {
            throw SurveyFileError.fileSystemError(
                "Failed to encode survey project to JSON: \(error.localizedDescription)"
            )
        }

        // Write survey.json
        let surveyJSONURL = bundleURL.appendingPathComponent(surveyJSONFilename)
        do {
            try jsonData.write(to: surveyJSONURL)
        } catch {
            throw SurveyFileError.fileSystemError(
                "Failed to write \(surveyJSONFilename): \(error.localizedDescription)"
            )
        }

        // Write floorplan.png
        let floorplanURL = bundleURL.appendingPathComponent(floorplanPNGFilename)
        let pngData = encodePNG(from: imageData, width: project.floorPlan.pixelWidth, height: project.floorPlan.pixelHeight)
        do {
            try (pngData ?? imageData).write(to: floorplanURL)
        } catch {
            throw SurveyFileError.fileSystemError(
                "Failed to write \(floorplanPNGFilename): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Load

    /// Loads a `SurveyProject` from a `.netmonsurvey` bundle at the given URL.
    ///
    /// - Parameter bundleURL: The file URL for the `.netmonsurvey` bundle directory.
    /// - Returns: The deserialized `SurveyProject` with floor plan image data restored.
    /// - Throws: `SurveyFileError` if the bundle is missing, corrupt, or incomplete.
    public static func load(from bundleURL: URL) throws -> SurveyProject {
        let fileManager = FileManager.default

        // Verify bundle exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw SurveyFileError.bundleNotFound(
                "Bundle not found at \(bundleURL.lastPathComponent). Ensure the .netmonsurvey file exists."
            )
        }

        // Read and decode survey.json
        let surveyJSONURL = bundleURL.appendingPathComponent(surveyJSONFilename)
        guard fileManager.fileExists(atPath: surveyJSONURL.path) else {
            throw SurveyFileError.corruptJSON(
                "survey.json is missing from the bundle \(bundleURL.lastPathComponent)."
            )
        }

        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: surveyJSONURL)
        } catch {
            throw SurveyFileError.corruptJSON(
                "Failed to read survey.json: \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var project: SurveyProject
        do {
            project = try decoder.decode(SurveyProject.self, from: jsonData)
        } catch {
            throw SurveyFileError.corruptJSON(
                "Failed to decode survey.json: \(error.localizedDescription)"
            )
        }

        // Read floorplan.png
        let floorplanURL = bundleURL.appendingPathComponent(floorplanPNGFilename)
        guard fileManager.fileExists(atPath: floorplanURL.path) else {
            throw SurveyFileError.missingFloorPlan(
                "floorplan.png is missing from the bundle \(bundleURL.lastPathComponent). The floor plan image is required."
            )
        }

        let imageData: Data
        do {
            imageData = try Data(contentsOf: floorplanURL)
        } catch {
            throw SurveyFileError.missingFloorPlan(
                "Failed to read floorplan.png: \(error.localizedDescription)"
            )
        }

        // Inject the image data back into the floor plan
        project.floorPlan.imageData = imageData

        // heatmap-cache/ is optional — no error if missing

        return project
    }

    // MARK: - PNG Encoding Helper

    /// Attempts to re-encode raw image data as PNG. If the input is already valid PNG
    /// or the conversion fails, returns nil (caller falls back to writing original data).
    private static func encodePNG(from data: Data, width: Int, height: Int) -> Data? {
        // Check if data is already a valid PNG (starts with PNG magic bytes)
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if data.count >= 4 {
            let header = [UInt8](data.prefix(4))
            if header == pngMagic {
                return data // Already PNG, use as-is
            }
        }

        // Try to create a CGImage from the raw data and re-encode as PNG
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }
}
