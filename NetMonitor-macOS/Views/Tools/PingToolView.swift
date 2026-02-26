import SwiftUI
import Charts
import NetMonitorCore

struct PingToolView: View {
    @State private var host = ""
    @AppStorage("netmonitor.ping.defaultCount") private var count = 20
    @AppStorage("netmonitor.lastUsedTarget") private var lastUsedTarget: String = ""
    @State private var isRunning = false
    @State private var outputLines: [String] = []
    @State private var pingResults: [PingResult] = []
    @State private var statistics: PingStatistics?
    @State private var errorMessage: String?
    @State private var pingTask: Task<Void, Never>?
    @State private var pingService = PingService()

    var body: some View {
        ToolSheetContainer(
            title: "Ping",
            iconName: "waveform.path",
            closeAccessibilityID: "ping_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
        .onAppear {
            if host.isEmpty && !lastUsedTarget.isEmpty {
                host = lastUsedTarget
            }
        }
        .onDisappear {
            pingTask?.cancel()
            pingTask = nil
        }
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Hostname or IP address", text: $host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runPing() }
                .disabled(isRunning)
                .accessibilityIdentifier("ping_textfield_host")

            Picker("Count", selection: $count) {
                Text("5").tag(5)
                Text("10").tag(10)
                Text("20").tag(20)
                Text("50").tag(50)
                Text("100").tag(100)
            }
            .frame(width: 80)
            .disabled(isRunning)
            .accessibilityIdentifier("ping_picker_count")

            Button(isRunning ? "Stop" : "Run") {
                if isRunning { stopPing() } else { runPing() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(host.isEmpty && !isRunning)
            .accessibilityIdentifier("ping_button_run")
        }
        .padding()
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(spacing: 0) {
            if chartableResults.count >= 2 {
                latencyChartView
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.red)
                        }

                        if let stats = statistics {
                            summaryView(stats)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .background(Color.black.opacity(0.2))
                .onChange(of: outputLines.count) { _, _ in
                    if let lastIndex = outputLines.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Latency Chart

    private var chartableResults: [PingResult] {
        pingResults.filter { !$0.isTimeout }
    }

    private var liveAvg: Double {
        let times = chartableResults.map(\.time)
        guard !times.isEmpty else { return 0 }
        return times.reduce(0, +) / Double(times.count)
    }

    private var liveMin: Double {
        chartableResults.map(\.time).min() ?? 0
    }

    private var liveMax: Double {
        chartableResults.map(\.time).max() ?? 0
    }

    /// Y-axis max: actual max value with 20% padding, minimum 10ms ceiling so
    /// small latency variations produce visible line movement instead of a flat trace.
    private var chartYMax: Double {
        guard let maxTime = chartableResults.map(\.time).max() else { return 10 }
        return max(maxTime * 1.2, 10)
    }

    private var latencyChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latency")
                    .font(.headline)
                Spacer()
                HStack(spacing: 16) {
                    chartStat("Avg", liveAvg, .primary)
                        .accessibilityIdentifier("ping_stat_avg")
                    chartStat("Min", liveMin, .green)
                        .accessibilityIdentifier("ping_stat_min")
                    chartStat("Max", liveMax, .orange)
                        .accessibilityIdentifier("ping_stat_max")
                }
            }

            Chart(chartableResults) { result in
                LineMark(
                    x: .value("Ping", result.sequence),
                    y: .value("ms", result.time)
                )
                .foregroundStyle(Color.blue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(
                    x: .value("Ping", result.sequence),
                    y: .value("ms", result.time)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...chartYMax)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityIdentifier("ping_chart_latency")
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }

    private func chartStat(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f ms", value))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    // MARK: - Summary

    private func summaryView(_ stats: PingStatistics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 8)
            Text("--- Summary ---")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
            Text("\(stats.transmitted) packets transmitted, \(stats.received) received, \(stats.packetLossText) packet loss")
                .font(.system(.body, design: .monospaced))
            if stats.received > 0 {
                Text("round-trip min/avg/max = \(String(format: "%.2f", stats.minTime))/\(String(format: "%.2f", stats.avgTime))/\(String(format: "%.2f", stats.maxTime)) ms")
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView().scaleEffect(0.7)
                Text("Pinging \(host)...").foregroundStyle(.secondary)
            } else if let stats = statistics {
                Image(systemName: stats.received > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(stats.received > 0 ? .green : .red)
                Text(stats.received > 0 ? "Host is reachable" : "Host unreachable")
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter a hostname or IP address").foregroundStyle(.secondary)
            }

            Spacer()

            if !outputLines.isEmpty && !isRunning {
                Button("Clear") {
                    outputLines.removeAll()
                    pingResults.removeAll()
                    statistics = nil
                    errorMessage = nil
                }
                .accessibilityIdentifier("ping_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runPing() {
        guard !host.isEmpty else { return }
        lastUsedTarget = host
        isRunning = true
        outputLines.removeAll()
        pingResults.removeAll()
        statistics = nil
        errorMessage = nil

        outputLines.append("PING \(host) (\(count) packets)...")

        pingTask = Task {
            var localResults: [PingResult] = []

            let stream = await pingService.ping(host: host, count: count, timeout: 5)
            for await result in stream {
                guard !Task.isCancelled else { break }
                localResults.append(result)

                await MainActor.run {
                    pingResults.append(result)
                    if result.isTimeout {
                        outputLines.append("Request timeout for icmp_seq \(result.sequence)")
                    } else {
                        let ip = result.ipAddress ?? result.host
                        outputLines.append(
                            "\(result.size) bytes from \(ip): icmp_seq=\(result.sequence) ttl=\(result.ttl) time=\(result.timeText)"
                        )
                    }
                }
            }

            guard !Task.isCancelled else { return }
            let stats = await pingService.calculateStatistics(localResults, requestedCount: count)
            await MainActor.run {
                statistics = stats
                isRunning = false
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        Task {
            await pingService.stop()
            await MainActor.run {
                isRunning = false
                outputLines.append("--- Ping cancelled ---")
            }
        }
    }
}

#Preview { PingToolView() }
