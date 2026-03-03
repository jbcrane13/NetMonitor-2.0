//
//  NetworkIntelCard.swift
//  NetMonitor
//
//  Live network intelligence summary for IT professionals.
//

import SwiftUI
import NetMonitorCore

/// Compact network intelligence card — active connections, listeners, DNS health, events.
struct NetworkIntelCard: View {
    @State private var activeConnections: Int = 0
    @State private var listeningPorts: Int = 0
    @State private var establishedCount: Int = 0
    @State private var timeWaitCount: Int = 0
    @State private var dnsLatencyMs: Double?
    @State private var dnsResolver: String = "—"
    @State private var recentEvents: [NetEvent] = []
    @State private var isLoading = true

    struct NetEvent: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let time: String
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("NETWORK INTEL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if !isLoading {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MacTheme.Colors.success)
                        .tracking(1.2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.Colors.success.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            if isLoading {
                HStack { Spacer()
                ProgressView().controlSize(.small)
                Spacer()
                }
            } else {
                // Connection stats grid
                HStack(spacing: 0) {
                    statTile(value: "\(activeConnections)", label: "ACTIVE", color: MacTheme.Colors.info)
                    Divider().frame(height: 28).opacity(0.2)
                    statTile(value: "\(establishedCount)", label: "ESTABLISHED", color: MacTheme.Colors.success)
                    Divider().frame(height: 28).opacity(0.2)
                    statTile(value: "\(listeningPorts)", label: "LISTENING", color: MacTheme.Colors.warning)
                    Divider().frame(height: 28).opacity(0.2)
                    statTile(value: "\(timeWaitCount)", label: "TIME_WAIT", color: .secondary)
                }
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))

                // DNS resolver health
                HStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(dnsHealthColor)
                    Text("DNS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Text(dnsResolver)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let ms = dnsLatencyMs {
                        Text(String(format: "%.0fms", ms))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(dnsHealthColor)
                    }
                }

                // Recent events feed
                if !recentEvents.isEmpty {
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(recentEvents.prefix(3)) { event in
                            HStack(spacing: 6) {
                                Image(systemName: event.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(event.color)
                                    .frame(width: 12)
                                Text(event.text)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(event.time)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_networkIntel")
        .task { await refresh() }
    }

    // MARK: - Sub-views

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var dnsHealthColor: Color {
        guard let ms = dnsLatencyMs else { return .secondary }
        if ms < 20 { return MacTheme.Colors.success }
        if ms < 50 { return MacTheme.Colors.info }
        if ms < 100 { return MacTheme.Colors.warning }
        return MacTheme.Colors.error
    }

    // MARK: - Data

    private func refresh() async {
        // Parse netstat for connection states
        await parseNetstat()

        // Get DNS resolver + measure latency
        await measureDNS()

        // Generate initial events
        recentEvents = generateEvents()
        isLoading = false

        // Refresh every 10 seconds
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            await parseNetstat()
            await measureDNS()
            recentEvents = generateEvents()
        }
    }

    private func parseNetstat() async {
        do {
            let runner = ShellCommandRunner()
            let result = try await runner.run("/usr/sbin/netstat", arguments: ["-n", "-p", "tcp"], timeout: 5)
            let lines = result.stdout.components(separatedBy: .newlines)

            var established = 0, listening = 0, timeWait = 0, total = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("ESTABLISHED") { established += 1
                total += 1
                }
                else if trimmed.contains("LISTEN") { listening += 1
                total += 1
                }
                else if trimmed.contains("TIME_WAIT") { timeWait += 1
                total += 1
                }
                else if trimmed.contains("CLOSE_WAIT") || trimmed.contains("SYN_SENT") ||
                        trimmed.contains("SYN_RECEIVED") || trimmed.contains("FIN_WAIT") {
                    total += 1
                }
            }

            activeConnections = total
            establishedCount = established
            listeningPorts = listening
            timeWaitCount = timeWait
        } catch {
            // Silently fail — card shows stale data
        }
    }

    private func measureDNS() async {
        // Read system DNS resolver
        if let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            let lines = contents.components(separatedBy: .newlines)
            if let nameserver = lines.first(where: { $0.hasPrefix("nameserver") }) {
                dnsResolver = nameserver.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Measure DNS lookup latency
        let start = ContinuousClock.now
        let host = CFHostCreateWithName(nil, "apple.com" as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(host, .addresses, nil)
        _ = CFHostGetAddressing(host, &resolved)
        let elapsed = ContinuousClock.now - start
        dnsLatencyMs = Double(elapsed.components.attoseconds) / 1e15
    }

    private func generateEvents() -> [NetEvent] {
        // Build events from real system state
        var events: [NetEvent] = []

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let now = formatter.string(from: Date())

        if establishedCount > 50 {
            events.append(NetEvent(icon: "exclamationmark.triangle", text: "\(establishedCount) active connections — high load", time: now, color: MacTheme.Colors.warning))
        }

        if timeWaitCount > 20 {
            events.append(NetEvent(icon: "clock.arrow.circlepath", text: "\(timeWaitCount) connections in TIME_WAIT", time: now, color: .secondary))
        }

        if let ms = dnsLatencyMs, ms > 50 {
            events.append(NetEvent(icon: "exclamationmark.circle", text: "DNS latency elevated: \(Int(ms))ms", time: now, color: MacTheme.Colors.warning))
        }

        if events.isEmpty {
            events.append(NetEvent(icon: "checkmark.shield", text: "All systems nominal", time: now, color: MacTheme.Colors.success))
        }

        return events
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NetworkIntelCard()
        .frame(width: 400)
}
#endif
