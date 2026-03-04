import NetMonitorCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NewProjectView

/// Full-screen view for creating a new heatmap survey project on iOS.
/// Flow: project name → floor plan import → optional calibration → begin survey.
struct NewProjectView: View {
    @State private var viewModel = FloorPlanImportViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Callback when the project is created and ready to survey.
    var onProjectCreated: ((SurveyProject) -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                // Project name
                projectNameSection

                // Floor plan import
                if !viewModel.hasFloorPlan {
                    importSection
                } else {
                    // Floor plan preview with canvas
                    floorPlanPreviewSection

                    // Calibration
                    calibrationSection
                }

                // Location permission
                locationPermissionSection

                // Create button
                if viewModel.hasFloorPlan {
                    createProjectButton
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("New Project")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("heatmap_newProject_cancel")
            }
        }
        .sheet(isPresented: $viewModel.showPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                viewModel.handlePhotoLibraryResult(data)
            }
        }
        .sheet(isPresented: $viewModel.showDocumentPicker) {
            DocumentPicker { url in
                viewModel.handleDocumentPickerResult(url)
            }
        }
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            NavigationStack {
                CalibrationSheetView(viewModel: viewModel)
            }
            .presentationDetents([.large])
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
        .onChange(of: viewModel.isReadyToSurvey) { _, isReady in
            if isReady, let project = viewModel.createdProject {
                onProjectCreated?(project)
            }
        }
        .accessibilityIdentifier("heatmap_screen_newProject")
    }

    // MARK: - Project Name Section

    private var projectNameSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                Label("Project Name", systemImage: "pencil")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TextField("e.g. Office 2nd Floor", text: $viewModel.projectName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.smallCornerRadius)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("heatmap_newProject_nameField")
            }
        }
        .accessibilityIdentifier("heatmap_newProject_nameSection")
    }

    // MARK: - Import Section

    private var importSection: some View {
        GlassCard {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.cyan.opacity(0.6))

                VStack(spacing: 4) {
                    Text("Import Floor Plan")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Import a floor plan image to begin your Wi-Fi survey")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Theme.Layout.itemSpacing) {
                    // Photo Library button
                    Button {
                        viewModel.showPhotoLibraryPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                                .font(.body.weight(.semibold))
                            Text("Photo Library")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                .fill(Theme.Colors.accent.opacity(0.15))
                        )
                    }
                    .accessibilityIdentifier("heatmap_import_photoLibrary")

                    // Files button
                    Button {
                        viewModel.showDocumentPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.body.weight(.semibold))
                            Text("Files")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                .fill(Color.cyan.opacity(0.15))
                        )
                    }
                    .accessibilityIdentifier("heatmap_import_files")
                }

                Text("Supported: PNG, JPEG, HEIC, PDF")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.vertical, Theme.Layout.itemSpacing)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("heatmap_newProject_importSection")
    }

    // MARK: - Floor Plan Preview

    private var floorPlanPreviewSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Label("Floor Plan", systemImage: "map.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    Button {
                        viewModel.showPhotoLibraryPicker = true
                    } label: {
                        Text("Replace")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityIdentifier("heatmap_newProject_replaceFloorPlan")
                }

                if let image = viewModel.floorPlanImage {
                    FloorPlanCanvasView(image: image)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.smallCornerRadius))
                        .accessibilityIdentifier("heatmap_newProject_floorPlanPreview")
                }

                if let result = viewModel.importResult {
                    HStack {
                        Text("\(result.pixelWidth) × \(result.pixelHeight) px")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)

                        Spacer()

                        if viewModel.isCalibrated {
                            Label("Calibrated", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.success)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_newProject_previewSection")
    }

    // MARK: - Calibration Section

    private var calibrationSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                Label("Scale Calibration", systemImage: "ruler")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Set the scale by marking two points of known distance. Calibration is optional — you can skip it and use pixel coordinates.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if viewModel.isCalibrated {
                    // Show calibration result
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Scale:")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(viewModel.scaleBarLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        // Scale bar visualization
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Theme.Colors.accent)
                                .frame(
                                    width: max(40, CGFloat(viewModel.scaleBarFraction) * 200),
                                    height: 4
                                )
                            Spacer()
                        }
                    }

                    Button {
                        viewModel.beginCalibration()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Recalibrate")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityIdentifier("heatmap_newProject_recalibrate")
                } else {
                    Button {
                        viewModel.beginCalibration()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "ruler")
                                .font(.body.weight(.semibold))
                            Text("Calibrate Scale")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                .fill(Theme.Colors.accent.opacity(0.15))
                        )
                    }
                    .accessibilityIdentifier("heatmap_newProject_calibrateButton")
                }
            }
        }
        .accessibilityIdentifier("heatmap_newProject_calibrationSection")
    }

    // MARK: - Location Permission

    private var locationPermissionSection: some View {
        Group {
            if viewModel.locationAuthorizationStatus == .notDetermined ||
                viewModel.locationAuthorizationStatus == .denied ||
                viewModel.locationAuthorizationStatus == .restricted {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                        Label("Location Permission", systemImage: "location.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.warning)

                        Text("Precise location access is required to read Wi-Fi signal data. Grant permission before starting your survey.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Button {
                            viewModel.requestLocationPermission()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                Text("Grant Location Access")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.warning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                    .fill(Theme.Colors.warning.opacity(0.15))
                            )
                        }
                        .accessibilityIdentifier("heatmap_newProject_locationPermission")
                    }
                }
                .accessibilityIdentifier("heatmap_newProject_locationSection")
            }
        }
    }

    // MARK: - Create Project Button

    private var createProjectButton: some View {
        Button {
            viewModel.createProject()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                Text("Begin Survey")
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                    .fill(Theme.Colors.accent)
            )
            .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 8, y: 4)
        }
        .disabled(viewModel.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(viewModel.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        .accessibilityIdentifier("heatmap_newProject_beginSurvey")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NewProjectView()
    }
}
