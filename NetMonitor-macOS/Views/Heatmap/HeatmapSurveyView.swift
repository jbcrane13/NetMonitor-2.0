import NetMonitorCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - HeatmapSurveyView

/// The main heatmap survey view for macOS.
/// Split view layout: left canvas (floor plan with measurements), right sidebar (point list + stats).
/// Toolbar provides import, calibrate, live RSSI badge, and dimension info.
struct HeatmapSurveyView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    @State private var showingNewProjectSheet = false
    @State private var showingDrawFloorPlan = false
    @State private var newProjectName = ""

    var body: some View {
        Group {
            if viewModel.hasFloorPlan {
                surveyContentView
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isCalibrationSheetPresented) {
            CalibrationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            newProjectSheet
        }
        .sheet(isPresented: $showingDrawFloorPlan) {
            DrawFloorPlanView(
                canvasWidth: 1000,
                canvasHeight: 800,
                onComplete: { imageData in
                    showingDrawFloorPlan = false
                    viewModel.applyDrawnFloorPlan(name: newProjectName, imageData: imageData)
                },
                onCancel: {
                    showingDrawFloorPlan = false
                }
            )
            .frame(minWidth: 700, minHeight: 550)
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .onAppear {
            viewModel.startLiveRSSIUpdates()
        }
        .onDisappear {
            viewModel.stopLiveRSSIUpdates()
        }
        .background {
            // Hidden buttons to provide keyboard shortcuts
            keyboardShortcutButtons
        }
        .accessibilityIdentifier("heatmap_survey_view")
    }

    // MARK: - Split View Content

    private var surveyContentView: some View {
        VStack(spacing: 0) {
            surveyToolbar
            Divider()
            HSplitView {
                canvasSection
                    .frame(minWidth: 400)

                MeasurementSidebarView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Canvas Section (Left)

    private var canvasSection: some View {
        ZStack(alignment: .bottomLeading) {
            HeatmapCanvasView(viewModel: viewModel) { normalizedPoint in
                Task {
                    await viewModel.takeMeasurement(at: normalizedPoint)
                }
            }

            // Scale bar overlay (shown after calibration)
            if viewModel.isCalibrated {
                scaleBarOverlay
                    .padding(16)
            }

            // Missing data overlay for current visualization type
            if let points = viewModel.project?.measurementPoints,
               points.count >= 3,
               !viewModel.visualizationHasData {
                missingDataOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Missing Data Overlay

    private var missingDataOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No \(viewModel.visualizationDisplayName) Data")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(missingDataHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("heatmap_missing_data_overlay")
    }

    private var missingDataHint: String {
        switch viewModel.selectedVisualization {
        case .signalStrength:
            return "Signal strength data should always be available."
        case .signalToNoise:
            return "SNR requires noise floor data. Ensure your WiFi adapter reports noise floor."
        case .downloadSpeed, .uploadSpeed:
            return "Speed data requires active scan mode. Enable active scanning in the toolbar."
        case .latency:
            return "Latency data requires active scan mode. Enable active scanning in the toolbar."
        }
    }

    // MARK: - Empty State (Import Prompt)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_import_icon")

            Text("Start a WiFi Survey")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("heatmap_import_title")

            Text("Import a floor plan image, draw one, or open an existing project.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("heatmap_import_subtitle")

            Text("Supported formats: PNG, JPEG, HEIC, PDF")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("heatmap_import_formats")

            HStack(spacing: 16) {
                Button(action: {
                    viewModel.importFloorPlan()
                }) {
                    Label("Import Floor Plan", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("heatmap_import_button")

                Button(action: {
                    showingNewProjectSheet = true
                }) {
                    Label("New Project", systemImage: "plus.rectangle.on.rectangle")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("heatmap_new_project_button")

                Button(action: {
                    viewModel.openProject()
                }) {
                    Label("Open Project", systemImage: "folder")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("heatmap_open_project_button")
            }
        }
        .padding(40)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcutButtons: some View {
        // Hidden buttons providing keyboard shortcut bindings
        VStack {
            Button("Save") { viewModel.saveProject() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Open") { viewModel.openProject() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Undo") { viewModel.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndo)
            Button("Redo") { viewModel.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedo)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - New Project Sheet

    private var newProjectSheet: some View {
        VStack(spacing: 20) {
            Text("New Survey Project")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("heatmap_new_project_title")

            TextField("Project Name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .accessibilityIdentifier("heatmap_new_project_name_field")

            Text("Choose how to provide a floor plan:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // Import image
                Button(action: {
                    showingNewProjectSheet = false
                    let name = newProjectName.isEmpty ? "Untitled Survey" : newProjectName
                    viewModel.importFloorPlanForNewProject(name: name)
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title)
                        Text("Import Image")
                            .font(.callout)
                    }
                    .frame(width: 120, height: 80)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("heatmap_new_project_import")

                // Draw floor plan
                Button(action: {
                    showingNewProjectSheet = false
                    if newProjectName.isEmpty {
                        newProjectName = "Untitled Survey"
                    }
                    showingDrawFloorPlan = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "pencil.and.ruler")
                            .font(.title)
                        Text("Draw Floor Plan")
                            .font(.callout)
                    }
                    .frame(width: 120, height: 80)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("heatmap_new_project_draw")

                // Blank canvas
                Button(action: {
                    showingNewProjectSheet = false
                    let name = newProjectName.isEmpty ? "Untitled Survey" : newProjectName
                    viewModel.createNewProject(name: name)
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.dashed")
                            .font(.title)
                        Text("Blank Canvas")
                            .font(.callout)
                    }
                    .frame(width: 120, height: 80)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("heatmap_new_project_blank")
            }

            HStack {
                Button("Cancel") {
                    showingNewProjectSheet = false
                    newProjectName = ""
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("heatmap_new_project_cancel")
            }
        }
        .padding(24)
        .frame(width: 460)
        .accessibilityIdentifier("heatmap_new_project_sheet")
    }

    // MARK: - Survey Toolbar

    private var surveyToolbar: some View {
        HStack(spacing: 12) {
            // Import new floor plan
            Button(action: {
                viewModel.importFloorPlan()
            }) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("heatmap_toolbar_import")

            Divider()
                .frame(height: 20)

            // Calibration
            Button(action: {
                viewModel.startCalibration()
            }) {
                Label(
                    viewModel.isCalibrated ? "Recalibrate" : "Calibrate Scale",
                    systemImage: "ruler"
                )
            }
            .accessibilityIdentifier("heatmap_toolbar_calibrate")

            if viewModel.isCalibrated {
                Text("✓ Calibrated")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("heatmap_toolbar_calibrated_badge")
            }

            Divider()
                .frame(height: 20)

            // Active/passive scan mode toggle
            scanModeToggle
                .accessibilityIdentifier("heatmap_toolbar_scan_mode_toggle")

            Divider()
                .frame(height: 20)

            // Live RSSI badge
            liveRSSIBadge
                .accessibilityIdentifier("heatmap_toolbar_rssi_badge")

            Divider()
                .frame(height: 20)

            // Visualization type picker
            visualizationPicker
                .accessibilityIdentifier("heatmap_toolbar_visualization_picker")

            Divider()
                .frame(height: 20)

            // Undo / Redo
            undoRedoButtons

            Spacer()

            // Measuring indicator with progress
            if viewModel.isMeasuring {
                if viewModel.isActiveScanMode, let progress = viewModel.activeMeasurementProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .accessibilityIdentifier("heatmap_toolbar_active_progress")
                    Text("Active scan…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("heatmap_toolbar_measuring_indicator")
                    Text("Measuring…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Save / Open buttons
            Button(action: {
                viewModel.openProject()
            }) {
                Label("Open", systemImage: "folder")
            }
            .accessibilityIdentifier("heatmap_toolbar_open")

            Button(action: {
                viewModel.saveProject()
            }) {
                Label("Save", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(viewModel.project == nil)
            .accessibilityIdentifier("heatmap_toolbar_save")

            Divider()
                .frame(height: 20)

            // PDF Export button
            Button(action: {
                viewModel.exportPDF()
            }) {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(!viewModel.canExportPDF)
            .help(viewModel.canExportPDF
                ? "Export a 3-page PDF report"
                : "Requires at least 3 measurement points")
            .accessibilityIdentifier("heatmap_toolbar_export_pdf")

            // Floor plan dimensions
            if let result = viewModel.importResult {
                Text("\(result.pixelWidth) × \(result.pixelHeight) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("heatmap_toolbar_dimensions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("heatmap_toolbar")
    }

    // MARK: - Scan Mode Toggle

    private var scanModeToggle: some View {
        Picker("Scan Mode", selection: $viewModel.isActiveScanMode) {
            Text("Passive").tag(false)
            Text("Active").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
        .help(viewModel.isActiveScanMode
            ? "Active: runs speed test + ping at each point (~6s)"
            : "Passive: captures WiFi signal info only")
    }

    // MARK: - Undo / Redo Buttons

    private var undoRedoButtons: some View {
        HStack(spacing: 4) {
            Button(action: {
                viewModel.undo()
            }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .help("Undo (⌘Z)")
            .accessibilityIdentifier("heatmap_toolbar_undo")

            Button(action: {
                viewModel.redo()
            }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
            .help("Redo (⇧⌘Z)")
            .accessibilityIdentifier("heatmap_toolbar_redo")
        }
    }

    // MARK: - Visualization Picker

    private var visualizationPicker: some View {
        Picker("Visualization", selection: $viewModel.selectedVisualization) {
            ForEach(HeatmapVisualization.allCases, id: \.self) { type in
                Text(displayName(for: type))
                    .tag(type)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 160)
    }

    private func displayName(for visualization: HeatmapVisualization) -> String {
        switch visualization {
        case .signalStrength: "Signal Strength"
        case .signalToNoise: "Signal to Noise"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .latency: "Latency"
        }
    }

    // MARK: - Live RSSI Badge

    private var liveRSSIBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi")
                .font(.caption)
                .foregroundStyle(rssiColor)
            Text(viewModel.liveRSSIBadgeText)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rssiColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var rssiColor: Color {
        guard let rssi = viewModel.liveRSSI
        else { return .gray }
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        return .red
    }

    // MARK: - Scale Bar

    private var scaleBarOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(.white)
                .frame(width: scaleBarWidth, height: 3)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: 8)
                        Spacer()
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: 8)
                    }
                    .frame(width: scaleBarWidth)
                )

            Text(viewModel.scaleBarLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("heatmap_scale_bar")
    }

    private var scaleBarWidth: CGFloat {
        let width = viewModel.scaleBarFraction * 500
        return max(30, min(200, width))
    }
}

#if DEBUG
#Preview("Empty State") {
    HeatmapSurveyView(viewModel: HeatmapSurveyViewModel())
        .frame(width: 1000, height: 700)
}
#endif
