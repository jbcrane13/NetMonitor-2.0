//
//  WorldPingToolView.swift
//  NetMonitor
//
//  World Ping tool for macOS — pings a host from global locations via check-host.net.
//

import SwiftUI
import NetMonitorCore

struct WorldPingToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var hostInput = ""
    @State private var isRunning = false
    @State private var results: [WorldPingLocationResult] = []
    @State private var errorMessage: String?
    @State private var runTask: Task<Void, Never>?

    private let service: any WorldPingServiceProtocol = WorldPingService()

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
            runTask?.cancel()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Host (e.g., google.com)", text: $hostInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { startPing() }
                .disabled(isRunning)
                .accessibilityIdentifier("worldPing_input_host")

            Button(isRunning ? "Stop" : "Run") {
                if isRunning { stopPing() } else { startPing() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(hostInput.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning)
            .accessibilityIdentifier("worldPing_button_run")
        }
        .padding()
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        if let error = errorMessage {
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
        } else if results.isEmpty {
            ScrollView {
                if isRunning {
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
                ForEach(results) { result in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(result.isSuccess ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.city)
                                .font(.system(.body, design: .default))
                            Text(result.country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let latency = result.latencyMs {
                            Text(latency < 10 ? String(format: "%.1f ms", latency) : String(format: "%.0f ms", latency))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundStyle(latencyColor(latency))
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
            if isRunning {
                ProgressView().scaleEffect(0.7)
                Text("Pinging from global nodes…")
                    .foregroundStyle(.secondary)
            } else if !results.isEmpty {
                let successCount = results.filter { $0.isSuccess }.count
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(successCount) / \(results.count) nodes responded")
                    .foregroundStyle(.secondary)
            } else {
                Text("Ping from up to 20 global locations")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !results.isEmpty && !isRunning {
                Button("Clear") {
                    results.removeAll()
                    errorMessage = nil
                }
                .accessibilityIdentifier("worldPing_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func startPing() {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }

        results.removeAll()
        errorMessage = nil
        isRunning = true

        runTask = Task {
            let stream = await service.ping(host: host, maxNodes: 20)
            for await result in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    results.append(result)
                    results.sort { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
                }
            }
            await MainActor.run {
                if results.isEmpty && !Task.isCancelled {
                    errorMessage = service.lastError ?? "No results returned. Check the host and your network connection."
                }
                isRunning = false
            }
        }
    }

    private func stopPing() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    private func latencyColor(_ ms: Double) -> Color {
        MacTheme.Colors.latencyColor(ms: ms)
    }
}

#Preview {
    WorldPingToolView()
}
