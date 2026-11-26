// swiftlint:disable file_length
// swiftlint:disable type_body_length
import SwiftUI
import NetMonitorCore
import SwiftData
import AppKit
import Darwin
import os

struct DevicesView: View {
    var isSheet: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Environment(\.dismiss) private var dismiss
    /// The network's saved rows, every group complete (#594); lists show `filteredDevices`.
    @State private var devices: [LocalDevice] = []

    /// The selected device's ID: a group's ID or a row's, resolved through `DeviceGroupResolver`
    /// so the detail stays on the device when its primary changes (#594).
    @State private var selectedDeviceID: UUID?
    @State private var searchText: String = ""
    @State private var filterOnlineOnly: Bool = false
    /// Past devices (unseen for a week, #583) are hidden at every launch, never remembered hidden:
    /// the list always says how many there are, so none is hidden without a visible way back.
    @State private var showPastDevices = false
    @Environment(\.presence) private var presence
    @State private var sortOrder: DeviceSortOrder = .lastSeen
    @State private var sortAscending: Bool = false
    @AppStorage("netmonitor.devices.viewMode") private var viewMode: DeviceViewMode = .consumer
    @State private var wolAction = WakeOnLanAction()
    @State private var availableNetworks: [NetworkProfile] = []
    @State private var selectedNetworkID: UUID?

    // Pro mode detail sheet
    @State private var selectedProDevice: LocalDevice?

    // Context menu action state
    @State private var deviceToPing: DeviceProjection?
    @State private var deviceToScan: DeviceProjection?

    // MARK: - View Mode

    enum DeviceViewMode: String, CaseIterable {
        case consumer = "Consumer"
        case pro = "Pro"

        var icon: String {
            switch self {
            case .consumer: return "square.grid.2x2"
            case .pro: return "list.bullet"
            }
        }
    }

    /// One entry per device (#594): rows projected, then searched, filtered and sorted.
    var filteredDevices: [DeviceProjection] {
        DeviceList.devices(
            devices,
            filter: DeviceListFilter(search: searchText, onlineOnly: filterOnlineOnly, showPast: showPastDevices),
            presence: presence,
            sort: sortOrder,
            ascending: sortAscending
        )
    }

    /// The N in "Show past devices (N)".
    private var pastDeviceCount: Int {
        DeviceList.pastCount(
            devices, filter: DeviceListFilter(search: searchText, onlineOnly: filterOnlineOnly), presence: presence
        )
    }

    /// The selected device, as the list shows it.
    private var selectedDevice: DeviceProjection? {
        selectedDeviceID.flatMap { Self.device(for: $0, among: devices, in: modelContext) }
    }

    private var selectedNetwork: NetworkProfile? {
        guard let selectedNetworkID else { return nil }
        return availableNetworks.first { $0.id == selectedNetworkID }
    }

    private var activeProfileID: UUID? {
        selectedNetworkID
            ?? coordinator?.networkProfile?.id
            ?? coordinator?.networkProfileManager.activeProfile?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if viewMode == .pro {
                proModeFullScreenList
            } else {
                HStack(spacing: 0) {
                    // Device list
                    VStack(spacing: 0) {
                        deviceList
                    }
                    .frame(minWidth: 280, idealWidth: 350, maxWidth: 450)

                    Divider()

                    // Detail pane
                    if let device = selectedDevice {
                        DeviceDetailView(device: device.primary) { remaining in
                            // Removing an interface can change the primary or end the group.
                            selectedDeviceID = remaining
                        }
                        // A new device starts with fresh edit state, so a draft can't be
                        // saved onto a device an alert selected (#478). So does a new primary
                        // (#594): after Remove this interface, a draft of the removed row's name
                        // or notes must not be saved onto the interface that takes its place.
                        .id([device.id, device.primary.id])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Select a Device",
                            systemImage: "desktopcomputer",
                            description: Text("Choose a device from the list to view details")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("devices_label_selectDevice")
                    }
                }
            }
        }
        .wakeOnLanAlert(wolAction)
        .sheet(item: $selectedProDevice) { device in
            ProDeviceDetailView(device: device)
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(item: $deviceToPing) { device in
            DevicePingSheet(device: device.current, name: device.displayName, isPresented: Binding(
                get: { deviceToPing != nil },
                set: {
                    if !$0 {
                        deviceToPing = nil
                    }
                }
            ))
        }
        .sheet(item: $deviceToScan) { device in
            DevicePortScanSheet(device: device.current, name: device.displayName, isPresented: Binding(
                get: { deviceToScan != nil },
                set: {
                    if !$0 {
                        deviceToScan = nil
                    }
                }
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkProfilesDidChange)) { _ in
            availableNetworks = coordinator?.networkProfileManager.profiles
                ?? NetworkProfileManager.detectActiveProfiles()
            // A picked network that no longer exists (the old local network after a move)
            // falls back to the network being scanned now.
            if let selectedNetworkID, !availableNetworks.contains(where: { $0.id == selectedNetworkID }) {
                self.selectedNetworkID = nil
            }
            reloadDevices()
        }
        .onAppear {
            availableNetworks = coordinator?.networkProfileManager.profiles
                ?? NetworkProfileManager.detectActiveProfiles()
            reloadDevices()
        }
        .onChange(of: selectedNetworkID) {
            reloadDevices()
        }
        .onChange(of: NotificationRouter.shared.deviceToSelect, initial: true) { _, id in
            selectPendingDevice(id)
        }
        // An interface about to be removed (#594) leaves the list before it is deleted, so no
        // row draws a deleted model; the list reloads once the deletion is saved.
        .onReceive(NotificationCenter.default.publisher(for: InterfaceRemoval.willRemove)) { note in
            devices.removeAll { $0.id == note.object as? UUID }
        }
        .onReceive(NotificationCenter.default.publisher(for: InterfaceRemoval.didFail)) { _ in
            reloadDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reloadDevices()
        }
        .onChange(of: coordinator?.isScanning) { _, isScanning in
            if isScanning == false {
                reloadDevices()
            }
        }
    }

    /// Selects the device an alert's View Details asked for (#478), on its own network. `id` may
    /// name any interface's row; the device it belongs to is selected (#594).
    private func selectPendingDevice(_ id: UUID?) {
        guard let id else { return }
        NotificationRouter.shared.deviceToSelect = nil
        let descriptor = FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == id })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        if let network = row.networkProfileID, network != activeProfileID {
            selectedNetworkID = network
        }
        reloadDevices()
        let rows = devices.contains { $0.id == id } ? devices : devices + [row]
        let device = DeviceGroupResolver(rows: LocalDeviceQueries.completed(rows, in: modelContext)).device(for: id)
        if viewMode == .pro {
            selectedProDevice = device?.primary ?? row
        } else {
            selectedDeviceID = device?.id ?? id
        }
    }

    /// The device `id` names (a group's ID or any interface's row ID): from the list's rows, else
    /// from the store, so an alert's View Details opens a device the list's fetch left out (#615
    /// review).
    static func device(for id: UUID, among rows: [LocalDevice], in context: ModelContext) -> DeviceProjection? {
        if let listed = DeviceGroupResolver(rows: rows).device(for: id) {
            return listed
        }
        if let row = try? context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == id })).first {
            return try? DeviceGroups.device(of: row, in: context)
        }
        let members = (try? DeviceGroups.members(ofGroups: [id], in: context)) ?? []
        return DeviceGroups.project(members).first
    }

    /// The rows the list reads: the active network's, or with none, rows saved without a network
    /// (as before #594), never every network's.
    static func scope(_ activeProfileID: UUID?) -> DeviceScope {
        .network(activeProfileID, else: .withoutNetwork)
    }

    private func reloadDevices() {
        // The 500 most recent devices, paged by device, each with all its interfaces (#594).
        devices = LocalDeviceQueries.recentDevices(in: Self.scope(activeProfileID), in: modelContext).flatMap(\.members)
    }

    // MARK: - Device List

    private var deviceList: some View {
        Group {
            if filteredDevices.isEmpty && pastDeviceCount == 0 && coordinator?.isScanning != true {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network",
                    description: Text("Click Scan to discover devices on your network")
                )
                .accessibilityIdentifier("devices_label_empty")
            } else {
                if viewMode == .consumer {
                    consumerModeList
                } else {
                    proModeList
                }
            }
        }
        .overlay {
            if coordinator?.isScanning == true {
                scanningOverlay
            }
        }
    }

    // MARK: - Consumer Mode List (Card-based)

    private var consumerModeList: some View {
        let selectedID = selectedDevice?.id
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredDevices) { device in
                    DeviceCardView(device: device, isSelected: selectedID == device.id)
                        .onTapGesture {
                            selectedDeviceID = device.id
                        }
                        .accessibilityIdentifier("devices_card_\(device.ipAddress)")
                        .contextMenu { deviceContextMenu(for: device) }
                }
                pastDevicesToggle
            }
            .padding()
        }
    }

    // MARK: - Pro Mode List (Dense Table)

    private var proModeFullScreenList: some View {
        Group {
            if filteredDevices.isEmpty && pastDeviceCount == 0 && coordinator?.isScanning != true {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network",
                    description: Text("Click Scan to discover devices on your network")
                )
                .accessibilityIdentifier("devices_label_empty")
            } else {
                proModeList
            }
        }
        .overlay {
            if coordinator?.isScanning == true {
                scanningOverlay
            }
        }
    }

    private var proModeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                proModeHeaderRow

                // Data rows
                ForEach(filteredDevices) { device in
                    ProModeRowView(device: device, isSelected: selectedProDevice.map { device.contains($0.id) } ?? false)
                        .onTapGesture {
                            selectedProDevice = device.primary
                        }
                        .accessibilityIdentifier("devices_row_pro\(device.ipAddress)")
                        .contextMenu { deviceContextMenu(for: device) }
                    Rectangle()
                        .fill(MacTheme.Colors.divider)
                        .frame(height: 1)
                }
                pastDevicesToggle
                    .padding(.vertical, 8)
            }
        }
        .background(MacTheme.Colors.chartSurface)
    }

    /// "Show past devices (N)" under the list, while there are any (#583).
    @ViewBuilder
    private var pastDevicesToggle: some View {
        if pastDeviceCount > 0 {
            Button(showPastDevices ? "Hide past devices" : "Show past devices (\(pastDeviceCount))") {
                showPastDevices.toggle()
            }
            .buttonStyle(.link)
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.labelSecondary)
            .help("Devices not seen for \(PresenceFreshness.pastDeviceDays) days while this network was scanned")
            .accessibilityIdentifier("devices_button_showPast")
        }
    }

    private var proModeHeaderRow: some View {
        HStack(spacing: ProModeRowView.columnSpacing) {
            sortableHeader("", order: .status, width: ProModeRowView.statusWidth)
            Text("Type")
                .frame(width: ProModeRowView.typeWidth, alignment: .leading)
            sortableHeader("IP Address", order: .ipAddress, width: ProModeRowView.ipWidth)
            sortableHeader("Name", order: .name, width: ProModeRowView.nameWidth)
            sortableHeader("Vendor", order: .vendor, width: ProModeRowView.vendorWidth)
            Text("MAC")
                .frame(width: ProModeRowView.macWidth, alignment: .leading)
            Text("Ports")
                .frame(width: ProModeRowView.portsWidth, alignment: .leading)
            sortableHeader("Latency", order: .latency, width: ProModeRowView.latencyWidth)
            sortableHeader("Seen", order: .lastSeen, width: ProModeRowView.seenWidth)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(MacTheme.Colors.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MacTheme.Colors.chartSurfaceShallow)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacTheme.Colors.hairline)
                .frame(height: 1)
        }
    }

    private func sortableHeader(_ label: String, order: DeviceSortOrder, width: CGFloat) -> some View {
        Button {
            if sortOrder == order {
                sortAscending.toggle()
            } else {
                sortOrder = order
                sortAscending = (order == .lastSeen) ? false : true
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                if sortOrder == order {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortOrder == order ? MacTheme.Colors.textPrimary : MacTheme.Colors.labelTertiary)
        .accessibilityIdentifier("devices_proHeader_\(order.label.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    // MARK: - Scanning Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            ProgressView(value: coordinator?.scanProgress ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text("Scanning network...")
                .font(.headline)

            Text("\(Int((coordinator?.scanProgress ?? 0) * 100))% complete")
                .font(.caption)
                .foregroundStyle(MacTheme.Colors.labelSecondary)

            Button("Stop") {
                coordinator?.stopScan()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("devices_button_stopScan")
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 24)
    }

    // MARK: - Top Bar

    /// The picker sizes to its title, so a long network name is shortened to keep the
    /// one-row top bar from overflowing at narrow widths (#425).
    static func pickerTitle(_ name: String, limit: Int = 24) -> String {
        name.count > limit ? String(name.prefix(limit - 1)) + "…" : name
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            // Close — only shown in sheet context
            if isSheet {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("devices_button_close")
            }

            Text("Devices")
                .font(.headline)

            // Device count
            Text("\(filteredDevices.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(MacTheme.Colors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MacTheme.Colors.chartSurface)
                .clipShape(Capsule())

            if coordinator?.isScanning == true {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            Spacer(minLength: 12)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("devices_textfield_search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MacTheme.Colors.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("devices_button_clearSearch")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(minWidth: 120, maxWidth: 200)
            .accessibilityIdentifier("devices_textfield_search")

            Divider()
                .frame(height: 18)

            // Network picker
            Picker("Network", selection: $selectedNetworkID) {
                Label("Auto", systemImage: "sparkles")
                    .tag(UUID?.none)
                ForEach(availableNetworks) { profile in
                    Label(Self.pickerTitle(profile.displayName), systemImage: profile.connectionType.iconName)
                        .tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            // Size to the network name; the old fixed 120pt clipped it behind the label.
            .fixedSize()
            .accessibilityIdentifier("devices_picker_network")

            // Sort
            Menu {
                ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Label(order.label, systemImage: order.icon)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("devices_menu_sort\(order.label.lowercased())")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("devices_menu_sort")

            // View mode
            Picker("View", selection: $viewMode) {
                ForEach(DeviceViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("devices_picker_viewMode")

            // Online only filter
            Toggle(isOn: $filterOnlineOnly) {
                Image(systemName: filterOnlineOnly ? "circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(filterOnlineOnly ? MacTheme.Colors.success : MacTheme.Colors.labelSecondary)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Online Only")
            .accessibilityIdentifier("devices_toggle_onlineOnly")

            Divider()
                .frame(height: 18)

            // Scan button
            Button {
                coordinator?.rescan(.user(selectedNetwork))
            } label: {
                Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(coordinator?.isScanning == true)
            .accessibilityIdentifier("devices_button_scan")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    /// Deletes every listed device, each with all its interfaces (#594).
    private func clearDevices() {
        selectedDeviceID = nil
        coordinator?.cancelSuggestions()
        do {
            try DeviceGroupWriter(context: modelContext).deleteDevices(filteredDevices.map(\.id))
        } catch {
            Logger.data.error("Failed to clear devices: \(error)")
        }
        reloadDevices()
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func deviceContextMenu(for device: DeviceProjection) -> some View {
        // Actions use the current interface; Wake on LAN goes to every interface's MAC (#594).
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.current.ipAddress, forType: .string)
        } label: {
            Label("Copy IP Address", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("devices_menu_copyIP")

        if !device.current.macAddress.isEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.current.macAddress, forType: .string)
            } label: {
                Label("Copy MAC Address", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("devices_menu_copyMAC")
        }

        Divider()

        Button {
            deviceToPing = device
        } label: {
            Label("Ping Device", systemImage: "waveform.path")
        }
        .accessibilityIdentifier("devices_menu_ping")

        Button {
            deviceToScan = device
        } label: {
            Label("Scan Ports", systemImage: "network")
        }
        .accessibilityIdentifier("devices_menu_portScan")

        if !device.realMACs.isEmpty {
            Button {
                Task {
                    await wolAction.wake(device: device)
                }
            } label: {
                Label("Wake on LAN", systemImage: "power")
            }
            .accessibilityIdentifier("devices_menu_wake")
        }

        Divider()

        Button(role: .destructive) {
            if selectedDevice?.id == device.id {
                selectedDeviceID = nil
            }
            if let selectedProDevice, device.contains(selectedProDevice.id) {
                self.selectedProDevice = nil
            }
            coordinator?.cancelSuggestions()
            // Every interface of the device goes (#594).
            do {
                try DeviceGroupWriter(context: modelContext).deleteDevice(device.id)
            } catch {
                Logger.data.error("Failed to remove device: \(error)")
            }
            reloadDevices()
        } label: {
            Label("Remove Device", systemImage: "trash")
        }
        .accessibilityIdentifier("devices_menu_remove")
    }
}

// MARK: - Helper Sheet Views

struct DevicePingSheet: View {
    /// The interface to run against (a device's current member, #594).
    let device: LocalDevice
    /// The device's name, when it isn't the row's (a group's primary's).
    var name: String?
    @Binding var isPresented: Bool

    @State private var pingResults: [String] = []
    @State private var isPinging = false
    @State private var pingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Ping \(name ?? device.displayName)", systemImage: "waveform.path")
                    .font(.headline)
                Spacer()
                Button {
                    stopPing()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("devicePingSheet_button_close")
            }
            .padding()

            Divider()

            // Device info
            HStack {
                Text("Target:")
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                Text(device.ipAddress)
                    .fontDesign(.monospaced)
                if let hostname = device.hostname {
                    Text("(\(hostname))")
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                }
                Spacer()
            }
            .padding()
            .background(MacTheme.Colors.chartSurfaceShallow)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pingResults.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .background(MacTheme.Colors.chartSurface)
                .onChange(of: pingResults.count) { _, _ in
                    if let lastIndex = pingResults.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if isPinging {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Pinging...")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                } else {
                    Text(pingResults.isEmpty ? "Ready to ping" : "Completed")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }

                Spacer()

                if !isPinging && !pingResults.isEmpty {
                    Button("Clear") {
                        pingResults.removeAll()
                    }
                    .accessibilityIdentifier("devicePingSheet_button_clear")
                }

                Button(isPinging ? "Stop" : "Run") {
                    if isPinging {
                        stopPing()
                    } else {
                        runPing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("devices_button_pingRun")
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .accessibilityIdentifier("devices_section_pingSheet")
        .onAppear {
            if !isPinging && pingResults.isEmpty {
                runPing()
            }
        }
        .onDisappear {
            pingTask?.cancel()
            pingTask = nil
        }
    }

    private func runPing() {
        isPinging = true
        pingResults.removeAll()
        pingResults.append("PING \(device.ipAddress) (5 packets)...")

        pingTask = Task {
            let pingService = PingService()
            let stream = await pingService.ping(host: device.ipAddress, count: 5, timeout: 5)
            for await result in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    if result.isTimeout {
                        pingResults.append("Request timeout for icmp_seq \(result.sequence)")
                    } else {
                        let ip = result.ipAddress ?? result.host
                        pingResults.append("\(result.size) bytes from \(ip): icmp_seq=\(result.sequence) ttl=\(result.ttl) time=\(result.timeText)")
                    }
                }
            }
            await MainActor.run {
                pingResults.append("--- Ping completed ---")
                isPinging = false
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        if isPinging {
            pingResults.append("--- Ping cancelled ---")
            isPinging = false
        }
    }
}

struct DevicePortScanSheet: View {
    /// The interface to run against (a device's current member, #594).
    let device: LocalDevice
    /// The device's name, when it isn't the row's (a group's primary's).
    var name: String?
    @Binding var isPresented: Bool

    @State private var portScanResults: [(port: Int, name: String, isOpen: Bool)] = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0.0
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Port Scan \(name ?? device.displayName)", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button {
                    stopPortScan()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("devicePortScanSheet_button_close")
            }
            .padding()

            Divider()

            // Device info
            HStack {
                Text("Target:")
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                Text(device.ipAddress)
                    .fontDesign(.monospaced)
                if let hostname = device.hostname {
                    Text("(\(hostname))")
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                }
                Spacer()
            }
            .padding()
            .background(MacTheme.Colors.chartSurfaceShallow)

            Divider()

            // Progress
            if isScanning {
                VStack(spacing: 8) {
                    ProgressView(value: scanProgress)
                        .progressViewStyle(.linear)
                    Text("\(Int(scanProgress * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .padding()
            }

            // Results
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(portScanResults, id: \.port) { result in
                        HStack {
                            Text("\(result.port)")
                                .fontDesign(.monospaced)
                                .frame(width: 60, alignment: .leading)
                            Text(result.name)
                                .foregroundStyle(MacTheme.Colors.labelSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(result.isOpen ? MacTheme.Colors.success : MacTheme.Colors.labelQuaternary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text(result.isOpen ? "Open" : "Closed")
                                    .foregroundStyle(result.isOpen ? MacTheme.Colors.success : MacTheme.Colors.labelSecondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(result.isOpen ? MacTheme.Colors.success.opacity(0.1) : Color.clear)
                    }
                }
            }
            .background(MacTheme.Colors.chartSurfaceShallow)

            Divider()

            // Footer
            HStack {
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning ports...")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                } else {
                    let openCount = portScanResults.filter { $0.isOpen }.count
                    Text(portScanResults.isEmpty ? "Ready to scan" : "\(openCount) open ports found")
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }

                Spacer()

                if !isScanning && !portScanResults.isEmpty {
                    Button("Clear") {
                        portScanResults.removeAll()
                        scanProgress = 0.0
                    }
                    .accessibilityIdentifier("devicePortScanSheet_button_clear")
                }

                Button(isScanning ? "Stop" : "Scan") {
                    if isScanning {
                        stopPortScan()
                    } else {
                        runPortScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("devices_button_portScan")
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .accessibilityIdentifier("devices_section_portScanSheet")
        .onAppear {
            if !isScanning && portScanResults.isEmpty {
                runPortScan()
            }
        }
        .onDisappear {
            scanTask?.cancel()
            scanTask = nil
        }
    }

    private func runPortScan() {
        isScanning = true
        portScanResults.removeAll()
        scanProgress = 0.0

        // Common ports to scan
        let commonPorts: [(Int, String)] = [
            (22, "SSH"),
            (80, "HTTP"),
            (443, "HTTPS"),
            (445, "SMB"),
            (548, "AFP"),
            (3389, "RDP"),
            (5900, "VNC"),
            (8080, "HTTP-Alt"),
            (8443, "HTTPS-Alt"),
            (21, "FTP"),
            (23, "Telnet"),
            (25, "SMTP"),
            (53, "DNS"),
            (110, "POP3"),
            (143, "IMAP"),
            (3306, "MySQL"),
            (5432, "PostgreSQL"),
            (6379, "Redis"),
            (27017, "MongoDB")
        ]

        scanTask = Task {
            for (index, portInfo) in commonPorts.enumerated() {
                guard isScanning else { break }

                let (port, name) = portInfo
                let isOpen = await checkPort(port: port)

                await MainActor.run {
                    portScanResults.append((port: port, name: name, isOpen: isOpen))
                    scanProgress = Double(index + 1) / Double(commonPorts.count)
                }
            }

            await MainActor.run {
                isScanning = false
                scanProgress = 1.0
            }
        }
    }

    private func checkPort(port: Int) async -> Bool {
        let ipAddress = device.ipAddress
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.netmonitor.portscan")
            queue.async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                hints.ai_protocol = IPPROTO_TCP

                var result: UnsafeMutablePointer<addrinfo>?
                let portString = String(port)
                let resolveStatus = getaddrinfo(ipAddress, portString, &hints, &result)

                guard resolveStatus == 0, let addrInfo = result else {
                    continuation.resume(returning: false)
                    return
                }
                defer { freeaddrinfo(result) }

                let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
                guard sock >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { close(sock) }

                // Set socket to non-blocking
                var flags = fcntl(sock, F_GETFL, 0)
                flags |= O_NONBLOCK
                _ = fcntl(sock, F_SETFL, flags)

                // Attempt connection
                _ = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)

                if errno == EINPROGRESS {
                    // Wait for connection with 2 second timeout
                    var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                    let pollResult = poll(&pfd, 1, 2000)

                    if pollResult > 0 {
                        var socketError: Int32 = 0
                        var errorLen = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLen)
                        continuation.resume(returning: socketError == 0)
                    } else {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: errno == 0)
                }
            }
        }
    }

    private func stopPortScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}

extension DeviceSortOrder {
    var label: String {
        switch self {
        case .lastSeen: return "Last Seen"
        case .name: return "Name"
        case .ipAddress: return "IP Address"
        case .status: return "Status"
        case .vendor: return "Vendor"
        case .latency: return "Latency"
        }
    }

    var icon: String {
        switch self {
        case .lastSeen: return "clock"
        case .name: return "textformat"
        case .ipAddress: return "number"
        case .status: return "circle.fill"
        case .vendor: return "building.2"
        case .latency: return "waveform.path"
        }
    }
}

#if DEBUG
#Preview {
    DevicesView()
        .modelContainer(PreviewContainer().container)
}
#endif

// swiftlint:enable type_body_length
