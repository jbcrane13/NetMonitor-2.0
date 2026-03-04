import Foundation
import NetMonitorCore

// MARK: - HeatmapProjectSummary

/// Lightweight summary of a saved survey project for display in the dashboard list.
/// Avoids loading the full floor plan image data.
struct HeatmapProjectSummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let pointCount: Int
    let surveyMode: SurveyMode
    let bundleURL: URL

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var pointCountLabel: String {
        pointCount == 1 ? "1 point" : "\(pointCount) points"
    }
}

// MARK: - HeatmapDashboardViewModel

@MainActor
@Observable
final class HeatmapDashboardViewModel {

    // MARK: - Observable State

    private(set) var projects: [HeatmapProjectSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var showNewProjectSheet = false

    // MARK: - Private

    private let fileManager: FileManager

    // MARK: - Init

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Documents Directory

    /// The app's Documents directory where .netmonsurvey bundles are stored.
    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Load Projects

    /// Scans the Documents directory for .netmonsurvey bundles and loads their summaries.
    func loadProjects() {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let documentsURL = documentsDirectory

        guard let contents = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            projects = []
            return
        }

        let surveyBundles = contents.filter { $0.pathExtension == "netmonsurvey" }

        var summaries: [HeatmapProjectSummary] = []

        for bundleURL in surveyBundles {
            if let summary = loadProjectSummary(from: bundleURL) {
                summaries.append(summary)
            }
        }

        // Sort by creation date, newest first
        summaries.sort { $0.createdAt > $1.createdAt }
        projects = summaries
    }

    // MARK: - Delete Project

    /// Deletes a saved project bundle from the Documents directory.
    func deleteProject(_ project: HeatmapProjectSummary) {
        do {
            try fileManager.removeItem(at: project.bundleURL)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    /// Reads only the survey.json from a bundle to extract summary info
    /// without loading the full floor plan image data.
    private func loadProjectSummary(from bundleURL: URL) -> HeatmapProjectSummary? {
        let surveyJSONURL = bundleURL.appendingPathComponent("survey.json")

        guard let jsonData = try? Data(contentsOf: surveyJSONURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let project = try? decoder.decode(SurveyProject.self, from: jsonData) else {
            return nil
        }

        return HeatmapProjectSummary(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            pointCount: project.measurementPoints.count,
            surveyMode: project.surveyMode,
            bundleURL: bundleURL
        )
    }
}
