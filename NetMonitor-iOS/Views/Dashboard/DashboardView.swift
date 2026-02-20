import SwiftUI
import NetMonitorCore

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    ConnectionStatusHeader(viewModel: viewModel)

                    SessionCard(viewModel: viewModel)

                    WiFiCard(viewModel: viewModel)

                    GatewayCard(viewModel: viewModel)

                    ISPCard(viewModel: viewModel)

                    LocalDevicesCard(viewModel: viewModel)
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .accessibilityIdentifier("dashboard_button_settings")
                }
            }
            .refreshable {
                await viewModel.refresh(forceIP: true)
            }
            .task {
                await viewModel.refresh(forceIP: true)
                viewModel.startAutoRefresh()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
        }
        .accessibilityIdentifier("screen_dashboard")
    }
}

struct ConnectionStatusHeader: View {
    let viewModel: DashboardViewModel

    private var isMacConnected: Bool {
        viewModel.macConnectionService.connectionState.isConnected
    }

    private var macName: String? {
        viewModel.macConnectionService.connectedMacName
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if isMacConnected, let name = macName {
                    Text("Connected to \(name)")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                } else {
                    Text("Standalone Mode")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(viewModel.connectionStatusText)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            if isMacConnected {
                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.success)
                    StatusDot(status: .online, size: 8, animated: true)
                }
            } else {
                StatusBadge(status: viewModel.isConnected ? .online : .offline, size: .small)
            }
        }
        .padding(.top, Theme.Layout.smallCornerRadius)
        .accessibilityIdentifier("dashboard_header_connectionStatus")
    }
}

struct SessionCard: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Session")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Started")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(viewModel.sessionStartTimeFormatted)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(viewModel.sessionDuration)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_session")
    }
}

struct WiFiCard: View {
    let viewModel: DashboardViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Image(systemName: viewModel.connectionType.iconName)
                        .foregroundStyle(viewModel.isConnected ? Theme.Colors.success : Theme.Colors.error)
                    Text("Connection")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if viewModel.connectionType == .wifi {
                        Text("WiFi")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.success.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                if let wifi = viewModel.currentWiFi {
                    VStack(spacing: Theme.Layout.smallCornerRadius) {
                        ToolResultRow(label: "Network", value: wifi.ssid, icon: "network")
                        ToolResultRow(label: "Type", value: "WiFi", icon: "wifi")
                        if let bssid = wifi.bssid {
                            ToolResultRow(label: "BSSID", value: bssid, icon: "barcode", isMonospaced: true)
                        }
                        if let dbm = wifi.signalDBm {
                            ToolResultRow(label: "Signal", value: "\(dbm) dBm", icon: "antenna.radiowaves.left.and.right")
                        }
                        if let channel = wifi.channel, let band = wifi.band {
                            ToolResultRow(label: "Channel", value: "\(channel) (\(band.rawValue))", icon: "dot.radiowaves.right")
                        }
                        if let security = wifi.securityType {
                            ToolResultRow(label: "Security", value: security, icon: "lock.shield")
                        }
                    }
                } else if viewModel.needsLocationPermission {
                    locationPermissionView
                } else {
                    noWiFiView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_wifi")
    }
    
    private var locationPermissionView: some View {
        VStack(spacing: Theme.Layout.smallCornerRadius) {
            Text("Location permission required to show WiFi details")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            GlassButton(title: "Grant Permission", icon: "location", size: .small) {
                viewModel.requestLocationPermission()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private var noWiFiView: some View {
        Text("No WiFi information available")
            .font(.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct GatewayCard: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(Theme.Colors.info)
                    Text("Gateway")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if let latencyText = viewModel.gateway?.latencyText,
                       let latencyMs = viewModel.gateway?.latency {
                        let color = Theme.Colors.latencyColor(ms: latencyMs)
                        Text(latencyText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                if let gateway = viewModel.gateway {
                    VStack(spacing: Theme.Layout.smallCornerRadius) {
                        ToolResultRow(label: "IP Address", value: gateway.ipAddress, icon: "number", isMonospaced: true)
                        if let mac = gateway.macAddress {
                            ToolResultRow(label: "MAC Address", value: mac, icon: "barcode", isMonospaced: true)
                        }
                        if let vendor = gateway.vendor {
                            ToolResultRow(label: "Vendor", value: vendor, icon: "building.2")
                        }
                    }
                } else {
                    Text("Detecting gateway...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_gateway")
    }
}

struct ISPCard: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Internet")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    GlassIconButton(icon: "arrow.clockwise", size: 32) {
                        Task {
                            await viewModel.refreshPublicIP()
                        }
                    }
                }
                
                if let isp = viewModel.ispInfo {
                    VStack(spacing: Theme.Layout.smallCornerRadius) {
                        ToolResultRow(label: "Public IP", value: isp.publicIP, icon: "globe", isMonospaced: true)
                        if let ispName = isp.ispName {
                            ToolResultRow(label: "ISP", value: ispName, icon: "building")
                        }
                        if let asn = isp.asn {
                            ToolResultRow(label: "ASN", value: asn, icon: "number", isMonospaced: true)
                        }
                        if let location = isp.locationText {
                            ToolResultRow(label: "Location", value: location, icon: "location")
                        }
                    }
                } else {
                    Text("Fetching public IP...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_isp")
    }
}

struct LocalDevicesCard: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        NavigationLink(destination: DeviceListView(discoveredDevices: viewModel.discoveredDevices)) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Local Devices")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(viewModel.deviceCount) devices")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    // Network selector
                    if viewModel.availableNetworks.count > 1 {
                        HStack {
                            Image(systemName: "network")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Picker("Network", selection: $viewModel.selectedNetworkID) {
                                Text("Auto").tag(String?.none)
                                ForEach(viewModel.availableNetworks) { profile in
                                    Label(profile.displayName, systemImage: profile.connectionType.iconName)
                                        .tag(Optional(profile.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.Colors.accent)
                            .accessibilityIdentifier("dashboard_picker_network")
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Scan")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            if let lastScan = viewModel.lastScanDate {
                                Text(lastScan, style: .relative)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            } else {
                                Text("Never")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }

                        Spacer()

                        if viewModel.isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                        } else {
                            GlassButton(title: "Scan", icon: "magnifyingglass", size: .small) {
                                Task {
                                    await viewModel.startDeviceScan()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            viewModel.refreshAvailableNetworks()
        }
        .accessibilityIdentifier("dashboard_card_localDevices")
    }
}

#Preview {
    DashboardView()
}
