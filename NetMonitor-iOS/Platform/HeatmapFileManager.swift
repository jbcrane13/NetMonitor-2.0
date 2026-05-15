import Foundation
import NetMonitorCore

// MARK: - SavedSurveyInfo

/// Metadata for a .netmonsurvey file discovered in the Documents directory.
/// Used by `HeatmapProjectsView` to render the saved-projects list.
struct SavedSurveyInfo: Identifiable {
    let name: String
    let url: URL
    let modifiedDate: Date
    let fileSize: Int

    var id: URL { url }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

// MARK: - HeatmapFileManager

/// File-system facade for heatmap survey persistence. Wraps
/// ``ProjectSaveLoadManager`` for the binary `.netmonsurvey` format and falls
/// back to JSON encoding for any other extension. Owns the Documents-directory
/// enumeration used by the saved-projects list and the autosave URL convention.
///
/// Extracted from ``HeatmapSurveyViewModel`` as part of #197 Phase 2 so the VM
/// no longer mixes survey state with file I/O.
struct HeatmapFileManager {
    private let projectManager: ProjectSaveLoadManager

    init(projectManager: ProjectSaveLoadManager = ProjectSaveLoadManager()) {
        self.projectManager = projectManager
    }

    // MARK: - Save / Load

    func save(project: SurveyProject, to url: URL) throws {
        if url.pathExtension == "netmonsurvey" {
            try projectManager.save(project: project, to: url)
        } else {
            let data = try JSONEncoder().encode(project)
            try data.write(to: url, options: .atomic)
        }
    }

    func load(from url: URL) throws -> SurveyProject {
        if url.pathExtension == "netmonsurvey" {
            return try projectManager.load(from: url)
        } else {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SurveyProject.self, from: data)
        }
    }

    /// Auto-save destination for a project of the given name.
    /// Returns `nil` if the Documents directory is unavailable.
    func autoSaveURL(for projectName: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("\(projectName).netmonsurvey")
    }

    // MARK: - Enumeration

    /// Lists every `.netmonsurvey` file in the Documents directory, sorted by
    /// modification date (newest first).
    static func listSavedProjects() -> [SavedSurveyInfo] {
        guard let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
        else { return [] }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "netmonsurvey" }
            .compactMap { url -> SavedSurveyInfo? in
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let name = url.deletingPathExtension().lastPathComponent
                return SavedSurveyInfo(
                    name: name,
                    url: url,
                    modifiedDate: attrs?.contentModificationDate ?? Date.distantPast,
                    fileSize: attrs?.fileSize ?? 0
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    /// Deletes a saved project file at the given URL.
    static func deleteSavedProject(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
