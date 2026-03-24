import NetMonitorCore
import SwiftUI

// MARK: - HeatmapSidebarView

struct HeatmapSidebarView: View {
    @Bindable var viewModel: WiFiHeatmapViewModel

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch viewModel.sidebarMode {
                    case .survey:
                        surveyContent
                    case .analyze:
                        analyzeContent
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 220)
        .accessibilityIdentifier("heatmap_sidebar")
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.sidebarMode) {
            Text("Survey").tag(WiFiHeatmapViewModel.SidebarMode.survey)
            Text("Analyze").tag(WiFiHeatmapViewModel.SidebarMode.analyze)
        }
        .pickerStyle(.segmented)
        .padding(8)
        .accessibilityIdentifier("heatmap_picker_sidebarMode")
    }

    // MARK: - Survey Content

    @ViewBuilder
    private var surveyContent: some View {
        liveSignalCard
        networkInfoSection
        signalQualitySection
        measurementModeSection
        nearbyAPsSection

        if viewModel.surveyProject != nil {
            if viewModel.isSurveying {
                Button {
                    viewModel.stopSurvey()
                } label: {
                    Label("Stop Survey", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("heatmap_button_stopSurvey")
            } else {
                Button {
                    viewModel.startSurvey()
                } label: {
                    Label("Start Survey", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isCalibrated)
                .help(viewModel.isCalibrated ? "Begin recording measurements" : "Calibrate the floor plan first")
                .accessibilityIdentifier("heatmap_button_startSurvey")
            }
        }
    }

    // MARK: - Live Signal Card

    private var liveSignalCard: some View {
        VStack(spacing: 4) {
            Text("LIVE SIGNAL")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let signal = viewModel.currentSignal {
                Text("\(signal.rssi)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(colorForRSSI(signal.rssi))

                Text("dBm · \(qualityLabel(signal.rssi))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                signalBars(rssi: signal.rssi)
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No WiFi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("heatmap_card_liveSignal")
    }

    // MARK: - Network Info

    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Network")
            if let signal = viewModel.currentSignal {
                infoRow("SSID", value: signal.ssid ?? "—")
                infoRow("BSSID", value: signal.bssid.map { String($0.prefix(11)) + "…" } ?? "—")
                infoRow("Channel", value: signal.channel.map { ch in
                    let bandLabel = signal.band?.rawValue ?? ""
                    return "\(ch) (\(bandLabel))"
                } ?? "—")
                infoRow("Link speed", value: signal.linkSpeed.map { "\($0) Mbps" } ?? "—")
            } else {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Signal Quality

    private var signalQualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Signal Quality")
            if let signal = viewModel.currentSignal {
                infoRow("Noise floor", value: signal.noiseFloor.map { "\($0) dBm" } ?? "—")
                infoRow("SNR", value: signal.snr.map { "\($0) dB" } ?? "—")
            }
        }
    }

    // MARK: - Measurement Mode

    private var measurementModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Measurement")
            Picker("Mode", selection: $viewModel.measurementMode) {
                Text("Passive").tag(WiFiHeatmapViewModel.MeasurementMode.passive)
                Text("Active").tag(WiFiHeatmapViewModel.MeasurementMode.active)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("heatmap_picker_measurementMode")

            if viewModel.measurementMode == .active {
                Text("Speed + latency at each point (slower)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(isOn: $viewModel.isContinuousScan) {
                Label("Auto-capture", systemImage: "timer")
                    .font(.caption)
            }
            .accessibilityIdentifier("heatmap_toggle_continuousScan")

            if viewModel.isContinuousScan {
                HStack {
                    Text("Every")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "\(Int(viewModel.continuousScanInterval))s",
                        value: $viewModel.continuousScanInterval,
                        in: 1...30,
                        step: 1
                    )
                    .font(.caption)
                    .accessibilityIdentifier("heatmap_stepper_scanInterval")
                }
                Text("Hover cursor over your position — measurements captured automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Nearby APs

    private var nearbyAPsSection: some View {
        DisclosureGroup("Nearby APs (\(viewModel.nearbyAPs.count))") {
            if viewModel.isScanning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Scanning…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else if viewModel.nearbyAPs.isEmpty {
                Button("Scan") {
                    viewModel.refreshNearbyAPs()
                }
                .font(.caption)
                .accessibilityIdentifier("heatmap_button_scanAPs")
            } else {
                ForEach(viewModel.nearbyAPs) { ap in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ap.ssid)
                                .font(.caption)
                                .lineLimit(1)
                            Text("Ch \(ap.channel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(ap.rssi) dBm")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(colorForRSSI(ap.rssi))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedAPFilter = ap.bssid
                        viewModel.sidebarMode = .analyze
                    }
                    .accessibilityIdentifier("heatmap_ap_\(ap.bssid)")
                }
                Button("Rescan") {
                    viewModel.refreshNearbyAPs()
                }
                .font(.caption)
                .disabled(viewModel.isScanning)
            }
        }
        .font(.caption)
    }

    // MARK: - Analyze Content

    @ViewBuilder
    private var analyzeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Visualization")
            Picker("Type", selection: $viewModel.selectedVisualization) {
                ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                    Text(viz.displayName).tag(viz)
                }
            }
            .accessibilityIdentifier("heatmap_picker_visualization")
            .onChange(of: viewModel.selectedVisualization) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Opacity")
            Slider(value: $viewModel.overlayOpacity, in: 0.1...1.0)
                .accessibilityIdentifier("heatmap_slider_opacity")
                .onChange(of: viewModel.overlayOpacity) { _, _ in
                    viewModel.generateHeatmap()
                }
            Text(String(format: "%.0f%%", viewModel.overlayOpacity * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Color Scheme")
            Picker("Scheme", selection: $viewModel.colorScheme) {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .accessibilityIdentifier("heatmap_picker_colorScheme")
            .onChange(of: viewModel.colorScheme) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("AP Filter")
            Picker("AP", selection: $viewModel.selectedAPFilter) {
                Text("All APs").tag(nil as String?)
                ForEach(viewModel.uniqueBSSIDs, id: \.bssid) { entry in
                    Text(entry.ssid).tag(entry.bssid as String?)
                }
            }
            .accessibilityIdentifier("heatmap_picker_apFilter")
            .onChange(of: viewModel.selectedAPFilter) { _, _ in
                viewModel.generateHeatmap()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Coverage Threshold")
            Toggle("Enable", isOn: $viewModel.isCoverageThresholdEnabled)
                .font(.caption)
                .accessibilityIdentifier("heatmap_toggle_threshold")

            if viewModel.isCoverageThresholdEnabled {
                Slider(value: $viewModel.coverageThreshold, in: -90...(-30))
                    .accessibilityIdentifier("heatmap_slider_threshold")
                Text(String(format: "%.0f dBm", viewModel.coverageThreshold))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Statistics")
            infoRow("Points", value: "\(viewModel.filteredPoints.count)")
            if let avg = viewModel.averageRSSI {
                infoRow("Avg RSSI", value: String(format: "%.1f dBm", avg))
            }
            if let min = viewModel.minRSSI {
                infoRow("Min RSSI", value: "\(min) dBm")
            }
            if let max = viewModel.maxRSSI {
                infoRow("Max RSSI", value: "\(max) dBm")
            }
        }

        if !viewModel.measurementPoints.isEmpty && !viewModel.isHeatmapGenerated {
            Button {
                viewModel.generateHeatmap()
            } label: {
                Label("Generate Heatmap", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("heatmap_button_generate")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2)
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(rssi >= -90 + i * 12 ? colorForRSSI(rssi) : Color.gray.opacity(0.3))
                    .frame(width: 6, height: CGFloat(6 + i * 3))
            }
        }
    }

    private func colorForRSSI(_ rssi: Int) -> Color {
        switch rssi {
        case -50...0: .green
        case -60 ..< -50: .yellow
        case -70 ..< -60: .orange
        default: .red
        }
    }

    private func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "Excellent"
        case -60 ..< -50: "Good"
        case -70 ..< -60: "Fair"
        default: "Weak"
        }
    }
}
