import SwiftUI
import NetMonitorCore

// MARK: - HeatmapDashboardView

/// Dashboard view for the Wi-Fi Heatmap tool.
/// Shows a list of saved survey projects, an empty state when no projects exist,
/// and a button to create a new project.
struct HeatmapDashboardView: View {
    @State private var viewModel = HeatmapDashboardViewModel()
    @State private var activeSurveyVM: HeatmapSurveyViewModel?
    @State private var showSurvey = false
    @State private var showARScan = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                // Header with new project button
                headerSection

                // Create new project options (blueprint + AR scan)
                createProjectSection

                // Project list or empty state
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectListSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Wi-Fi Heatmap")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            viewModel.loadProjects()
        }
        .sheet(isPresented: $viewModel.showNewProjectSheet) {
            NavigationStack {
                NewProjectView { project in
                    viewModel.showNewProjectSheet = false
                    openSurvey(for: project)
                }
            }
        }
        .navigationDestination(isPresented: $showSurvey) {
            if let surveyVM = activeSurveyVM {
                HeatmapSurveyView(viewModel: surveyVM)
            }
        }
        .navigationDestination(isPresented: $showARScan) {
            ARScanView()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .accessibilityIdentifier("heatmap_screen_dashboard")
    }

    // MARK: - Navigation Helpers

    private func openSurvey(for project: SurveyProject) {
        let wifiService = WiFiInfoService()
        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: NoOpSpeedTestService(),
            pingService: NoOpPingService()
        )
        activeSurveyVM = HeatmapSurveyViewModel(
            project: project,
            measurementEngine: engine,
            wifiService: wifiService
        )
        showSurvey = true
    }

    private func openSavedProject(_ summary: HeatmapProjectSummary) {
        let wifiService = WiFiInfoService()
        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: NoOpSpeedTestService(),
            pingService: NoOpPingService()
        )
        if let vm = HeatmapSurveyViewModel.loadProject(
            from: summary.bundleURL,
            measurementEngine: engine,
            wifiService: wifiService
        ) {
            activeSurveyVM = vm
            showSurvey = true
        } else {
            viewModel.errorMessage = "Failed to load project \"\(summary.name)\"."
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Survey Projects")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Create and manage Wi-Fi coverage surveys")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    viewModel.showNewProjectSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                        Text("New")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.accent.opacity(0.15))
                    )
                }
                .accessibilityIdentifier("heatmap_button_newProject")
            }
        }
    }

    // MARK: - Create Project Section

    /// Entry points for creating a new survey: blueprint import and AR scan.
    private var createProjectSection: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            // Blueprint import entry point
            Button {
                viewModel.showNewProjectSheet = true
            } label: {
                GlassCard(padding: 12) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(.cyan)

                        Text("Blueprint Import")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Import floor plan image")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 90)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("heatmap_button_blueprintImport")

            // AR scan entry point
            Button {
                showARScan = true
            } label: {
                GlassCard(padding: 12) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        Text("AR Room Scan")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Scan with camera")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 90)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("heatmap_button_arScan")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Image(systemName: "map.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan.opacity(0.6))

                VStack(spacing: Theme.Layout.smallCornerRadius) {
                    Text("No Survey Projects")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Create a new project to start mapping\nyour Wi-Fi coverage.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    viewModel.showNewProjectSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                        Text("Create New Project")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.Colors.accent.opacity(0.15))
                    )
                }
                .accessibilityIdentifier("heatmap_button_createFirstProject")
            }
            .padding(.vertical, Theme.Layout.sectionSpacing)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("heatmap_emptyState")
    }

    // MARK: - Loading State

    private var loadingState: some View {
        GlassCard {
            VStack(spacing: Theme.Layout.itemSpacing) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                Text("Loading projects…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, Theme.Layout.sectionSpacing)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("heatmap_loadingState")
    }

    // MARK: - Project List

    private var projectListSection: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            ForEach(viewModel.projects) { project in
                Button {
                    openSavedProject(project)
                } label: {
                    ProjectCard(project: project, onDelete: {
                        viewModel.deleteProject(project)
                    })
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("heatmap_projectList")
    }
}

// MARK: - ProjectCard

/// A card displaying summary info for a single saved survey project.
private struct ProjectCard: View {
    let project: HeatmapProjectSummary
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                // Icon
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(.cyan.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.smallCornerRadius))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(project.pointCountLabel, systemImage: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)

                        Text(project.formattedDate)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \"\(project.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the survey project and all its data.")
        }
        .accessibilityIdentifier("heatmap_projectCard_\(project.id.uuidString)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HeatmapDashboardView()
    }
}
