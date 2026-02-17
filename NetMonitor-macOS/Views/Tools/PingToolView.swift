import SwiftUI
import NetMonitorCore

struct PingToolView: View {
    @State private var host = ""
    @State private var count = 5
    @State private var isRunning = false
    @State private var outputLines: [String] = []
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
                Text("1").tag(1)
                Text("5").tag(5)
                Text("10").tag(10)
                Text("20").tag(20)
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

    private var outputArea: some View {
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
                    statistics = nil
                    errorMessage = nil
                }
                .accessibilityIdentifier("ping_button_clear")
            }
        }
        .padding()
    }

    private func runPing() {
        guard !host.isEmpty else { return }
        isRunning = true
        outputLines.removeAll()
        statistics = nil
        errorMessage = nil

        outputLines.append("PING \(host) (\(count) packets)...")

        pingTask = Task {
            var results: [PingResult] = []

            let stream = pingService.ping(host: host, count: count, timeout: 5)
            for await result in stream {
                guard !Task.isCancelled else { break }
                results.append(result)

                await MainActor.run {
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

            let stats = await pingService.calculateStatistics(results, requestedCount: count)
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
