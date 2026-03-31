import SwiftUI
import NetMonitorCore

/// Traceroute tool view for tracing network path
struct TracerouteToolView: View {
    @State private var viewModel: TracerouteToolViewModel

    init(initialHost: String? = nil) {
        self._viewModel = State(initialValue: TracerouteToolViewModel(initialHost: initialHost))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                inputSection
                controlSection
                hopsSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Traceroute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_tracerouteTool")
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.host,
                placeholder: "Enter hostname or IP address",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                keyboardType: .URL,
                accessibilityID: "tracerouteTool_input_host",
                onSubmit: {
                    if viewModel.canStartTrace {
                        viewModel.startTrace()
                    }
                }
            )

            // Max hops picker
            HStack {
                Text("Max Hops")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                Picker("Max Hops", selection: $viewModel.maxHops) {
                    ForEach(viewModel.availableMaxHops, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("tracerouteTool_picker_maxHops")
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        HStack(spacing: 12) {
            ToolRunButton(
                title: "Start Trace",
                icon: "play.fill",
                isRunning: viewModel.isRunning,
                stopTitle: "Stop Trace",
                action: {
                    if viewModel.isRunning {
                        viewModel.stopTrace()
                    } else {
                        viewModel.startTrace()
                    }
                }
            )
            .disabled(!viewModel.canStartTrace && !viewModel.isRunning)
            .accessibilityIdentifier("tracerouteTool_button_run")

            if !viewModel.hops.isEmpty && !viewModel.isRunning {
                ToolClearButton(accessibilityID: "tracerouteTool_button_clear") {
                    viewModel.clearResults()
                }
            }
        }
    }

    // MARK: - Hops Section

    @ViewBuilder
    private var hopsSection: some View {
        if !viewModel.hops.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Route")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    if viewModel.isRunning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                            .scaleEffect(0.8)
                    }

                    Text("\(viewModel.completedHops) hops")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.hops.enumerated()), id: \.element.id) { index, hop in
                            TracerouteHopRow(hop: hop, isLast: index == viewModel.hops.count - 1)

                            if index < viewModel.hops.count - 1 {
                                HopConnector()
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("tracerouteTool_section_hops")
        }
    }
}

// MARK: - Traceroute Hop Row

private struct TracerouteHopRow: View {
    let hop: TracerouteHop
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Hop number badge
            Text("\(hop.hopNumber)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(hopColor.opacity(0.2))
                )
                .overlay(
                    Circle()
                        .stroke(hopColor.opacity(0.5), lineWidth: 1)
                )

            // Address info
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.displayAddress)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(hop.isTimeout ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)

                if let ip = hop.ipAddress, hop.hostname != nil {
                    Text(ip)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            // Response time
            Text(hop.timeText)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(hop.isTimeout ? Theme.Colors.textTertiary : timeColor)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("tracerouteTool_row_\(hop.hopNumber)")
    }

    private var hopColor: Color {
        if hop.isTimeout {
            return Theme.Colors.textTertiary
        }
        return isLast ? Theme.Colors.success : Theme.Colors.accent
    }

    private var timeColor: Color {
        guard let avgTime = hop.averageTime else {
            return Theme.Colors.textPrimary
        }
        switch avgTime {
        case ..<Theme.Thresholds.latencyGood: return Theme.Colors.success
        case Theme.Thresholds.latencyGood..<Theme.Thresholds.latencyWarning: return Theme.Colors.warning
        default: return Theme.Colors.error
        }
    }
}

// MARK: - Hop Connector

private struct HopConnector: View {
    var body: some View {
        HStack {
            Spacer()
                .frame(width: 14)

            Rectangle()
                .fill(Theme.Colors.glassBorder)
                .frame(width: 1, height: 16)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TracerouteToolView()
    }
}
