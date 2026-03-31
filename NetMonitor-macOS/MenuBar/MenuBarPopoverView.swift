//
//  MenuBarPopoverView.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import SwiftUI
import NetMonitorCore
import SwiftData

struct MenuBarPopoverView: View {
    @Bindable var session: MonitoringSession
    var deviceDiscovery: DeviceDiscoveryCoordinator
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Connection status + quick stats
            connectionStatus

            Divider()

            // Device count + gateway latency
            networkStats

            Divider()

            // Mini latency graph
            latencySparkline

            Divider()

            // Quick action buttons
            quickActions

            Divider()

            // Problem devices (offline / high latency)
            problemDevicesSection

            if !problemDevices.isEmpty {
                Divider()
            }

            // Target status list
            targetList

            Divider()

            // Footer actions
            footer
        }
        .frame(width: 320)
        .accessibilityIdentifier("screen_menubar")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NetMonitor")
                    .font(.headline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(session.isMonitoring ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(session.isMonitoring ? "Monitoring" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Start/Stop button
            Button {
                if session.isMonitoring {
                    session.stopMonitoring()
                } else {
                    session.startMonitoring()
                }
            } label: {
                Image(systemName: session.isMonitoring ? "stop.fill" : "play.fill")
                    .foregroundStyle(session.isMonitoring ? .red : .green)
            }
            .buttonStyle(.borderless)
            .help(session.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
            .accessibilityIdentifier("menubar_button_monitoringToggle")
        }
        .padding()
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack(spacing: 12) {
            let profile = deviceDiscovery.networkProfile
            let connectionType = profile?.connectionType ?? .none
            let isOnline = profile != nil

            // Connection type icon + label
            HStack(spacing: 6) {
                Image(systemName: isOnline ? connectionType.iconName : "wifi.slash")
                    .foregroundStyle(isOnline ? .green : .red)
                    .font(.system(size: 14, weight: .medium))

                VStack(alignment: .leading, spacing: 1) {
                    Text(isOnline ? connectionType.displayName : "No Connection")
                        .font(.caption)
                        .fontWeight(.medium)

                    if let ssid = profile?.name, !ssid.isEmpty, connectionType == .wifi {
                        Text(ssid)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let gw = profile?.gatewayIP, !gw.isEmpty {
                        Text("Gateway: \(gw)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Online/Offline badge
            Text(isOnline ? "Online" : "Offline")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOnline ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .foregroundStyle(isOnline ? .green : .red)
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityIdentifier("menubar_label_connectionStatus")
    }

    // MARK: - Network Stats

    private var networkStats: some View {
        HStack(spacing: 0) {
            // Device count
            networkStatItem(
                value: deviceCountString,
                label: "Devices Online",
                systemImage: "desktopcomputer",
                color: .blue,
                isLoading: deviceDiscovery.isScanning
            )
            .accessibilityIdentifier("menubar_label_devices")

            Divider()
                .frame(height: 36)

            // Gateway latency
            networkStatItem(
                value: gatewayLatencyString,
                label: "Gateway",
                systemImage: "bolt.fill",
                color: gatewayLatencyColor,
                isLoading: false
            )
            .accessibilityIdentifier("menubar_label_gatewayLatency")

            Divider()
                .frame(height: 36)

            // Avg target latency
            networkStatItem(
                value: averageLatencyString,
                label: "Avg Latency",
                systemImage: "waveform",
                color: .purple,
                isLoading: false
            )
            .accessibilityIdentifier("menubar_label_latency")
        }
        .padding(.vertical, 10)
    }

    private func networkStatItem(
        value: String,
        label: String,
        systemImage: String,
        color: Color,
        isLoading: Bool
    ) -> some View {
        VStack(spacing: 3) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 18)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 9))
                        .foregroundStyle(color)
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Latency Sparkline

    /// Mini latency graph for the gateway / primary target
    private var latencySparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GATEWAY LATENCY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if gatewayLatencyHistory.count > 1 {
                MiniSparklineView(
                    data: gatewayLatencyHistory,
                    lineWidth: 1.2,
                    showPulse: true,
                    height: 32,
                    cornerRadius: 6,
                    thresholdColor: { MacTheme.Colors.latencyColor(ms: $0) }
                )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 32)
                    .overlay(
                        Text("Collecting data…")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityIdentifier("menubar_label_latencySparkline")
    }

    /// Gateway latency history from monitoring session
    private var gatewayLatencyHistory: [Double] {
        guard let gatewayIP = deviceDiscovery.networkProfile?.gatewayIP,
              !gatewayIP.isEmpty else { return [] }

        // Find the target ID that matches gateway IP
        for (id, history) in session.recentLatencies {
            if let measurement = session.latestResults[id],
               measurement.target?.host == gatewayIP,
               !history.isEmpty {
                return history
            }
        }

        // Fall back to any target with latency data
        for (_, history) in session.recentLatencies where !history.isEmpty {
            return history
        }
        return []
    }

    // MARK: - Problem Devices

    /// Devices that are offline or have high latency — surfaced prominently
    private var problemDevices: [LocalDevice] {
        deviceDiscovery.discoveredDevices.filter { device in
            device.status == .offline ||
            (device.lastLatency ?? 0) > 100
        }
        .prefix(3)
        .map { $0 }
    }

    @ViewBuilder
    private var problemDevicesSection: some View {
        if !problemDevices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.Colors.warning)
                    Text("ATTENTION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MacTheme.Colors.warning)
                        .tracking(0.5)
                }

                ForEach(problemDevices, id: \.id) { device in
                    HStack(spacing: 6) {
                        Image(systemName: device.deviceType.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(device.status == .offline ? .red : MacTheme.Colors.warning)
                            .frame(width: 14)

                        Text(device.displayName)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        if device.status == .offline {
                            Text("Offline")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.red)
                        } else if let latency = device.lastLatency {
                            Text("\(Int(latency))ms")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.warning)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar_label_problemDevices")
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 0) {
            popoverQuickAction(
                title: "Scan",
                systemImage: "antenna.radiowaves.left.and.right",
                color: .blue
            ) {
                guard !deviceDiscovery.isScanning else { return }
                deviceDiscovery.startScan()
            }
            .disabled(deviceDiscovery.isScanning)
            .accessibilityIdentifier("menubar_button_scan")

            Divider().frame(height: 28)

            popoverQuickAction(
                title: "Ping",
                systemImage: "waveform.path",
                color: .green
            ) {
                WindowOpener.shared.openMainWindow()
                onClose()
            }
            .accessibilityIdentifier("menubar_button_ping")

            Divider().frame(height: 28)

            popoverQuickAction(
                title: "Speed",
                systemImage: "speedometer",
                color: .purple
            ) {
                WindowOpener.shared.openMainWindow()
                onClose()
            }
            .accessibilityIdentifier("menubar_button_speed")
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("menubar_section_quickActions")
    }

    private func popoverQuickAction(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Target List

    /// Sorted measurement entries for stable display order (by target name, then host)
    private var sortedEntries: [(id: UUID, measurement: TargetMeasurement)] {
        session.latestResults
            .sorted { lhs, rhs in
                let lName = lhs.value.target?.name ?? lhs.value.target?.host ?? ""
                let rName = rhs.value.target?.name ?? rhs.value.target?.host ?? ""
                return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
            }
            .prefix(5)
            .map { (id: $0.key, measurement: $0.value) }
    }

    private var targetList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedEntries, id: \.id) { entry in
                    targetRow(measurement: entry.measurement)
                        .accessibilityIdentifier("menubar_row_\(entry.id)")
                }

                if session.latestResults.isEmpty {
                    Text("No targets configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding()
                }
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: 140)
    }

    /// Display name for a measurement: prefer target name, fall back to host
    private func displayName(for measurement: TargetMeasurement) -> String {
        if let name = measurement.target?.name, !name.isEmpty {
            return name
        }
        if let host = measurement.target?.host, !host.isEmpty {
            return host
        }
        return "Unknown"
    }

    private func targetRow(measurement: TargetMeasurement) -> some View {
        HStack {
            Circle()
                .fill(measurement.isReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(displayName(for: measurement))
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if measurement.isReachable, let latency = measurement.latency {
                Text("\(Int(latency))ms")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            } else {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open NetMonitor") {
                WindowOpener.shared.openMainWindow()
                onClose()
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("menubar_button_openApp")

            Spacer()

            Button {
                guard !deviceDiscovery.isScanning else { return }
                deviceDiscovery.startScan()
            } label: {
                HStack(spacing: 4) {
                    if deviceDiscovery.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    Text(deviceDiscovery.isScanning ? "Scanning…" : "Quick Scan")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .disabled(deviceDiscovery.isScanning)
            .accessibilityIdentifier("menubar_button_quickScan")
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var onlineTargetCount: Int { session.onlineTargetCount }
    private var offlineTargetCount: Int { session.offlineTargetCount }
    private var averageLatencyString: String { session.averageLatencyString }

    /// Number of online devices discovered by the scanner
    private var deviceCountString: String {
        let total = deviceDiscovery.discoveredDevices.count
        if total == 0 { return "—" }
        let online = deviceDiscovery.discoveredDevices.filter { $0.status == .online }.count
        return "\(online)/\(total)"
    }

    /// Gateway latency from the latest monitoring measurement for the gateway IP,
    /// falling back to "—" when not available.
    private var gatewayLatencyString: String {
        guard let gatewayIP = deviceDiscovery.networkProfile?.gatewayIP,
              !gatewayIP.isEmpty else { return "—" }

        // Look for a target measurement whose host matches the gateway IP
        if let measurement = session.latestResults.values.first(where: {
            $0.target?.host == gatewayIP
        }), measurement.isReachable, let latency = measurement.latency {
            return "\(Int(latency))ms"
        }

        // Fallback: use the lowest latency online target as a proxy
        if let best = session.latestResults.values
            .filter({ $0.isReachable })
            .compactMap({ m -> (Double, TargetMeasurement)? in
                guard let l = m.latency else { return nil }
                return (l, m)
            })
            .min(by: { $0.0 < $1.0 }) {
            return "\(Int(best.0))ms"
        }

        return "—"
    }

    private var gatewayLatencyColor: Color {
        guard let str = Double(gatewayLatencyString.replacingOccurrences(of: "ms", with: "")) else {
            return .secondary
        }
        if str < 10 { return .green }
        if str < 50 { return .yellow }
        return .red
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(
        for: NetworkTarget.self, TargetMeasurement.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let httpService = HTTPMonitorService()
    let icmpService = ICMPMonitorService()
    let tcpService = TCPMonitorService()
    let session = MonitoringSession(
        modelContext: context,
        httpService: httpService,
        icmpService: icmpService,
        tcpService: tcpService
    )
    let profileManager = NetworkProfileManager()
    let discovery = DeviceDiscoveryCoordinator(
        modelContext: context,
        arpScanner: ARPScannerService(),
        bonjourScanner: BonjourDiscoveryService(),
        networkProfileManager: profileManager
    )

    return MenuBarPopoverView(session: session, deviceDiscovery: discovery, onClose: {})
}
