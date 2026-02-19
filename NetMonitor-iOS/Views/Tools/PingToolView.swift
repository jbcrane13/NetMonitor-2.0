import SwiftUI
import Charts
import NetMonitorCore

/// Ping tool view for testing host reachability
struct PingToolView: View {
    let initialHost: String?
    @State private var viewModel: PingToolViewModel

    init(initialHost: String? = nil) {
        self.initialHost = initialHost
        self._viewModel = State(initialValue: PingToolViewModel(initialHost: initialHost))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                PingInputSection(viewModel: viewModel)
                controlSection
                latencyChartSection
                resultsSection
                statisticsSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Ping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_pingTool")
    }

    // MARK: - Control Section

    private var controlSection: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            ToolRunButton(
                title: "Start Ping",
                icon: "play.fill",
                isRunning: viewModel.isRunning,
                stopTitle: "Stop Ping",
                action: {
                    if viewModel.isRunning {
                        viewModel.stopPing()
                    } else {
                        viewModel.startPing()
                    }
                }
            )
            .disabled(!viewModel.canStartPing && !viewModel.isRunning)
            .accessibilityIdentifier("pingTool_button_run")

            if !viewModel.results.isEmpty && !viewModel.isRunning {
                ToolClearButton(accessibilityID: "pingTool_button_clear") {
                    viewModel.clearResults()
                }
            }
        }
    }

    // MARK: - Latency Chart

    @ViewBuilder
    private var latencyChartSection: some View {
        if viewModel.successfulPings.count >= 2 {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Text("Latency")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }

                HStack(spacing: 0) {
                    chartStatItem(label: "Avg", value: viewModel.liveAvgLatency)
                    Spacer()
                    chartStatItem(label: "Min", value: viewModel.liveMinLatency, color: Theme.Colors.success)
                    Spacer()
                    chartStatItem(label: "Max", value: viewModel.liveMaxLatency, color: Theme.Colors.warning)
                }

                GlassCard {
                    Chart(viewModel.successfulPings) { result in
                        LineMark(
                            x: .value("Ping", result.sequence),
                            y: .value("ms", result.time)
                        )
                        .foregroundStyle(Color(hex: "007AFF"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Ping", result.sequence),
                            y: .value("ms", result.time)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "007AFF").opacity(0.3), Color(hex: "007AFF").opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...viewModel.chartYAxisMax)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(String(format: "%.0f", v))
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
            }
            .accessibilityIdentifier("pingTool_section_latencyChart")
        }
    }

    private func chartStatItem(label: String, value: Double, color: Color = Theme.Colors.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f ms", value))
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Settings

    private var showDetailedResults: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Keys.showDetailedResults) as? Bool ?? true
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if !viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Text("Results")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    Text("\(viewModel.results.count) of \(viewModel.pingCount)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                GlassCard {
                    let detailed = showDetailedResults
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            PingResultRow(result: result, showDetailed: detailed)

                            if index < viewModel.results.count - 1 {
                                Divider()
                                    .background(Theme.Colors.glassBorder)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("pingTool_section_results")
        }
    }

    // MARK: - Statistics Section

    @ViewBuilder
    private var statisticsSection: some View {
        if let stats = viewModel.statistics {
            ToolStatisticsCard(
                title: "Ping Statistics",
                icon: "chart.bar",
                statistics: [
                    ToolStatistic(
                        label: "Min",
                        value: String(format: "%.1f ms", stats.minTime),
                        valueColor: Theme.Colors.success
                    ),
                    ToolStatistic(
                        label: "Avg",
                        value: String(format: "%.1f ms", stats.avgTime)
                    ),
                    ToolStatistic(
                        label: "Max",
                        value: String(format: "%.1f ms", stats.maxTime),
                        valueColor: Theme.Colors.warning
                    )
                ]
            )
            .accessibilityIdentifier("pingTool_card_statistics")

            if showDetailedResults {
                ToolStatisticsCard(
                    title: "Packet Statistics",
                    icon: "arrow.up.arrow.down",
                    statistics: [
                        ToolStatistic(
                            label: "Sent",
                            value: "\(stats.transmitted)",
                            icon: "arrow.up"
                        ),
                        ToolStatistic(
                            label: "Received",
                            value: "\(stats.received)",
                            icon: "arrow.down"
                        ),
                        ToolStatistic(
                            label: "Loss",
                            value: stats.packetLossText,
                            icon: "xmark",
                            valueColor: stats.packetLoss > 0 ? Theme.Colors.error : Theme.Colors.success
                        )
                    ]
                )
                .accessibilityIdentifier("pingTool_card_packets")
            }
        }
    }
}

// MARK: - Input Section (isolated to prevent full-body re-render on keystrokes)

private struct PingInputSection: View {
    @Bindable var viewModel: PingToolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Target")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.host,
                placeholder: "Enter hostname or IP address",
                icon: "network",
                keyboardType: .URL,
                accessibilityID: "pingTool_input_host",
                onSubmit: {
                    if viewModel.canStartPing {
                        viewModel.startPing()
                    }
                }
            )

            // Ping count picker
            HStack {
                Text("Ping Count")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                Picker("Count", selection: $viewModel.pingCount) {
                    ForEach(viewModel.availablePingCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("pingTool_picker_count")
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Ping Result Row

private struct PingResultRow: View {
    let result: PingResult
    let showDetailed: Bool

    var body: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            // Sequence number
            Text("#\(result.sequence)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: Theme.Layout.resultColumnSmall, alignment: .leading)

            // IP/Host info
            VStack(alignment: .leading, spacing: 2) {
                if let ip = result.ipAddress {
                    Text(ip)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                if showDetailed {
                    HStack(spacing: Theme.Layout.smallCornerRadius) {
                        Label("\(result.size) bytes", systemImage: "doc")
                        Label("TTL \(result.ttl)", systemImage: "clock")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            // Response time
            Text(result.timeText)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(timeColor(for: result.time))
        }
        .accessibilityIdentifier("pingTool_result_\(result.sequence)")
    }

    private func timeColor(for time: Double) -> Color {
        Theme.Colors.latencyColor(ms: time)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PingToolView()
    }
}
