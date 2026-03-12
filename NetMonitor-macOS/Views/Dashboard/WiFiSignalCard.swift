//
//  WiFiSignalCard.swift
//  NetMonitor-macOS
//
//  Card displaying WiFi signal strength with real-time trend graph.
//

import SwiftUI
import Charts
import NetMonitorCore

/// Model for tracking signal strength history
struct SignalSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rssi: Int
}

/// Card displaying WiFi signal strength with trend visualization
struct WiFiSignalCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var currentRSSI: Int?
    @State private var currentChannel: Int?
    @State private var linkSpeed: Int?
    @State private var ssid: String?
    @State private var isLoading = true
    @State private var signalHistory: [SignalSample] = []
    @State private var isMonitoring = false
    @State private var monitorTask: Task<Void, Never>?

    private let networkService = NetworkInfoService()
    private let maxHistoryCount = 60 // ~2 minutes at 2-second intervals

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("WiFi Signal", systemImage: "wifi")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                // Live indicator
                if isMonitoring {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Toggle monitoring button
                Button(action: toggleMonitoring) {
                    Image(systemName: isMonitoring ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isMonitoring ? .orange : MacTheme.Colors.info)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wifi_signal_button_toggle")
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(height: 80)
            } else if currentRSSI == nil {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No WiFi connection")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            } else {
                // Signal Strength Gauge
                HStack(spacing: 20) {
                    // Current RSSI with quality indicator
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(currentRSSI ?? 0)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(signalQualityLabel)
                            .font(.caption)
                            .foregroundStyle(signalQualityColor)
                    }

                    Spacer()

                    // Signal bars visualization
                    signalBarsView
                }

                // Trend Graph
                if !signalHistory.isEmpty {
                    chartView
                        .frame(height: 80)
                }

                // Additional info row
                HStack(spacing: 16) {
                    if let ssid = ssid {
                        Label(ssid, systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let channel = currentChannel {
                        Label("Ch \(channel)", systemImage: "wave.3.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let speed = linkSpeed {
                        Label("\(speed) Mbps", systemImage: "bolt.horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Average over history
                    if !signalHistory.isEmpty {
                        let avg = signalHistory.map(\.rssi).reduce(0, +) / signalHistory.count
                        Text("Avg: \(avg) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: 14, padding: 0)
        .task {
            await loadInitialSignal()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    // MARK: - Computed Properties

    private var signalQualityLabel: String {
        guard let rssi = currentRSSI else { return "Unknown" }
        switch rssi {
        case -50...0: return "Excellent"
        case -60..<(-50): return "Very Good"
        case -70..<(-60): return "Good"
        case -80..<(-70): return "Fair"
        default: return "Weak"
        }
    }

    private var signalQualityColor: Color {
        guard let rssi = currentRSSI else { return .secondary }
        switch rssi {
        case -60...0: return MacTheme.Colors.success
        case -70..<(-60): return MacTheme.Colors.warning
        case -80..<(-70): return .orange
        default: return MacTheme.Colors.error
        }
    }

    private var signalBarsView: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 6, height: CGFloat((index + 1) * 6) + 4)
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        guard let rssi = currentRSSI else { return Color.white.opacity(0.3) }
        let barsFilled: Int
        switch rssi {
        case -50...0: barsFilled = 4
        case -60..<(-50): barsFilled = 3
        case -70..<(-60): barsFilled = 2
        case -80..<(-70): barsFilled = 1
        default: barsFilled = 0
        }
        return index < barsFilled ? signalQualityColor : Color.white.opacity(0.3)
    }

    private var chartView: some View {
        Chart(signalHistory) { sample in
            LineMark(
                x: .value("Time", sample.timestamp, unit: .minute),
                y: .value("RSSI", sample.rssi)
            )
            .foregroundStyle(MacTheme.Colors.info.gradient)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", sample.timestamp, unit: .minute),
                y: .value("RSSI", sample.rssi)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [MacTheme.Colors.info.opacity(0.3), MacTheme.Colors.info.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rssi = value.as(Int.self) {
                        Text("\(rssi)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: -100 ... -20 as ClosedRange<Int>)
        .chartXAxis(.hidden)
    }

    // MARK: - Actions

    private func loadInitialSignal() async {
        isLoading = true
        await refreshSignal()
        isLoading = false
    }

    private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    private func startMonitoring() {
        isMonitoring = true
        monitorTask = Task {
            while !Task.isCancelled {
                await refreshSignal()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func refreshSignal() async {
        do {
            let info = try await networkService.getCurrentConnection()
            guard info.connectionType == .wifi else {
                // Not WiFi - clear values
                currentRSSI = nil
                currentChannel = nil
                linkSpeed = nil
                ssid = nil
                return
            }

            currentRSSI = info.signalStrength
            currentChannel = info.channel
            linkSpeed = info.linkSpeed
            ssid = info.ssid

            // Add to history
            if let rssi = info.signalStrength {
                let sample = SignalSample(timestamp: Date(), rssi: rssi)
                await MainActor.run {
                    signalHistory.append(sample)
                    // Trim old history
                    if signalHistory.count > maxHistoryCount {
                        signalHistory.removeFirst(signalHistory.count - maxHistoryCount)
                    }
                }
            }
        } catch {
            // Silently handle errors - just don't update
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack {
        WiFiSignalCard()
            .frame(width: 350)
    }
    .padding()
    .background(Color.black)
}
#endif