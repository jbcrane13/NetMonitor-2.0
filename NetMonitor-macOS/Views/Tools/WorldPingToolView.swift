//
//  WorldPingToolView.swift
//  NetMonitor
//
//  World Ping tool for macOS — pings a host from global locations via Globalping.io.
//

import SwiftUI
import NetMonitorCore

struct WorldPingToolView: View {
    // periphery:ignore
    @Environment(\.appAccentColor) private var accentColor
    @State private var viewModel = MacWorldPingToolViewModel()

    var body: some View {
        ToolSheetContainer(
            title: "World Ping",
            iconName: "globe.americas",
            closeAccessibilityID: "worldPing_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Host (e.g., google.com)", text: $viewModel.hostInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.run() }
                .disabled(viewModel.isRunning)
                .accessibilityIdentifier("worldPing_input_host")

            Button(viewModel.isRunning ? "Stop" : "Run") {
                if viewModel.isRunning { viewModel.stop() } else { viewModel.run() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRun && !viewModel.isRunning)
            .accessibilityIdentifier("worldPing_button_run")
        }
        .padding()
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        if let error = viewModel.errorMessage {
            ScrollView {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(MacTheme.Colors.subtleBackground)
        } else if viewModel.results.isEmpty {
            ScrollView {
                if viewModel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Pinging from global nodes…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else {
                    Text("Enter a hostname or IP address to ping from global locations")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .background(MacTheme.Colors.subtleBackground)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.results) { result in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(result.isSuccess ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.city)
                                .font(.system(.body, design: .default))
                            HStack(spacing: 4) {
                                Text(result.country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let ip = result.resolvedAddress {
                                    Text("→ \(ip)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer()

                        if let latency = result.latencyMs {
                            Text(latency < 10 ? String(format: "%.1f ms", latency) : String(format: "%.0f ms", latency))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundStyle(MacTheme.Colors.latencyColor(ms: latency))
                        } else {
                            Text("—")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("worldPing_location_row")

                    Divider().padding(.horizontal)
                }
            }
            .padding(.vertical, 4)
        }
        .background(MacTheme.Colors.subtleBackground)
        .accessibilityIdentifier("worldPing_section_results")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.isRunning {
                ProgressView().scaleEffect(0.7)
                Text("Pinging from global nodes…")
                    .foregroundStyle(.secondary)
            } else if viewModel.hasResults {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(viewModel.successCount) / \(viewModel.results.count) nodes responded")
                    .foregroundStyle(.secondary)
            } else {
                Text("Ping from up to 20 global locations")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.hasResults && !viewModel.isRunning {
                Button("Clear") {
                    viewModel.clear()
                }
                .accessibilityIdentifier("worldPing_button_clear")
            }
        }
        .padding()
    }
}

#Preview {
    WorldPingToolView()
}
