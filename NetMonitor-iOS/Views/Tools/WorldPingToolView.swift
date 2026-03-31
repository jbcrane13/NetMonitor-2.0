import SwiftUI
import NetMonitorCore

/// World Ping tool — pings a host from global locations via check-host.net
struct WorldPingToolView: View {
    var initialHost: String?
    @State private var viewModel = WorldPingToolViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                WorldPingInputSection(viewModel: viewModel)
                controlSection

                if let error = viewModel.errorMessage {
                    errorCard(error)
                }

                if viewModel.isRunning && viewModel.results.isEmpty {
                    loadingSection
                }

                if viewModel.hasResults {
                    statsBar
                    resultsSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("World Ping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_worldPingTool")
        .onAppear {
            if let host = initialHost, viewModel.hostInput.isEmpty {
                viewModel.hostInput = host
            }
        }
    }

    // MARK: - Controls

    private var controlSection: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            ToolRunButton(
                title: "Run World Ping",
                icon: "globe.americas",
                isRunning: viewModel.isRunning,
                stopTitle: "Stop",
                action: {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.run()
                    }
                }
            )
            .disabled(!viewModel.canRun && !viewModel.isRunning)
            .tint(.teal)
            .accessibilityIdentifier("worldPing_button_run")

            if viewModel.hasResults && !viewModel.isRunning {
                ToolClearButton(accessibilityID: "worldPing_button_clear") {
                    viewModel.clear()
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingSection: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .teal))
                Text("Pinging from global nodes…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Stats Bar

    @ViewBuilder
    private var statsBar: some View {
        HStack(spacing: 0) {
            statItem(label: "Nodes", value: "\(viewModel.results.count)")
                .accessibilityIdentifier("worldPing_stat_nodes")
            Spacer()
            statItem(label: "Success", value: "\(viewModel.successCount)")
                .accessibilityIdentifier("worldPing_stat_success")
            Spacer()
            if let avg = viewModel.averageLatencyMs {
                statItem(label: "Avg", value: avg < 10 ? String(format: "%.1f ms", avg) : String(format: "%.0f ms", avg))
                    .accessibilityIdentifier("worldPing_stat_avg")
                Spacer()
            }
            if let best = viewModel.bestLatencyMs {
                statItem(label: "Best", value: best < 10 ? String(format: "%.1f ms", best) : String(format: "%.0f ms", best), color: Theme.Colors.success)
                    .accessibilityIdentifier("worldPing_stat_best")
            }
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("worldPing_statsBar")
    }

    private func statItem(label: String, value: String, color: Color = Theme.Colors.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Results")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        WorldPingLocationRow(result: result)

                        if index < viewModel.results.count - 1 {
                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("worldPing_section_results")
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Input Section

private struct WorldPingInputSection: View {
    @Bindable var viewModel: WorldPingToolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Host")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.hostInput,
                placeholder: "e.g. google.com or 8.8.8.8",
                icon: "globe.americas",
                keyboardType: .URL,
                accessibilityID: "worldPing_input_host",
                onSubmit: {
                    if viewModel.canRun {
                        viewModel.run()
                    }
                }
            )
        }
    }
}

// MARK: - Location Row

private struct WorldPingLocationRow: View {
    let result: WorldPingLocationResult

    var body: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            // Status indicator
            Circle()
                .fill(result.isSuccess ? Theme.Colors.success : Theme.Colors.error)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.city)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text(result.country)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let ip = result.resolvedAddress {
                        Text("→ \(ip)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            if let latency = result.latencyMs {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(latency < 10 ? String(format: "%.1f ms", latency) : String(format: "%.0f ms", latency))
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.latencyColor(ms: latency))

                    // Mini latency bar
                    LatencyBar(latencyMs: latency, maxMs: 500)
                        .frame(width: 50, height: 4)
                        .clipShape(Capsule())
                }
            } else {
                Text("No response")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityIdentifier("worldPing_location_row_\(result.id)")
    }
}

// MARK: - Latency Bar

private struct LatencyBar: View {
    let latencyMs: Double
    let maxMs: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.glassBorder)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.latencyColor(ms: latencyMs))
                    .frame(width: geo.size.width * CGFloat(min(1.0, latencyMs / maxMs)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorldPingToolView(initialHost: nil)
    }
}
