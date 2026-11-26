import SwiftUI
import NetMonitorCore
import SwiftData

struct DeviceDetailView: View {
    /// How detail finds its saved row.
    enum Entry: Hashable {
        /// A scan's list entry: the row the device match finds for this address on `networkID`
        /// (nil when opened without one); `macAddress` is the MAC the list showed, which matters
        /// for a cached result the live scan lacks.
        case scanned(ipAddress: String, networkID: UUID?, macAddress: String?)
        /// A link that carries `LocalDevice.id` (#584), or a device's own ID from a list (a group's,
        /// #594): that device, whatever device has its IP now.
        case saved(id: UUID)
    }

    let entry: Entry
    @State private var viewModel = DeviceDetailViewModel()
    @State private var showsLabelCapture = false
    /// The member "Remove this interface" asked about, while its confirmation is up (#594).
    @State private var removingInterface: LocalDevice?
    /// Whether "Same device as…"'s picker is up (#594 PR2).
    @State private var showsSameDeviceAs = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DevicePresenceModel.self) private var presenceModel: DevicePresenceModel?

    init(ipAddress: String, networkID: UUID? = nil, macAddress: String? = nil) {
        entry = .scanned(ipAddress: ipAddress, networkID: networkID, macAddress: macAddress)
    }

    /// Opens the saved row with this `LocalDevice.id` (#584).
    init(deviceID: UUID) {
        entry = .saved(id: deviceID)
    }

    /// The address the entry names, for the title and "not found" while nothing is loaded.
    private var enteredAddress: String {
        switch entry {
        case let .scanned(ipAddress, _, _): ipAddress
        case .saved: "this saved device"
        }
    }

    private func load() {
        switch entry {
        case let .scanned(ipAddress, networkID, macAddress):
            viewModel.loadDevice(ipAddress: ipAddress, networkID: networkID, macAddress: macAddress, context: modelContext)
        case let .saved(id):
            viewModel.loadDevice(id: id, context: modelContext)
        }
    }

    var body: some View {
        ScrollView {
            if let device = viewModel.device, let current = viewModel.current {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    headerSection(device)
                    GroupSuggestionBanner(viewModel: viewModel)
                    networkInfoSection(device, current: current)
                    servicesAndPortsSection(current)
                    if !viewModel.interfaces.isEmpty {
                        DeviceInterfacesSection(
                            interfaces: viewModel.interfaces, primary: device, presence: presence,
                            groupLabel: viewModel.groupLabel(for:), onSeparate: viewModel.separateInterface, onRemove: requestRemoval
                        )
                    }
                    SameDeviceAsButton { showsSameDeviceAs = true }
                    statusSection(device)
                    quickActionsSection(current)
                    notesSection(device)
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            } else if viewModel.isLoading {
                ProgressView()
                    .tint(Theme.Colors.accent)
                    .accessibilityIdentifier("deviceDetail_label_loading")
            } else {
                ContentUnavailableView(
                    "Device Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("No device found at \(enteredAddress)")
                )
                .accessibilityIdentifier("deviceDetail_label_notFound")
            }
        }
        .themedBackground()
        .navigationTitle(viewModel.device?.displayName ?? enteredAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let device = viewModel.device {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: viewModel.shareText(presence: presence) ?? device.displayName) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("deviceDetail_button_share")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task<Void, Never> {
                            await viewModel.scanPorts()
                        }
                    } label: {
                        Label(viewModel.isScanning ? "Scanning Ports..." : "Scan Ports", systemImage: "network")
                    }
                    .disabled(viewModel.isScanning || viewModel.probeAddress == nil)
                    .accessibilityIdentifier("deviceDetail_menu_scanPorts")

                    Button {
                        Task<Void, Never> {
                            await viewModel.discoverServices()
                        }
                    } label: {
                        Label(viewModel.isDiscovering ? "Discovering..." : "Discover Services", systemImage: "bonjour")
                    }
                    .disabled(viewModel.isDiscovering || viewModel.probeAddress == nil)
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
        .task(id: entry) {
            load()
            guard !Task.isCancelled else { return }
            await viewModel.enrichDevice(bonjourServices: [])
        }
        .sheet(isPresented: $showsLabelCapture) {
            if let device = viewModel.device {
                LabelCaptureView(device: device, current: viewModel.current) {
                    // The saved values replace what the detail shows, suggestions included.
                    load()
                }
            }
        }
        // The screen's identifier goes on the content, not the toast inset, which would otherwise
        // carry it in place of `deviceDetail_toast_undo` (iOS 26+ stamps a container's id).
        .accessibilityIdentifier("screen_deviceDetail")
        .modifier(DeviceGroupingPresentation(viewModel: viewModel, showsSameDeviceAs: $showsSameDeviceAs))
        .confirmationDialog(removalTitle, isPresented: isConfirmingRemoval, titleVisibility: .visible, presenting: removingInterface) { member in
            Button("Remove Interface", role: .destructive) {
                viewModel.removeInterface(member)
                removingInterface = nil
            }
            .accessibilityIdentifier("deviceDetail_button_confirmRemoveInterface")
        } message: { member in
            Text(viewModel.removalMessage(member))
        }
    }

    private var presence: PresenceSnapshot {
        presenceModel?.snapshot ?? DevicePresenceModel.noScans
    }

    /// Removes a member at once, or after a confirmation naming what goes with it (#594).
    private func requestRemoval(_ member: LocalDevice) {
        if viewModel.userContent(of: member).isEmpty {
            viewModel.removeInterface(member)
        } else {
            removingInterface = member
        }
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { removingInterface != nil }, set: { removingInterface = $0 ? removingInterface : nil })
    }

    private var removalTitle: String {
        "Remove \(removingInterface?.ipAddress ?? "this interface")?"
    }

    // MARK: - Header Section

    private func headerSection(_ device: LocalDevice) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: device.deviceType.iconName)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityIdentifier("deviceDetail_image_deviceType")

            Text(device.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_displayName")

            // What the saved status means now (#583); the presence model refreshes every minute.
            // A device of several interfaces is online while any member is (#594).
            HStack(spacing: 8) {
                PresenceDot(freshness: viewModel.freshness(presence))
                Text(viewModel.projection.map { presence.statusText($0) } ?? presence.statusText(device))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.projection.map { presence.accessibilityText($0) } ?? presence.accessibilityText(device))
            .accessibilityIdentifier("deviceDetail_label_status")

            if let maker = device.maker {
                Text(maker)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("deviceDetail_label_manufacturer")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Network Info Section

    /// The device's identity (the primary's) and the current member's address and names.
    private func networkInfoSection(_ device: LocalDevice, current: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Network Information")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_networkInfoTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                infoRow(label: "IP Address", value: current.ipAddress)
                    .accessibilityIdentifier("deviceDetail_row_ipAddress")

                infoRow(label: "MAC Address", value: current.formattedMacAddress)
                    .accessibilityIdentifier("deviceDetail_row_macAddress")

                if let hostname = current.hostname {
                    infoRow(label: "Hostname", value: hostname)
                        .accessibilityIdentifier("deviceDetail_row_hostname")
                }

                if let resolvedHostname = current.resolvedHostname {
                    infoRow(label: "Resolved Name", value: resolvedHostname)
                        .accessibilityIdentifier("deviceDetail_row_resolvedHostname")
                }

                if let maker = device.maker {
                    suggestibleRow(label: "Manufacturer", value: maker, isSuggested: device.isMakerSuggested)
                        .accessibilityIdentifier("deviceDetail_row_manufacturerInfo")
                }

                if let model = device.modelName {
                    suggestibleRow(label: "Model", value: model, isSuggested: device.isModelSuggested)
                        .accessibilityIdentifier("deviceDetail_row_model")
                }

                // The serial (#561), moved out of the notes; the device's, so the primary's.
                if let serial = device.serialNumber, !serial.isEmpty {
                    infoRow(label: "Serial Number", value: serial)
                        .accessibilityIdentifier("deviceDetail_row_serial")
                }

                // A suggested type is shown, not written, until the user accepts it (#449).
                suggestibleRow(
                    label: "Type",
                    value: (viewModel.suggestedType ?? device.deviceType).rawValue.capitalized,
                    isSuggested: viewModel.suggestedType != nil
                )
                .accessibilityIdentifier("deviceDetail_row_deviceType")

                if viewModel.isShowingSuggestion {
                    suggestionRow
                }

                scanLabelButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Services & Ports Section

    /// The current member's ports and services: they stay on the interface they were found on.
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
                                Text(WellKnownServices.name(for: port) ?? "Port \(port)")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .font(.subheadline)

                                if WellKnownServices.name(for: port) != nil {
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
                        .accessibilityIdentifier("deviceDetail_row_port\(port)")

                        if index < openPorts.count - 1 {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                    }
                }

                // Discovered Services
                if let services = device.discoveredServices, !services.isEmpty {
                    if !(device.openPorts?.isEmpty ?? true) {
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
                        .accessibilityIdentifier("deviceDetail_row_service\(index)")

                        if index != services.count - 1 {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                    }
                }

                // Empty state or action buttons
                if device.openPorts?.isEmpty ?? true, device.discoveredServices?.isEmpty ?? true {
                    Text("No services or ports discovered yet")
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                // Action buttons
                Divider().background(Theme.Colors.glassBorder)

                servicesActionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("deviceDetail_section_services")
    }
}

// MARK: - Services Actions

extension DeviceDetailView {
    /// Scan Ports and Discover Services, under the services list.
    private var servicesActionButtons: some View {
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
            .disabled(viewModel.isScanning || viewModel.probeAddress == nil)
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
            .disabled(viewModel.isDiscovering || viewModel.probeAddress == nil)
            .accessibilityIdentifier("deviceDetail_button_discoverServices")
        }
    }
}

// MARK: - Status, Actions and Notes

extension DeviceDetailView {
    // MARK: - Status Section

    private func statusSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_statusTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                if let latency = viewModel.current?.lastLatency {
                    HStack {
                        Text("Latency")
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.Colors.latencyColor(ms: latency))
                                .frame(width: 8, height: 8)

                            Text(viewModel.current?.latencyText ?? "")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .accessibilityIdentifier("deviceDetail_row_latency")
                }

                infoRow(label: "First Seen", value: (viewModel.firstSeen ?? device.firstSeen).formatted(date: .abbreviated, time: .shortened))
                    .accessibilityIdentifier("deviceDetail_row_firstSeen")

                infoRow(label: "Last Seen", value: (viewModel.lastSeen ?? device.lastSeen).formatted(date: .abbreviated, time: .shortened))
                    .accessibilityIdentifier("deviceDetail_row_lastSeen")

                if viewModel.members.contains(where: \.isGateway) {
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

                if viewModel.members.contains(where: \.supportsWakeOnLan) {
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

    /// Ping, Port Scan and DNS act on the current member's address (#594).
    private func quickActionsSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_quickActionsTitle")

            VStack(spacing: Theme.Layout.itemSpacing) {
                // Ping button
                NavigationLink(value: AppDestination.ping(host: device.ipAddress)) {
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
                NavigationLink(value: AppDestination.portScanner(host: device.ipAddress)) {
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
                NavigationLink(value: AppDestination.dnsLookup(domain: device.ipAddress)) {
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

                // Wake-on-LAN button (conditional): every interface's MAC for a device of several.
                if (viewModel.projection?.realMACs.count ?? 0) > 1, viewModel.canWake {
                    Divider().background(Theme.Colors.glassBorder)

                    WakeAllInterfacesButton(viewModel: viewModel)
                } else if device.supportsWakeOnLan || viewModel.canWake {
                    Divider().background(Theme.Colors.glassBorder)

                    NavigationLink(value: AppDestination.wakeOnLAN(mac: viewModel.projection?.realMACs.first ?? device.macAddress)) {
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

    private func notesSection(_ device: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_notesTitle")

            // With several interfaces, each member's notes say which one they're about (#594).
            if !viewModel.interfaces.isEmpty {
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("deviceDetail_label_notesInterface")
            }

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
            .accessibilityIdentifier("deviceDetail_textfield_notes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String) -> some View {
        LabelValueRow(label: label, value: value)
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceDetailView(ipAddress: "192.168.1.1")
            .modelContainer(for: [LocalDevice.self], inMemory: true)
    }
}

// MARK: - Identity Suggestion (#449)

extension DeviceDetailView {
    /// An info row with a sparkles marker when its value came from the on-device model.
    private func suggestibleRow(label: String, value: String, isSuggested: Bool) -> some View {
        HStack(spacing: 4) {
            infoRow(label: label, value: value)
            if isSuggested {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityLabel("Suggested by the on-device model")
            }
        }
    }

    /// Marks what the on-device model suggested and lets the user keep or drop it (#449).
    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Suggested", systemImage: "sparkles")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Suggested by the on-device model")
                .accessibilityIdentifier("deviceDetail_badge_suggested")

            HStack(spacing: Theme.Layout.itemSpacing) {
                Button("Accept") { viewModel.acceptSuggestion() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("deviceDetail_button_acceptSuggestion")
                Button("Dismiss") { viewModel.dismissSuggestion() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("deviceDetail_button_dismissSuggestion")
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Label Capture (#456)

extension DeviceDetailView {
    /// Opens the label sheet: read the maker, model, serial and MAC from a photo of the label.
    private var scanLabelButton: some View {
        Button {
            showsLabelCapture = true
        } label: {
            Label("Scan Label", systemImage: "text.viewfinder")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.Colors.glassBackground)
                .cornerRadius(Theme.Layout.buttonCornerRadius)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .accessibilityIdentifier("deviceDetail_button_scanLabel")
    }
}
