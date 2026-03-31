//
//  SpeedTestToolView.swift
//  NetMonitor
//
//  Speed test tool — uses the shared SpeedTestService (delegate-based, efficient).
//

import SwiftUI
import NetMonitorCore

struct SpeedTestToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var service = SpeedTestService()
    @State private var speedTestTask: Task<Void, Never>?
    @State private var testDuration: TimeInterval = 10
    @State private var timeRemaining: TimeInterval = 0
    @State private var selectedServer: SpeedTestServer = .autoSelect
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        ToolSheetContainer(
            title: "Speed Test",
            iconName: "speedometer",
            closeAccessibilityID: "speedtest_button_close",
            minWidth: 600,
            minHeight: 500,
            inputArea: { contentArea },
            footerContent: { footer }
        )
        .onDisappear {
            speedTestTask?.cancel()
            timerTask?.cancel()
            service.stopTest()
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 32) {
            // Configuration row: duration + server
            HStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Test Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Duration", selection: $testDuration) {
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                        Text("30 seconds").tag(TimeInterval(30))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .disabled(service.isRunning)
                    .accessibilityIdentifier("speedtest_picker_duration")
                }

                VStack(spacing: 8) {
                    Text("Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Server", selection: $selectedServer) {
                        ForEach(SpeedTestServer.all) { server in
                            Text(server.name).tag(server)
                        }
                    }
                    .frame(maxWidth: 180)
                    .disabled(service.isRunning)
                    .accessibilityIdentifier("speedtest_picker_server")
                }
            }

            Spacer()

            speedometerView

            if service.isRunning && (service.phase == .download || service.phase == .upload) && timeRemaining > 0 {
                Text("Time remaining: \(Int(timeRemaining))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            resultsView

            Spacer()

            if !service.isRunning {
                Button {
                    runSpeedTest()
                } label: {
                    Label("Start Test", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("speedtest_button_start")
            } else {
                Button {
                    stopSpeedTest()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("speedtest_button_stop")
            }

            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.2))
    }

    private var speedometerView: some View {
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.gray.opacity(0.3), lineWidth: 20)
                .rotationEffect(.degrees(90))
                .frame(width: 200, height: 200)

            Circle()
                .trim(from: 0.15, to: 0.15 + (0.7 * min(service.progress, 1.0)))
                .stroke(
                    LinearGradient(
                        colors: [accentColor, .green],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: 200, height: 200)
                .animation(.easeInOut(duration: 0.3), value: service.progress)

            VStack(spacing: 4) {
                if service.isRunning {
                    Text(service.phase.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if service.phase == .complete {
                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if service.phase == .download {
                    Text(formatSpeed(service.downloadSpeed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                } else if service.phase == .upload {
                    Text(formatSpeed(service.uploadSpeed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                } else if service.phase == .complete {
                    Text(formatSpeed(service.downloadSpeed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                } else if service.isRunning {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Text("--")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Mbps")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var resultsView: some View {
        HStack(spacing: 48) {
            // Ping
            VStack(spacing: 4) {
                Image(systemName: "waveform.path")
                    .font(.title2)
                    .foregroundStyle(accentColor)

                if service.latency > 0 || service.phase == .complete {
                    Text(String(format: "%.0f", service.latency))
                        .font(.title2.bold())
                    Text("ms ping")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("ms ping")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("speedtest_stat_latency")

            // Download
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.green)

                if service.downloadSpeed > 0 || service.phase == .complete {
                    Text(formatSpeed(service.downloadSpeed))
                        .font(.title2.bold())
                    Text("avg down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if service.peakDownloadSpeed > 0 {
                        Text("Peak: \(formatSpeed(service.peakDownloadSpeed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("speedtest_stat_download")

            // Upload
            VStack(spacing: 4) {
                Image(systemName: "arrow.up.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)

                if service.uploadSpeed > 0 || service.phase == .complete {
                    Text(formatSpeed(service.uploadSpeed))
                        .font(.title2.bold())
                    Text("avg up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if service.peakUploadSpeed > 0 {
                        Text("Peak: \(formatSpeed(service.peakUploadSpeed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("up")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("speedtest_stat_upload")

            // Server
            VStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text(selectedServer.name)
                    .font(.title3.bold())
                Text(selectedServer.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("speedtest_stat_server")
        }
        .accessibilityIdentifier("speedtest_section_results")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let error = service.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .foregroundStyle(.secondary)
            } else if service.isRunning {
                Text(service.phase.displayName)
                    .foregroundStyle(.secondary)
            } else if service.phase == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Test completed")
                    .foregroundStyle(.secondary)
            } else {
                Text("Test your internet connection speed")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if service.phase == .complete && !service.isRunning {
                Button("Reset") {
                    resetTest()
                }
                .accessibilityIdentifier("speedtest_button_reset")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runSpeedTest() {
        service.duration = testDuration
        service.selectedServer = selectedServer.isAutoSelect ? nil : selectedServer

        // Timer for "time remaining" display
        let duration = testDuration
        let startTime = Date()
        timerTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                timeRemaining = max(0, duration - elapsed)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        speedTestTask = Task {
            do {
                _ = try await service.startTest()
            } catch is CancellationError {
                // User cancelled
            } catch {
                // Error is set on service.errorMessage
            }
            timerTask?.cancel()
            timeRemaining = 0
        }
    }

    private func stopSpeedTest() {
        speedTestTask?.cancel()
        speedTestTask = nil
        timerTask?.cancel()
        timerTask = nil
        service.stopTest()
        timeRemaining = 0
    }

    private func resetTest() {
        service.stopTest()
        service = SpeedTestService()
        timeRemaining = 0
    }
}

// MARK: - SpeedTestPhase Display

private extension SpeedTestPhase {
    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .latency: "Testing latency..."
        case .download: "Testing download..."
        case .upload: "Testing upload..."
        case .complete: "Complete"
        }
    }
}

// MARK: - Helpers

private func formatSpeed(_ speed: Double) -> String {
    if speed >= 1000 {
        return String(format: "%.1f Gbps", speed / 1000)
    } else if speed >= 100 {
        return String(format: "%.0f Mbps", speed)
    } else if speed >= 10 {
        return String(format: "%.1f Mbps", speed)
    } else {
        return String(format: "%.2f Mbps", speed)
    }
}

#Preview {
    SpeedTestToolView()
}
