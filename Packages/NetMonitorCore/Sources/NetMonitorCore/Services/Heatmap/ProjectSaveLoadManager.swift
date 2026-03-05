import Foundation

// MARK: - SurveyFileError

public enum SurveyFileError: Error, Sendable, Equatable {
    case bundleNotFound(URL)
    case surveyJSONMissing
    case floorPlanImageMissing
    case corruptedJSON(String)
    case writeFailed(String)

    public var localizedDescription: String {
        switch self {
        case .bundleNotFound(let url):
            "Survey bundle not found at \(url.lastPathComponent)"
        case .surveyJSONMissing:
            "survey.json is missing from the survey bundle"
        case .floorPlanImageMissing:
            "floorplan.png is missing from the survey bundle"
        case .corruptedJSON(let detail):
            "survey.json is corrupted: \(detail)"
        case .writeFailed(let detail):
            "Failed to write survey bundle: \(detail)"
        }
    }
}

// MARK: - ProjectSaveLoadManager

/// Manages saving and loading SurveyProject as .netmonsurvey directory bundles.
///
/// Bundle structure:
/// ```
/// project.netmonsurvey/
///   survey.json        — Serialized SurveyProject (without floor plan image data)
///   floorplan.png      — Floor plan image (stored separately to avoid JSON bloat)
///   heatmap-cache/     — Pre-rendered heatmap images (optional, for fast reopening)
/// ```
public struct ProjectSaveLoadManager: Sendable {

    private static let surveyJSONFilename = "survey.json"
    private static let floorPlanFilename = "floorplan.png"
    private static let heatmapCacheDirectory = "heatmap-cache"

    public init() {}

    // MARK: - Save

    public func save(project: SurveyProject, to url: URL) throws {
        let fileManager = FileManager.default

        // Remove existing bundle to prevent stale files
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw SurveyFileError.writeFailed("Could not remove existing bundle: \(error.localizedDescription)")
            }
        }

        // Create bundle directory
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw SurveyFileError.writeFailed("Could not create bundle directory: \(error.localizedDescription)")
        }

        // Save floor plan image separately
        let imageURL = url.appendingPathComponent(Self.floorPlanFilename)
        do {
            try project.floorPlan.imageData.write(to: imageURL)
        } catch {
            throw SurveyFileError.writeFailed("Could not write floor plan image: \(error.localizedDescription)")
        }

        // Encode project JSON with image data stripped out
        let strippedProject = projectWithEmptyImageData(project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(strippedProject)
        } catch {
            throw SurveyFileError.writeFailed("Could not encode survey JSON: \(error.localizedDescription)")
        }

        let jsonURL = url.appendingPathComponent(Self.surveyJSONFilename)
        do {
            try jsonData.write(to: jsonURL)
        } catch {
            throw SurveyFileError.writeFailed("Could not write survey.json: \(error.localizedDescription)")
        }

        // Create heatmap-cache directory
        let cacheURL = url.appendingPathComponent(Self.heatmapCacheDirectory)
        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Load

    public func load(from url: URL) throws -> SurveyProject {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw SurveyFileError.bundleNotFound(url)
        }

        // Load JSON
        let jsonURL = url.appendingPathComponent(Self.surveyJSONFilename)
        guard fileManager.fileExists(atPath: jsonURL.path) else {
            throw SurveyFileError.surveyJSONMissing
        }

        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            throw SurveyFileError.corruptedJSON("Could not read file: \(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var project: SurveyProject
        do {
            project = try decoder.decode(SurveyProject.self, from: jsonData)
        } catch {
            throw SurveyFileError.corruptedJSON(error.localizedDescription)
        }

        // Restore floor plan image from separate file
        let imageURL = url.appendingPathComponent(Self.floorPlanFilename)
        guard fileManager.fileExists(atPath: imageURL.path) else {
            throw SurveyFileError.floorPlanImageMissing
        }

        let imageData: Data
        do {
            imageData = try Data(contentsOf: imageURL)
        } catch {
            throw SurveyFileError.floorPlanImageMissing
        }

        project.floorPlan.imageData = imageData
        return project
    }

    // MARK: - Cache Management

    public func saveHeatmapCache(
        imageData: Data,
        named filename: String,
        in bundleURL: URL
    ) throws {
        let cacheDir = bundleURL.appendingPathComponent(Self.heatmapCacheDirectory)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        let fileURL = cacheDir.appendingPathComponent(filename)
        try imageData.write(to: fileURL)
    }

    public func loadHeatmapCache(
        named filename: String,
        from bundleURL: URL
    ) -> Data? {
        let fileURL = bundleURL
            .appendingPathComponent(Self.heatmapCacheDirectory)
            .appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    public func clearHeatmapCache(in bundleURL: URL) throws {
        let cacheDir = bundleURL.appendingPathComponent(Self.heatmapCacheDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDir.path) {
            try fileManager.removeItem(at: cacheDir)
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private func projectWithEmptyImageData(_ project: SurveyProject) -> SurveyProject {
        var copy = project
        copy.floorPlan.imageData = Data()
        return copy
    }
}
