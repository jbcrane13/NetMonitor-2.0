import Foundation

// MARK: - ProjectSaveLoadManager

/// Manages saving and loading SurveyProject as .netmonsurvey directory bundles.
/// Full implementation tracked in NetMonitor20-2v2.
public struct ProjectSaveLoadManager: Sendable {

    public init() {}

    /// Saves a SurveyProject to a .netmonsurvey directory bundle.
    /// Bundle structure:
    ///   - survey.json: Serialized SurveyProject (metadata, points, calibration)
    ///   - floorplan.png: Floor plan image data
    public func save(project: SurveyProject, to url: URL) throws {
        let bundlePath = url.path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)

        let jsonURL = url.appendingPathComponent("survey.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(project)
        try jsonData.write(to: jsonURL)

        let imageURL = url.appendingPathComponent("floorplan.png")
        try project.floorPlan.imageData.write(to: imageURL)
    }

    /// Loads a SurveyProject from a .netmonsurvey directory bundle.
    public func load(from url: URL) throws -> SurveyProject {
        let jsonURL = url.appendingPathComponent("survey.json")
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        var project = try decoder.decode(SurveyProject.self, from: jsonData)

        let imageURL = url.appendingPathComponent("floorplan.png")
        if FileManager.default.fileExists(atPath: imageURL.path) {
            let imageData = try Data(contentsOf: imageURL)
            project.floorPlan.imageData = imageData
        }

        return project
    }
}
