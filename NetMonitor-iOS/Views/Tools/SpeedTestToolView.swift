import SwiftUI
import NetMonitorCore
import SwiftData

/// Speed Test tool view for measuring download/upload speed and latency
struct SpeedTestToolView: View {
    @State private var viewModel = SpeedTestToolViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeedTestResult.timestamp, order: .reverse) private var history: [SpeedTestResult]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                gaugeSection
                controlSection
                currentResultSection
                historySection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Speed Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_speedTestTool")
    }

    // MARK: - Gauge Section

    private var gaugeSection: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Phase indicator
                Text(viewModel.phaseText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(viewModel.isRunning ? Theme.Colors.accent : Theme.Colors.textSecondary)

                // Speed gauge
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.glassBorder, lineWidth: 8)
                        .frame(width: 160, height: 160)

                    Circle()
                        .trim(from: 0, to: viewModel.isRunning ? viewModel.progress : (viewModel.phase == .complete ? 1.0 : 0))
                        .stroke(
                            gaugeColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(Theme.Animation.standard, value: viewModel.progress)

                    VStack(spacing: 4) {
                        Text(primarySpeedText)
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text(primarySpeedLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("speedTest_gauge")

                // Latency display during/after test
                if viewModel.latency > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(viewModel.latencyText)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var primarySpeedText: String {
        switch viewModel.phase {
        case .idle:
            return "0.0"
        case .latency:
            return viewModel.latencyText
        case .download:
            return String(format: "%.1f", viewModel.downloadSpeed)
        case .upload:
            return String(format: "%.1f", viewModel.uploadSpeed)
        case .complete:
            return String(format: "%.1f", viewModel.downloadSpeed)
        }
    }

    private var primarySpeedLabel: String {
        switch viewModel.phase {
        case .idle: return "Mbps"
        case .latency: return "Latency"
        case .download: return "Download Mbps"
        case .upload: return "Upload Mbps"
        case .complete: return "Download Mbps"
        }
    }

    private var gaugeColor: Color {
        switch viewModel.phase {
        case .idle: return Theme.Colors.accent
        case .latency: return Theme.Colors.info
        case .download: return Theme.Colors.success
        case .upload: return Theme.Colors.warning
        case .complete: return Theme.Colors.success
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(spacing: 12) {
            // Duration picker
            HStack {
                Text("Test Duration")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Picker("Duration", selection: Binding(
                    get: { viewModel.selectedDuration },
                    set: { viewModel.selectedDuration = $0 }
                )) {
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                    Text("30s").tag(30.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .accessibilityIdentifier("speedTest_picker_duration")
            }
            .padding(.horizontal, 4)

            // Server picker
            HStack {
                Text("Server")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Picker("Server", selection: Binding(
                    get: { viewModel.selectedServer },
                    set: { viewModel.selectedServer = $0 }
                )) {
                    ForEach(SpeedTestServer.all) { server in
                        Text(server.isAutoSelect ? server.name : "\(server.name) — \(server.location)").tag(server)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isRunning)
                .accessibilityIdentifier("speedTest_picker_server")
            }
            .padding(.horizontal, 4)

            ToolRunButton(
                title: "Start Test",
                icon: "play.fill",
                isRunning: viewModel.isRunning,
                stopTitle: "Stop Test",
                action: {
                    if viewModel.isRunning {
                        viewModel.stopTest()
                    } else {
                        viewModel.startTest(modelContext: modelContext)
                    }
                }
            )
            .accessibilityIdentifier("speedTest_button_run")
        }
    }

    // MARK: - Current Result Section

    @ViewBuilder
    private var currentResultSection: some View {
        if viewModel.phase == .complete || viewModel.downloadSpeed > 0 || viewModel.uploadSpeed > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Results")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                GlassCard {
                    VStack(spacing: 12) {
                        // Primary: Download / Upload / Latency
                        HStack(spacing: 0) {
                            speedStat(
                                icon: "arrow.down.circle.fill",
                                label: "Download",
                                value: viewModel.downloadSpeedText,
                                color: Theme.Colors.success
                            )

                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .frame(height: 50)

                            speedStat(
                                icon: "arrow.up.circle.fill",
                                label: "Upload",
                                value: viewModel.uploadSpeedText,
                                color: Theme.Colors.warning
                            )

                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .frame(height: 50)

                            speedStat(
                                icon: "clock.fill",
                                label: "Latency",
                                value: viewModel.latencyText,
                                color: Theme.Colors.info
                            )
                        }

                        Divider().background(Theme.Colors.glassBorder)

                        // Secondary: Peak speeds + Jitter
                        HStack(spacing: 0) {
                            miniStat(
                                label: "Peak ↓",
                                value: viewModel.peakDownloadSpeedText,
                                color: Theme.Colors.success
                            )

                            miniStat(
                                label: "Peak ↑",
                                value: viewModel.peakUploadSpeedText,
                                color: Theme.Colors.warning
                            )

                            miniStat(
                                label: "Jitter",
                                value: viewModel.jitterText,
                                color: Theme.Colors.info
                            )
                        }
                    }
                }
            }
            .accessibilityIdentifier("speedTest_results")
        }

        if let error = viewModel.errorMessage {
            GlassCard {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.error)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.error)
                }
            }
            .accessibilityIdentifier("speedTest_error")
        }
    }

    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(color.opacity(0.8))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func speedStat(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("History")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(10).enumerated()), id: \.element.id) { index, result in
                            SpeedTestHistoryRow(result: result)

                            if index < min(history.count, 10) - 1 {
                                Divider()
                                    .background(Theme.Colors.glassBorder)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("speedTest_section_history")
        }
    }
}

// MARK: - History Row

private struct SpeedTestHistoryRow: View {
    let result: SpeedTestResult

    var body: some View {
        HStack(spacing: 12) {

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Label(result.downloadSpeedText, systemImage: "arrow.down")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.success)

                    Label(result.uploadSpeedText, systemImage: "arrow.up")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.warning)

                    Label(result.latencyText, systemImage: "clock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.info)
                }

                if let server = result.serverName {
                    Text(server)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            Text(result.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .accessibilityIdentifier("speedTest_historyRow_\(result.id)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SpeedTestToolView()
            .modelContainer(for: SpeedTestResult.self, inMemory: true)
    }
}
