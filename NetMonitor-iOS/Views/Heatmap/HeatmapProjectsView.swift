import SwiftUI

// MARK: - HeatmapProjectsView

/// Lists saved .netmonsurvey projects from the Documents directory.
/// Allows opening, deleting, and sharing saved heatmap surveys.
struct HeatmapProjectsView: View {
    let onSelectProject: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [SavedSurveyInfo] = []
    @State private var showDeleteConfirmation = false
    @State private var projectToDelete: SavedSurveyInfo?

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .themedBackground()
            .navigationTitle("Saved Surveys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("heatmapProjects_button_cancel")
                }
            }
            .onAppear { refreshProjects() }
            .alert("Delete Survey?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        deleteProject(project)
                    }
                }
                .accessibilityIdentifier("heatmapProjects_button_confirmDelete")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("heatmapProjects_button_cancelDelete")
            } message: {
                if let project = projectToDelete {
                    Text("This will permanently delete \"\(project.name)\".")
                }
            }
        }
        .accessibilityIdentifier("screen_heatmapProjects")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No Saved Surveys")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Surveys auto-save during mapping.\nStart a new survey to get started.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
    }

    // MARK: - Project List

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Layout.itemSpacing) {
                ForEach(projects) { project in
                    projectRow(project)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, Theme.Layout.itemSpacing)
        }
    }

    private func projectRow(_ project: SavedSurveyInfo) -> some View {
        Button {
            onSelectProject(project.url)
            dismiss()
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.accent.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(project.modifiedDate.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)

                            Text(project.formattedSize)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    Spacer()

                    // Delete button
                    Button {
                        projectToDelete = project
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.error.opacity(0.7))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityIdentifier("heatmapProjects_button_delete_\(project.name)")

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .accessibilityIdentifier("heatmapProjects_row_\(project.name)")
    }

    // MARK: - Actions

    private func refreshProjects() {
        projects = HeatmapSurveyViewModel.listSavedProjects()
    }

    private func deleteProject(_ project: SavedSurveyInfo) {
        try? HeatmapSurveyViewModel.deleteSavedProject(at: project.url)
        refreshProjects()
    }
}
