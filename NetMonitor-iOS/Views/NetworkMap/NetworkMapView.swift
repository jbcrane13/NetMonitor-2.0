import SwiftUI
import NetMonitorCore
import NetworkScanKit

struct NetworkMapView: View {
    @State private var viewModel = NetworkMapViewModel()
    @State private var sortOrder: DeviceSortOrder = .ip
    // periphery:ignore
    @State private var isAddNetworkSheetPresented = false

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
                    // 1. Network Context Header
                    networkSummary

                    // 2. Control Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SIGNAL GRID")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1.5)
                            Text("\(viewModel.deviceCount) active nodes")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        
                        Spacer()
                        
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.accent)
                    }
                    .padding(.horizontal, 4)

                    // 3. High-Density Device Grid
                    if sortedDevices.isEmpty && !viewModel.isScanning {
                        ContentUnavailableView(
                            "No Nodes Active",
                            systemImage: "network.slash",
                            description: Text("Scan to map the current network landscape.")
                        )
                        .padding(.top, 40)
                        .accessibilityIdentifier("networkMap_label_empty")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sortedDevices) { device in
                                NavigationLink(destination: DeviceDetailView(ipAddress: device.ipAddress)) {
                                    ProDeviceRow(device: device, isScanning: viewModel.isScanning)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityIdentifier("networkMap_row_\(device.ipAddress)")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Network Map")
            .accessibilityIdentifier("screen_networkMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    scanButton
                }
            }
            .task {
                viewModel.refreshAvailableNetworks()
                await viewModel.startScan(forceRefresh: false)
            }
        }
    }

    // MARK: - Sub-components

    private var networkSummary: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.activeNetwork?.displayName ?? "LOCAL NETWORK")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(viewModel.gateway?.ipAddress ?? "---.---.---.---")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accent.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "wifi.router.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                
                Divider().background(Color.white.opacity(0.05))
                
                HStack {
                    Label("\(viewModel.activeNetworkDeviceCount ?? 0) Devices", systemImage: "cpu")
                    Spacer()
                    Label("Gateway: Reachable", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("networkMap_summary")
    }

    private var scanButton: some View {
        Button {
            Task { await viewModel.startScan(forceRefresh: true) }
        } label: {
            if viewModel.isScanning {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .accessibilityIdentifier("networkMap_button_scan")
    }
}

struct ProDeviceRow: View {
    let device: DiscoveredDevice
    let isScanning: Bool
    @State private var sweepOffset: CGFloat = -1.0
    
    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.crystalBase)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    
                    Image(systemName: device.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(device.ipAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(device.latencyText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.success)
                    
                    Text(device.source == .local ? "DIRECT" : "PEER")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.05))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .overlay(
                // Scanner Sweep Effect
                GeometryReader { geo in
                    if isScanning {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Theme.Colors.accent.opacity(0.1), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 60)
                            .offset(x: geo.size.width * sweepOffset)
                    }
                }
            )
        }
        .onAppear {
            if isScanning {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    sweepOffset = 1.5
                }
            }
        }
    }
}

#Preview {
    NetworkMapView()
}
