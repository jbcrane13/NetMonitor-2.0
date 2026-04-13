import SwiftUI
import NetMonitorCore

struct TracerouteToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var host = ""
    @State private var maxHops = 30
    @AppStorage("netmonitor.lastUsedTarget") private var lastUsedTarget: String = ""
    @State private var isRunning = false
    @State private var hops: [TracerouteHop] = []
    @State private var errorMessage: String?
    @State private var tracerouteTask: Task<Void, Never>?

    private let service = TracerouteService()

    var body: some View {
        ToolSheetContainer(
            title: "Traceroute",
            iconName: "point.topleft.down.to.point.bottomright.curvepath",
            closeAccessibilityID: "traceroute_button_close",
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
            tracerouteTask?.cancel()
            tracerouteTask = nil
        }
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Hostname or IP address", text: $host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runTraceroute() }
                .disabled(isRunning)
                .accessibilityIdentifier("traceroute_textfield_host")

            Picker("Max Hops", selection: $maxHops) {
                Text("15").tag(15)
                Text("30").tag(30)
                Text("64").tag(64)
            }
            .fixedSize()
            .disabled(isRunning)
            .accessibilityIdentifier("traceroute_picker_hops")

            Button(isRunning ? "Stop" : "Trace") {
                if isRunning { stopTraceroute() } else { runTraceroute() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(host.isEmpty && !isRunning)
            .accessibilityIdentifier("traceroute_button_run")
        }
        .padding()
    }

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if hops.isEmpty && errorMessage == nil && !isRunning {
                        Text("Enter a hostname to trace the network path")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(hops) { hop in
                            hopRow(hop).id(hop.id)
                        }
                        .accessibilityIdentifier("traceroute_section_hops")
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(MacTheme.Colors.subtleBackground)
            .onChange(of: hops.count) { _, _ in
                if let lastHop = hops.last { proxy.scrollTo(lastHop.id, anchor: .bottom) }
            }
        }
    }

    private func hopRow(_ hop: TracerouteHop) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%2d", hop.hopNumber))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 25, alignment: .trailing)

            if hop.isTimeout {
                Text("* * *")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.orange)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(hop.hostname ?? hop.ipAddress ?? "unknown")
                            .font(.system(.body, design: .monospaced))

                        if let ip = hop.ipAddress, hop.hostname != nil {
                            Text("(\(ip))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !hop.times.isEmpty {
                        Text(hop.times.map { String(format: "%.2f ms", $0) }.joined(separator: "  "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("traceroute_row_\(hop.hopNumber)")
    }

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView().scaleEffect(0.7)
                Text("Tracing route to \(host)...").foregroundStyle(.secondary)
            } else if !hops.isEmpty {
                let successfulHops = hops.filter { !$0.isTimeout }.count
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(successfulHops)/\(hops.count) hops completed").foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Trace failed").foregroundStyle(.secondary)
            } else {
                Text("Trace the path to any host").foregroundStyle(.secondary)
            }

            Spacer()

            if !hops.isEmpty && !isRunning {
                Button("Clear") {
                    hops.removeAll()
                    errorMessage = nil
                }
                .accessibilityIdentifier("traceroute_button_clear")
            }
        }
        .padding()
    }

    private func runTraceroute() {
        guard !host.isEmpty else { return }
        lastUsedTarget = host
        isRunning = true
        hops.removeAll()
        errorMessage = nil

        tracerouteTask = Task {
            let stream = await service.trace(
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                maxHops: maxHops
            )
            for await hop in stream {
                guard !Task.isCancelled else { break }
                hops.append(hop)
            }
            isRunning = false
        }
    }

    private func stopTraceroute() {
        tracerouteTask?.cancel()
        tracerouteTask = nil
        Task { await service.stop() }
        isRunning = false
    }
}

#Preview { TracerouteToolView() }
