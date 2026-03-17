import SwiftUI
import NetMonitorCore
import SwiftData

struct DeviceDetailView: View {
    let ipAddress: String
    @State private var viewModel = DeviceDetailViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let device = viewModel.device {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    headerSection(device)
                    networkInfoSection(device)
                    servicesAndPortsSection(device)
                    statusSection(device)
                    quickActionsSection(device)
                    notesSection(device)
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            } else if viewModel.isLoading {
                ProgressView()
                    .tint(Theme.Colors.accent)
                    .accessibilityIdentifier("deviceDetail_progress_loading")
            } else {
                ContentUnavailableView(
                    "Device Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("No device found at \(ipAddress)")
                )
                .accessibilityIdentifier("deviceDetail_label_notFound")
            }
        }
        .themedBackground()
        .navigationTitle(viewModel.device?.displayName ?? ipAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task<Void, Never> {
                            await viewModel.scanPorts()
                        }
                    } label: {
                        Label(viewModel.isScanning ? "Scanning Ports..." : "Scan Ports", systemImage: "network")
                    }
                    .disabled(viewModel.isScanning)
                    .accessibilityIdentifier("deviceDetail_menu_scanPorts")

                    Button {
                        Task<Void, Never> {
                            await viewModel.discoverServices()
                        }
                    } label: {
                        Label(viewModel.isDiscovering ? "Discovering..." : "Discover Services", systemImage: "bonjour")
                    }
                    .disabled(viewModel.isDiscovering)
                    .accessibilityIdentifier("deviceDetail_menu_discoverServices")
                } label: {
                    if viewModel.isScanning || viewModel.isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.Colors.accent)
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                .accessibilityIdentifier("deviceDetail_button_actions")
            }
        }
        .task(id: ipAddress) {
            viewModel.loadDevice(ipAddress: ipAddress, context: modelContext)
            guard !Task.isCancelled else { return }
            await viewModel.enrichDevice(bonjourServices: [])
        }
        .accessibilityIdentifier("screen_deviceDetail")
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(_ device: LocalDevice) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: device.deviceType.iconName)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityIdentifier("deviceDetail_icon_deviceType")

            Text(device.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_displayName")

            HStack(spacing: 8) {
                Circle()
                    .fill(device.status.color)
                    .frame(width: 8, height: 8)

                Text(device.status.statusType.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("deviceDetail_label_status")

            if let manufacturer = device.manufacturer {
                Text(manufacturer)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("deviceDetail_label_manufacturer")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Network Info Section

    @ViewBuilder
    private func networkInfoSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Network Information")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_networkInfoTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                infoRow(label: "IP Address", value: device.ipAddress)
                    .accessibilityIdentifier("deviceDetail_row_ipAddress")

                infoRow(label: "MAC Address", value: device.formattedMacAddress)
                    .accessibilityIdentifier("deviceDetail_row_macAddress")

                if let hostname = device.hostname {
                    infoRow(label: "Hostname", value: hostname)
                        .accessibilityIdentifier("deviceDetail_row_hostname")
                }

                if let resolvedHostname = device.resolvedHostname {
                    infoRow(label: "Resolved Name", value: resolvedHostname)
                        .accessibilityIdentifier("deviceDetail_row_resolvedHostname")
                }

                if let manufacturer = device.manufacturer {
                    infoRow(label: "Manufacturer", value: manufacturer)
                        .accessibilityIdentifier("deviceDetail_row_manufacturerInfo")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Services & Ports Section

    @ViewBuilder
    private func servicesAndPortsSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Services & Ports")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_servicesTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                // Open Ports
                if let openPorts = device.openPorts, !openPorts.isEmpty {
                    ForEach(Array(openPorts.enumerated()), id: \.element) { index, port in
                        HStack(spacing: 12) {
                            Image(systemName: "network")
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(wellKnownServiceName(for: port) ?? "Port \(port)")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .font(.subheadline)

                                if wellKnownServiceName(for: port) != nil {
                                    Text("Port \(port)")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .font(.caption)
                                }
                            }

                            Spacer()

                            Text("Open")
                                .foregroundStyle(Theme.Colors.success)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.success.opacity(0.15))
                                .cornerRadius(Theme.Layout.smallCornerRadius)
                        }
                        .accessibilityIdentifier("deviceDetail_row_port_\(port)")

                        if index < openPorts.count - 1 {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                    }
                }

                // Discovered Services
                if let services = device.discoveredServices, !services.isEmpty {
                    if device.openPorts != nil && !device.openPorts!.isEmpty {
                        Divider().background(Theme.Colors.glassBorder)
                    }

                    ForEach(Array(services.enumerated()), id: \.offset) { index, service in
                        HStack(spacing: 12) {
                            Image(systemName: "bonjour")
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 24)

                            Text(service)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .font(.subheadline)

                            Spacer()
                        }
                        .accessibilityIdentifier("deviceDetail_row_service_\(index)")

                        if index != services.count - 1 {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                    }
                }

                // Empty state or action buttons
                if (device.openPorts == nil || device.openPorts!.isEmpty) &&
                   (device.discoveredServices == nil || device.discoveredServices!.isEmpty) {
                    Text("No services or ports discovered yet")
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                // Action buttons
                Divider().background(Theme.Colors.glassBorder)

                HStack(spacing: Theme.Layout.itemSpacing) {
                    Button {
                        Task {
                            await viewModel.scanPorts()
                        }
                    } label: {
                        HStack {
                            if viewModel.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Theme.Colors.accent)
                            } else {
                                Image(systemName: "network")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                            Text(viewModel.isScanning ? "Scanning..." : "Scan Ports")
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.glassBackground)
                        .cornerRadius(Theme.Layout.buttonCornerRadius)
                    }
                    .disabled(viewModel.isScanning)
                    .accessibilityIdentifier("deviceDetail_button_scanPorts")

                    Button {
                        Task {
                            await viewModel.discoverServices()
                        }
                    } label: {
                        HStack {
                            if viewModel.isDiscovering {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Theme.Colors.accent)
                            } else {
                                Image(systemName: "bonjour")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                            Text(viewModel.isDiscovering ? "Discovering..." : "Discover Services")
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.glassBackground)
                        .cornerRadius(Theme.Layout.buttonCornerRadius)
                    }
                    .disabled(viewModel.isDiscovering)
                    .accessibilityIdentifier("deviceDetail_button_discoverServices")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("deviceDetail_section_services")
    }

    // MARK: - Status Section

    @ViewBuilder
    private func statusSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_statusTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                if let latency = device.lastLatency {
                    HStack {
                        Text("Latency")
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.Colors.latencyColor(ms: latency))
                                .frame(width: 8, height: 8)

                            Text(device.latencyText ?? "")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .accessibilityIdentifier("deviceDetail_row_latency")
                }

                infoRow(label: "First Seen", value: device.firstSeen.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityIdentifier("deviceDetail_row_firstSeen")

                infoRow(label: "Last Seen", value: device.lastSeen.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityIdentifier("deviceDetail_row_lastSeen")

                if device.isGateway {
                    HStack {
                        Text("Gateway")
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.success)
                                .font(.caption)

                            Text("Yes")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .accessibilityIdentifier("deviceDetail_row_gateway")
                }

                if device.supportsWakeOnLan {
                    HStack {
                        Text("Wake-on-LAN")
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.success)
                                .font(.caption)

                            Text("Supported")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .accessibilityIdentifier("deviceDetail_row_wakeOnLan")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Quick Actions Section

    @ViewBuilder
    private func quickActionsSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_quickActionsTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                // Ping button
                NavigationLink(destination: PingToolView(initialHost: device.ipAddress)) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 24)

                        Text("Ping")
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityIdentifier("deviceDetail_button_ping")

                Divider().background(Theme.Colors.glassBorder)

                // Port Scan button
                NavigationLink(destination: PortScannerToolView(initialHost: device.ipAddress)) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 24)

                        Text("Port Scan")
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityIdentifier("deviceDetail_button_portScan")

                Divider().background(Theme.Colors.glassBorder)

                // DNS Lookup button
                NavigationLink(destination: DNSLookupToolView(initialDomain: device.ipAddress)) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 24)

                        Text("DNS Lookup")
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityIdentifier("deviceDetail_button_dnsLookup")

                // Wake-on-LAN button (conditional)
                if device.supportsWakeOnLan {
                    Divider().background(Theme.Colors.glassBorder)

                    NavigationLink(destination: WakeOnLANToolView(initialMacAddress: device.macAddress)) {
                        HStack {
                            Image(systemName: "power")
                                .foregroundStyle(Theme.Colors.success)
                                .frame(width: 24)

                            Text("Wake on LAN")
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .accessibilityIdentifier("deviceDetail_button_wakeOnLan")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Notes Section

    @ViewBuilder
    private func notesSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_notesTitle")

            TextEditor(text: Binding(
                get: { device.notes ?? "" },
                set: { device.notes = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 100)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.Colors.textPrimary)
            .background(Color.clear)
            .overlay(
                Group {
                    if device.notes == nil || device.notes?.isEmpty == true {
                        Text("Add notes about this device...")
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            )
            .accessibilityIdentifier("deviceDetail_textEditor_notes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Text(value)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helper Functions

    private func wellKnownServiceName(for port: Int) -> String? {
        let wellKnownPorts: [Int: String] = [
            22: "SSH", 53: "DNS", 80: "HTTP", 443: "HTTPS",
            21: "FTP", 25: "SMTP", 110: "POP3", 143: "IMAP",
            445: "SMB", 548: "AFP", 631: "IPP", 3389: "RDP",
            5900: "VNC", 8080: "HTTP Proxy", 8443: "HTTPS Alt",
            3000: "Dev Server", 5353: "mDNS", 62078: "iSync"
        ]
        return wellKnownPorts[port]
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceDetailView(ipAddress: "192.168.1.1")
            .modelContainer(for: [LocalDevice.self], inMemory: true)
    }
}
