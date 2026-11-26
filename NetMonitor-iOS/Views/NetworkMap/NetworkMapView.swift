import SwiftUI
import SwiftData
import NetMonitorCore
import NetworkScanKit

struct NetworkMapView: View {
    @State private var viewModel: NetworkMapViewModel
    @Environment(DevicePresenceModel.self) private var presenceModel: DevicePresenceModel?
    @State private var sortOrder: DeviceSortOrder = .ip
    @State private var isAddNetworkSheetPresented = false
    /// Saved rows that are one device's interfaces: the map shows that device once (#594).
    @Query(filter: #Predicate<LocalDevice> { $0.deviceGroupID != nil }) private var groupedRows: [LocalDevice]

    init(env: AppEnvironment) {
        _viewModel = State(initialValue: NetworkMapViewModel(
            deviceDiscoveryService: env.deviceDiscovery,
            macConnectionService: env.macConnection,
            reviewPrompt: RateAppService.reviewPrompt
        ))
    }

    private var sortedDevices: [DiscoveredDevice] {
        let devices = viewModel.nodes
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

    private var gatewayDevice: DiscoveredDevice? {
        guard let gatewayIP = viewModel.gateway?.ipAddress else { return nil }
        return viewModel.discoveredDevices.first { $0.ipAddress == gatewayIP }
    }

    var body: some View {
        NavigationStack {
            // The presence model refreshes after each saved scan and every minute (#583).
            mapContent(staleNote: viewModel.notCheckedRecentlyNote(presenceModel?.snapshot ?? DevicePresenceModel.noScans))
        }
        .onChange(of: groupedRows.map(\.id), initial: true) {
            viewModel.groupedRows = groupedRows
        }
    }

    /// The grid's title, node count, the not-checked-recently note (#583) and the sort.
    private func controlBar(staleNote: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SIGNAL GRID")
                    .font(.system(.caption2, weight: .black))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1.5)
                Text(staleNote == nil ? "\(viewModel.deviceCount) active nodes" : "\(viewModel.deviceCount) nodes")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                if let staleNote {
                    HStack(spacing: 4) {
                        PresenceDot(freshness: .notCheckedRecently)
                        Text(staleNote)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("networkMap_label_notCheckedRecently")
                }
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
        .padding(.horizontal, 4)
    }

    private func mapContent(staleNote: String?) -> some View {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    // 1. Network Context Header
                    networkSummary

                    // 2. Control Bar
                    controlBar(staleNote: staleNote)

                    // 4. High-Density Device Grid
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
                                NavigationLink(value: AppDestination.deviceDetail(
                            ipAddress: device.ipAddress, networkID: device.networkProfileID, macAddress: device.macAddress
                        )) {
                                    ProDeviceRow(device: device, isScanning: viewModel.isScanning)
                                }
                                .buttonStyle(PlainButtonStyle())
                                // A cached device gave no answer this scan and may have left (#378);
                                // none is online now when the network wasn't checked recently (#583).
                                .opacity(device.isCached || staleNote != nil ? 0.55 : 1)
                                .accessibilityValue(device.isCached ? "Cached, may have left the network" : "")
                                .accessibilityIdentifier("networkMap_row_\(device.ipAddress)")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .appDestinations()
            .themedBackground()
            .navigationTitle("Network Map")
            .accessibilityIdentifier("screen_networkMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    networksMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    scanButton
                }
            }
            .sheet(isPresented: $isAddNetworkSheetPresented) {
                AddNetworkSheet(
                    discoveredDevices: viewModel.discoveredDevices,
                    gatewayHint: viewModel.activeNetwork?.gatewayIP,
                    onAddNetwork: { gateway, subnet, name in
                        await viewModel.addNetworkProfile(gateway: gateway, subnet: subnet, name: name)
                    }
                )
            }
            .task {
                viewModel.refreshAvailableNetworks()
                await viewModel.startScan(forceRefresh: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkProfilesDidChange)) { _ in
                // The device joined another network: show that network, not the old one.
                viewModel.refreshAvailableNetworks()
            }
    }

    // MARK: - Sub-components

    private var networksMenu: some View {
        Menu {
            ForEach(viewModel.availableNetworks) { network in
                Button {
                    Task { await viewModel.selectNetwork(id: network.id) }
                } label: {
                    if viewModel.activeNetwork?.id == network.id {
                        Label(network.displayName, systemImage: "checkmark")
                    } else {
                        Text(network.displayName)
                    }
                }
                .accessibilityIdentifier("networkMap_menu_selectNetwork\(network.id)")
            }

            Divider()

            Button {
                isAddNetworkSheetPresented = true
            } label: {
                Label("Add Network", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("networkMap_button_addNetwork")
        } label: {
            Label(viewModel.activeNetwork?.displayName ?? "Networks", systemImage: "network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
        }
        .accessibilityIdentifier("networkMap_menu_networks")
    }

    private var networkSummary: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.activeNetwork?.displayName ?? "LOCAL NETWORK")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textStrong)
                        Text(viewModel.gateway?.ipAddress ?? "---.---.---.---")
                            .font(.system(.caption, design: .monospaced))
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

                Divider().background(Theme.Colors.divider)

                HStack {
                    Label("\(viewModel.activeNetworkDeviceCount ?? 0) Devices", systemImage: "cpu")
                    Spacer()
                    Label("Gateway: Reachable", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                }
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("networkMap_label_summary")
    }

    private var scanButton: some View {
        Button {
            Task { await viewModel.startScan(forceRefresh: true) }
        } label: {
            if viewModel.isScanning {
                ProgressView().tint(Theme.Colors.textStrong)
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
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.divider, lineWidth: 1))

                    Image(systemName: device.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.textStrong)
                    Text(device.ipAddress)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(device.latencyText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(device.isCached ? Theme.Colors.textTertiary : Theme.Colors.success)

                    Text(device.source == .local ? "DIRECT" : "PEER")
                        .font(.system(.caption2, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.divider)
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
    let env = AppEnvironment.live()
    NetworkMapView(env: env)
        .environment(env)
}
