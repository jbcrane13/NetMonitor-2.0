//
//  PortScannerToolView.swift
//  NetMonitor
//
//  Port scanner tool using Network.framework NWConnection.
//

import SwiftUI
import NetMonitorCore
import Network

/// Common port presets
enum PortPreset: String, CaseIterable {
    case common = "Common"
    case web = "Web"
    case custom = "Custom"

    var ports: [UInt16] {
        switch self {
        case .common:
            return [21, 22, 23, 25, 53, 80, 110, 143, 443, 465, 587, 993, 995, 3306, 3389, 5432, 5900, 8080, 8443]
        case .web:
            return [80, 443, 8080, 8443, 3000, 3001, 4000, 5000, 8000, 9000]
        case .custom:
            return []
        }
    }
}

struct PortScannerToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var host = ""
    @State private var preset: PortPreset = .common
    @State private var customPorts = ""
    @State private var isRunning = false
    @State private var results: [PortResult] = []
    @State private var scannedCount = 0
    @State private var totalPorts = 0
    @State private var errorMessage: String?
    @AppStorage("netmonitor.lastUsedTarget") private var lastUsedTarget: String = ""

    var body: some View {
        ToolSheetContainer(
            title: "Port Scanner",
            iconName: "network",
            closeAccessibilityID: "portScan_button_close",
            minWidth: 600,
            minHeight: 500,
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
            scanTask?.cancel()
            scanTask = nil
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Hostname or IP address", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
                    .accessibilityIdentifier("portScan_textfield_host")

                Picker("Preset", selection: $preset) {
                    ForEach(PortPreset.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .frame(width: 120)
                .disabled(isRunning)
                .accessibilityIdentifier("portScan_picker_preset")

                Button(isRunning ? "Stop" : "Scan") {
                    if isRunning {
                        stopScan()
                    } else {
                        runScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty && !isRunning)
                .accessibilityIdentifier("portScan_button_scan")
            }

            if preset == .custom {
                TextField("Custom ports (e.g., 22,80,443,8080 or 1-1024)", text: $customPorts)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
                    .accessibilityIdentifier("portScan_textfield_custom")
            }
        }
        .padding()
    }

    // MARK: - Output Area

    private var outputArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if results.isEmpty && errorMessage == nil && !isRunning {
                    Text("Enter a hostname and select ports to scan")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    // Show open ports first
                    let openPorts = results.filter { $0.isOpen }
                    let closedPorts = results.filter { !$0.isOpen }

                    if !openPorts.isEmpty {
                        Text("Open Ports")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .padding(.bottom, 4)
                            .accessibilityIdentifier("portScan_label_openPorts")

                        ForEach(openPorts) { result in
                            portRow(result)
                        }

                        Divider()
                            .padding(.vertical, 8)
                    }

                    if !closedPorts.isEmpty && !isRunning {
                        Text("Closed/Filtered Ports")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        ForEach(closedPorts) { result in
                            portRow(result)
                        }
                    }

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
        .background(Color.black.opacity(0.2))
    }

    private func portRow(_ result: PortResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.isOpen ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(result.isOpen ? .green : .secondary)

            Text(String(format: "%5d", result.port))
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            Text(result.serviceName)
                .foregroundStyle(.secondary)

            Spacer()

            if result.isOpen {
                Text(String(format: "%.0f ms", result.latency * 1000))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("portScan_row_\(result.port)")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning \(scannedCount)/\(totalPorts) ports...")
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(scannedCount), total: Double(max(totalPorts, 1)))
                    .frame(width: 100)
            } else if !results.isEmpty {
                let openCount = results.filter { $0.isOpen }.count
                Image(systemName: openCount > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(openCount > 0 ? .green : .secondary)
                Text("\(openCount) open port(s) found")
                    .foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Scan failed")
                    .foregroundStyle(.secondary)
            } else {
                Text("Scan TCP ports on any host")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !results.isEmpty && !isRunning {
                Button("Clear") {
                    results.removeAll()
                    errorMessage = nil
                    scannedCount = 0
                }
                .accessibilityIdentifier("portScan_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    @State private var scanTask: Task<Void, Never>?

    private func runScan() {
        guard !host.isEmpty else { return }

        lastUsedTarget = host
        let portsToScan = getPortsToScan()
        guard !portsToScan.isEmpty else {
            errorMessage = "No valid ports specified"
            return
        }

        isRunning = true
        results.removeAll()
        errorMessage = nil
        scannedCount = 0
        totalPorts = portsToScan.count

        scanTask = Task {
            await scanPorts(host: host, ports: portsToScan)
            isRunning = false
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isRunning = false
    }

    private func getPortsToScan() -> [UInt16] {
        if preset == .custom {
            return parseCustomPorts(customPorts)
        }
        return preset.ports
    }

    private func parseCustomPorts(_ input: String) -> [UInt16] {
        var ports: Set<UInt16> = []

        let components = input.components(separatedBy: ",")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("-") {
                // Range: "1-1024"
                let rangeParts = trimmed.split(separator: "-")
                if rangeParts.count == 2,
                   let start = UInt16(rangeParts[0]),
                   let end = UInt16(rangeParts[1]),
                   start <= end {
                    for port in start...min(end, 65535) {
                        ports.insert(port)
                    }
                }
            } else if let port = UInt16(trimmed) {
                ports.insert(port)
            }
        }

        return Array(ports).sorted()
    }

    private func scanPorts(host: String, ports: [UInt16]) async {
        // Scan in batches of 50 concurrent connections
        let batchSize = 50

        for batch in stride(from: 0, to: ports.count, by: batchSize) {
            guard isRunning else { break }

            let end = min(batch + batchSize, ports.count)
            let batchPorts = Array(ports[batch..<end])

            await withTaskGroup(of: PortResult?.self) { group in
                for port in batchPorts {
                    group.addTask {
                        await self.checkPort(host: host, port: port)
                    }
                }

                for await result in group {
                    guard isRunning else { break }

                    await MainActor.run {
                        scannedCount += 1
                        if let result = result {
                            // Insert in sorted order
                            let insertIndex = results.firstIndex { $0.port > result.port } ?? results.count
                            results.insert(result, at: insertIndex)
                        }
                    }
                }
            }
        }
    }

    private func checkPort(host: String, port: UInt16) async -> PortResult? {
        let startTime = Date()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return PortResult(port: port, isOpen: false, latency: 0, serviceName: Self.serviceName(for: port))
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withCheckedContinuation { continuation in
            let tracker = ContinuationTracker()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    if tracker.tryResume() {
                        let latency = Date().timeIntervalSince(startTime)
                        continuation.resume(returning: PortResult(
                            port: port,
                            isOpen: true,
                            latency: latency,
                            serviceName: Self.serviceName(for: port)
                        ))
                    }

                case .failed, .cancelled:
                    if tracker.tryResume() {
                        continuation.resume(returning: PortResult(
                            port: port,
                            isOpen: false,
                            latency: 0,
                            serviceName: Self.serviceName(for: port)
                        ))
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout after 2 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if tracker.tryResume() {
                    connection.cancel()
                    continuation.resume(returning: PortResult(
                        port: port,
                        isOpen: false,
                        latency: 0,
                        serviceName: Self.serviceName(for: port)
                    ))
                }
            }
        }
    }

    nonisolated private static func serviceName(for port: UInt16) -> String {
        switch port {
        case 21: return "FTP"
        case 22: return "SSH"
        case 23: return "Telnet"
        case 25: return "SMTP"
        case 53: return "DNS"
        case 80: return "HTTP"
        case 110: return "POP3"
        case 143: return "IMAP"
        case 443: return "HTTPS"
        case 465: return "SMTPS"
        case 587: return "Submission"
        case 993: return "IMAPS"
        case 995: return "POP3S"
        case 3000: return "Dev Server"
        case 3306: return "MySQL"
        case 3389: return "RDP"
        case 5432: return "PostgreSQL"
        case 5900: return "VNC"
        case 8080: return "HTTP Alt"
        case 8443: return "HTTPS Alt"
        default: return "Unknown"
        }
    }
}

// MARK: - Models

struct PortResult: Identifiable {
    let id = UUID()
    let port: UInt16
    let isOpen: Bool
    let latency: TimeInterval
    let serviceName: String
}

#Preview {
    PortScannerToolView()
}
