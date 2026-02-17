import SwiftUI
import NetMonitorCore
import NetworkScanKit

struct NetworkMapView: View {
    @State private var viewModel = NetworkMapViewModel()
    @State private var sortOrder: DeviceSortOrder = .ip

    private var sortedDevices: [DiscoveredDevice] {
        let devices = viewModel.discoveredDevices
        switch sortOrder {
        case .ip:
            return devices.sorted { $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey }
        case .name:
            return devices.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .latency:
            return devices.sorted { ($0.latency ?? 9999) < ($1.latency ?? 9999) }
        case .source:
            return devices.sorted {
                if $0.source == $1.source {
                    return $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey
                }
                return $0.source == .local
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    // Network summary header
                    networkSummary

                    // Sort + count bar
                    sortBar

                    // Device list
                    if viewModel.discoveredDevices.isEmpty && !viewModel.isScanning {
                        ContentUnavailableView(
                            "No Devices Found",
                            systemImage: "network.slash",
                            description: Text("Tap Scan to discover devices on your network")
                        )
                        .padding(.top, 40)
                        .accessibilityIdentifier("networkMap_label_empty")
                    } else {
                        deviceList
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    scanButton
                }
            }
            .task {
                await viewModel.startScan(forceRefresh: false)
            }
        }
        .accessibilityIdentifier("screen_networkMap")
    }

    // MARK: - Network Summary

    private var networkSummary: some View {
        GlassCard {
            HStack(spacing: 16) {
                // Gateway info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.router")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Gateway")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(viewModel.gateway?.ipAddress ?? "Detecting…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                // Mac companion status
                if viewModel.macConnectionService.connectionState.isConnected {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(Theme.Colors.success)
                            Text("Mac Paired")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(viewModel.macConnectionService.connectedMacName ?? "Connected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.success)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "iphone")
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("Standalone")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text("iOS only")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("networkMap_summary")
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack {
            if viewModel.isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                        .scaleEffect(0.7)
                    Text(viewModel.scanPhaseText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text("\(viewModel.deviceCount) devices")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Picker("Sort", selection: $sortOrder) {
                ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.accent)
            .accessibilityIdentifier("networkMap_picker_sort")
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            ForEach(sortedDevices) { device in
                NavigationLink(destination: DeviceDetailView(ipAddress: device.ipAddress)) {
                    deviceRow(device: device)
                }
                .accessibilityIdentifier("networkMap_row_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))")
            }
        }
    }

    @ViewBuilder
    private func deviceRow(device: DiscoveredDevice) -> some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: iconForDevice(device))
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    HStack(spacing: 8) {
                        if device.hostname != nil {
                            Text(device.ipAddress)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        Text(device.latencyText)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if let vendor = device.vendor, !vendor.isEmpty {
                        Text(vendor)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconForDevice(_ device: DiscoveredDevice) -> String {
        if device.source == .macCompanion {
            return "desktopcomputer.and.arrow.down"
        }
        // Try to guess device type from hostname
        let name = (device.hostname ?? "").lowercased()
        if name.contains("iphone") || name.contains("ipad") { return "iphone" }
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("mac") || name.contains("imac") { return "desktopcomputer" }
        if name.contains("apple-tv") || name.contains("appletv") { return "appletv" }
        if name.contains("printer") || name.contains("hp") || name.contains("epson") { return "printer" }
        return "desktopcomputer"
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            Task {
                await viewModel.startScan(forceRefresh: true)
            }
        } label: {
            if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.textPrimary))
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .accessibilityIdentifier("networkMap_button_scan")
    }
}

#Preview {
    NetworkMapView()
}
