import NetMonitorCore
import SwiftUI

// MARK: - HeatmapSidebarSheet

/// Bottom sheet with survey controls: mode picker, visualization picker, color scheme,
/// opacity slider, measurement list, and action buttons.
struct HeatmapSidebarSheet: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    var shortcutsProvider: ShortcutsWiFiProvider?
    var onShare: (() -> Void)?
    var onSetup: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .onTapGesture { isExpanded.toggle() }

            VStack(spacing: 12) {
                // Survey start/stop + mode toggle
                surveyControlsRow

                if isExpanded {
                    expandedControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
        }
        .glassCard(cornerRadius: 20, padding: 0)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityIdentifier("heatmap_sheet_sidebar")
    }

    // MARK: - Survey Controls Row

    private var surveyControlsRow: some View {
        HStack(spacing: 12) {
            // Survey toggle button
            Button {
                if viewModel.isSurveying {
                    viewModel.stopSurvey()
                } else {
                    viewModel.startSurvey()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isSurveying ? "stop.fill" : "play.fill")
                        .font(.caption.bold())
                    Text(viewModel.isSurveying ? "Stop" : "Survey")
                        .font(.caption.bold())
                }
                .foregroundStyle(viewModel.isSurveying ? Theme.Colors.error : Theme.Colors.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    (viewModel.isSurveying ? Theme.Colors.error : Theme.Colors.accent).opacity(0.2),
                    in: Capsule()
                )
            }
            .disabled(!viewModel.isCalibrated)
            .accessibilityIdentifier("heatmap_button_surveyToggle")

            // Mode picker
            Picker("Mode", selection: Binding(
                get: { viewModel.measurementMode },
                set: { viewModel.measurementMode = $0 }
            )) {
                Text("Passive").tag(HeatmapSurveyViewModel.MeasurementMode.passive)
                Text("Active").tag(HeatmapSurveyViewModel.MeasurementMode.active)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("heatmap_picker_mode")

            // Expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityIdentifier("heatmap_button_expandSidebar")
        }
    }

    // MARK: - Expanded Controls

    private var expandedControls: some View {
        VStack(spacing: 12) {
            // Fallback banner when Shortcuts not available
            if shortcutsProvider?.isAvailable != true {
                Button {
                    onSetup?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Install Wi-Fi Shortcut for signal data")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("heatmap_button_shortcutBanner")
            }

            Divider().background(Theme.Colors.divider)

            // Visualization picker
            visualizationPicker

            // Color scheme picker
            colorSchemePicker

            // Opacity slider
            opacitySlider

            // Stats + actions
            statsAndActions
        }
    }

    // MARK: - Visualization Picker

    private var visualizationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visualization")
                .font(.caption.bold())
                .foregroundStyle(Theme.Colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HeatmapVisualization.allCases, id: \.rawValue) { viz in
                        let isSelected = viewModel.selectedVisualization == viz
                        let hasData = viz.hasData(in: viewModel.measurementPoints)
                        let needsActive = viz.requiresActiveScan

                        Button {
                            viewModel.selectedVisualization = viz
                            viewModel.updateHeatmap()
                        } label: {
                            VStack(spacing: 2) {
                                Text(viz.displayName)
                                    .font(.caption2.bold())
                                Text(viz.unit)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? Theme.Colors.accent.opacity(0.2)
                                    : Theme.Colors.glassBackground,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Theme.Colors.accent.opacity(0.5) : Theme.Colors.glassBorder,
                                        lineWidth: 0.5
                                    )
                            )
                            .opacity(!hasData && !viewModel.measurementPoints.isEmpty ? 0.5 : 1.0)
                        }
                        .disabled(needsActive && viewModel.measurementMode == .passive && !hasData)
                        .accessibilityIdentifier("heatmap_button_viz_\(viz.rawValue)")
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_picker_visualization")
    }

    // MARK: - Color Scheme Picker

    private var colorSchemePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color Scheme")
                .font(.caption.bold())
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: 8) {
                ForEach(HeatmapColorScheme.allCases, id: \.rawValue) { scheme in
                    let isSelected = viewModel.selectedColorScheme == scheme

                    Button {
                        viewModel.selectedColorScheme = scheme
                        viewModel.updateHeatmap()
                    } label: {
                        HStack(spacing: 4) {
                            colorSchemePreview(scheme)
                            Text(scheme.displayName)
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? Theme.Colors.accent.opacity(0.2)
                                : Theme.Colors.glassBackground,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ? Theme.Colors.accent.opacity(0.5) : Theme.Colors.glassBorder,
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .accessibilityIdentifier("heatmap_button_color_\(scheme.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("heatmap_picker_colorScheme")
    }

    private func colorSchemePreview(_ scheme: HeatmapColorScheme) -> some View {
        let colors: [Color] = switch scheme {
        case .thermal: [.blue, .cyan, .green, .yellow, .red]
        case .stoplight: [.red, .orange, .yellow, .green]
        case .plasma: [Color(red: 0.05, green: 0.01, blue: 0.2), .purple, .red, .orange, .yellow]
        case .wifiman: [.red, .yellow, .green]
        }

        return HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { i in
                colors[i]
                    .frame(width: 4, height: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    // MARK: - Opacity Slider

    private var opacitySlider: some View {
        HStack(spacing: 8) {
            Text("Opacity")
                .font(.caption.bold())
                .foregroundStyle(Theme.Colors.textSecondary)

            Slider(
                value: Binding(
                    get: { viewModel.heatmapOpacity },
                    set: { newValue in
                        viewModel.heatmapOpacity = newValue
                        viewModel.updateHeatmap()
                    }
                ),
                in: 0.1...1.0
            )
            .tint(Theme.Colors.accent)
            .accessibilityIdentifier("heatmap_slider_opacity")

            Text("\(Int(viewModel.heatmapOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Stats & Actions

    private var statsAndActions: some View {
        HStack(spacing: 12) {
            // Measurement count
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                Text("\(viewModel.measurementPoints.count) pts")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityIdentifier("heatmap_label_measurementCount")

            // Average RSSI
            if let avg = viewModel.averageRSSI {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(Int(avg)) dBm avg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("heatmap_label_averageRSSI")
            }

            Spacer()

            // Undo
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.bold())
                    .foregroundStyle(viewModel.canUndo ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .disabled(!viewModel.canUndo)
            .accessibilityIdentifier("heatmap_button_undo")

            // Clear
            Button {
                viewModel.clearMeasurements()
            } label: {
                Image(systemName: "trash")
                    .font(.caption.bold())
                    .foregroundStyle(viewModel.measurementPoints.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.error)
            }
            .disabled(viewModel.measurementPoints.isEmpty)
            .accessibilityIdentifier("heatmap_button_clear")

            // Share
            Button {
                onShare?()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption.bold())
                    .foregroundStyle(viewModel.measurementPoints.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accent)
            }
            .disabled(viewModel.measurementPoints.isEmpty)
            .accessibilityIdentifier("heatmap_button_sidebarShare")

            // Calibrate
            Button {
                viewModel.startCalibration()
            } label: {
                Image(systemName: "ruler")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityIdentifier("heatmap_button_calibrate")
        }
    }
}
