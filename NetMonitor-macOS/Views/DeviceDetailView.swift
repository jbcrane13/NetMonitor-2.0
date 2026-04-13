// swiftlint:disable type_body_length
import SwiftUI
import SwiftData
import NetMonitorCore
import Darwin
import os

struct DeviceDetailView: View {
    @Bindable var device: LocalDevice
    var isSheet: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(DeviceDiscoveryCoordinator.self) private var discoveryCoordinator: DeviceDiscoveryCoordinator?
    @Environment(\.appAccentColor) private var accentColor

    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var selectedDeviceType: DeviceType = .unknown
    @State private var wolAction = WakeOnLanAction()

    // Ping sheet state
    @State private var showPingSheet = false

    // Port scan sheet state
    @State private var showPortScanSheet = false

    // Add to targets feedback
    @State private var showAddToTargetsAlert = false
    @State private var addToTargetsMessage = ""

    // Bonjour services discovered for this device (loaded from cache)
    @State private var bonjourServices: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                quickActionBar
                networkInfoCard
                manufacturerSection
                timelineSection
                servicesSection
                notesCard
                actionsSection
            }
            .padding()
        }
        .navigationTitle(device.displayName)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("deviceDetail_button_close")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                    isEditing.toggle()
                }
                .accessibilityIdentifier("deviceDetail_button_edit")
            }
        }
        .task {
            await loadBonjourServices()
        }
        .wakeOnLanAlert(wolAction)
        .alert("Add to Targets", isPresented: $showAddToTargetsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addToTargetsMessage)
        }
        .sheet(isPresented: $showPingSheet) {
            pingSheetView
        }
        .sheet(isPresented: $showPortScanSheet) {
            portScanSheetView
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.title)
                    .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Device Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("deviceDetail_textfield_name")
                } else {
                    Text(device.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(device.status == .online ? "Online" : "Offline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let vendor = device.vendor {
                    Text(vendor)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isEditing {
                Picker("Device Type", selection: $selectedDeviceType) {
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Label(type.rawValue.capitalized, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityIdentifier("deviceDetail_picker_type")
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_header")
    }

    // MARK: - Quick Action Bar

    private var quickActionBar: some View {
        HStack(spacing: 8) {
            quickActionIcon(
                title: "Ping",
                systemImage: "waveform.path",
                color: accentColor,
                action: { showPingSheet = true }
            )
            .accessibilityIdentifier("deviceDetail_button_qaPing")

            quickActionIcon(
                title: "Scan Ports",
                systemImage: "network",
                color: MacTheme.Colors.info,
                action: { showPortScanSheet = true }
            )
            .accessibilityIdentifier("deviceDetail_button_qaPortScan")

            if !device.macAddress.isEmpty {
                quickActionIcon(
                    title: "Wake",
                    systemImage: "power",
                    color: MacTheme.Colors.success,
                    action: { Task { await wolAction.wake(device: device) } }
                )
                .accessibilityIdentifier("deviceDetail_button_qaWake")
            }

            quickActionIcon(
                title: "Copy IP",
                systemImage: "doc.on.doc",
                color: .secondary,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.ipAddress, forType: .string)
                }
            )
            .accessibilityIdentifier("deviceDetail_button_qaCopyIP")

            quickActionIcon(
                title: "Monitor",
                systemImage: "plus.circle",
                color: MacTheme.Colors.warning,
                action: { addToTargets() }
            )
            .accessibilityIdentifier("deviceDetail_button_qaAddTarget")
        }
        .accessibilityIdentifier("deviceDetail_section_quickActions")
    }

    private func quickActionIcon(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Network Info Card

    private var networkInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Information", systemImage: "network")
                .font(.headline)

            Divider()

            infoRow(label: "IP Address", value: device.ipAddress, monospace: true)

            if !device.macAddress.isEmpty {
                infoRow(label: "MAC Address", value: device.macAddress, monospace: true)
            }

            if let hostname = device.hostname {
                infoRow(label: "Hostname", value: hostname, monospace: true)
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_networkInfo")
    }

    // MARK: - Manufacturer Section

    private var manufacturerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hardware", systemImage: "cpu")
                .font(.headline)

            Divider()

            if let vendor = device.vendor {
                infoRow(label: "Manufacturer", value: vendor)
            }

            if !device.macAddress.isEmpty {
                infoRow(label: "MAC Address", value: device.macAddress, monospace: true)

                infoRow(
                    label: "OUI Prefix",
                    value: String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)),
                    monospace: true
                )
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_hardware")
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timeline", systemImage: "clock")
                .font(.headline)

            Divider()

            infoRow(
                label: "First Seen",
                value: device.firstSeen.formatted(date: .abbreviated, time: .shortened)
            )

            infoRow(
                label: "Last Seen",
                value: device.lastSeen.formatted(date: .abbreviated, time: .shortened)
            )

            infoRow(label: "Time Since Last Seen", value: timeSinceLastSeen)

            infoRow(label: "Total Time Tracked", value: totalTimeTracked)
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_timeline")
    }

    // MARK: - Services Section

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Discovered Services", systemImage: "server.rack")
                .font(.headline)

            Divider()

            if bonjourServices.isEmpty {
                Text("No services discovered")
                    .foregroundStyle(.secondary)
                    .font(.body)
            } else {
                ForEach(bonjourServices, id: \.self) { service in
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(accentColor)
                        Text(service)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_services")
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Divider()

            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("deviceDetail_textfield_notes")
            } else {
                if let notes = device.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No notes")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_notes")
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Divider()

            HStack(spacing: 12) {
                actionButton(
                    title: "Ping",
                    systemImage: "waveform.path",
                    action: { showPingSheet = true }
                )
                .accessibilityIdentifier("deviceDetail_button_ping")

                actionButton(
                    title: "Port Scan",
                    systemImage: "network",
                    action: { showPortScanSheet = true }
                )
                .accessibilityIdentifier("deviceDetail_button_portScan")

                if !device.macAddress.isEmpty {
                    actionButton(
                        title: "Wake",
                        systemImage: "power",
                        action: {
                            Task {
                                await wolAction.wake(device: device)
                            }
                        }
                    )
                    .accessibilityIdentifier("deviceDetail_button_wake")
                }

                actionButton(
                    title: "Add to Targets",
                    systemImage: "plus.circle",
                    action: { addToTargets() }
                )
                .accessibilityIdentifier("deviceDetail_button_addToTargets")
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("deviceDetail_card_actions")
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .fontDesign(monospace ? .monospaced : .default)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Computed Properties

    private var timeSinceLastSeen: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) minutes ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours ago" }
        return "\(Int(interval / 86400)) days ago"
    }

    private var totalTimeTracked: String {
        let interval = Date().timeIntervalSince(device.firstSeen)
        if interval < 3600 { return "\(Int(interval / 60)) minutes" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours" }
        return "\(Int(interval / 86400)) days"
    }

    // MARK: - Actions

    private func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        selectedDeviceType = device.deviceType
    }

    private func saveChanges() {
        device.customName = editedName.isEmpty ? nil : editedName
        device.notes = editedNotes.isEmpty ? nil : editedNotes
        device.deviceType = selectedDeviceType
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Failed to save device changes: \(error)")
        }
    }

    private func loadBonjourServices() async {
        // Get cached Bonjour services from the last discovery scan
        guard let discoveryCoordinator else { return }
        let cachedServices = await discoveryCoordinator.bonjourScanner.discoveredServices
        let deviceServices = cachedServices.filter { service in
            service.addresses.contains(device.ipAddress)
        }

        // Update bonjourServices with the service types found
        bonjourServices = deviceServices.map { service in
            if let port = service.port {
                return "\(service.type) (Port \(port))"
            } else {
                return service.type
            }
        }
    }

    private func addToTargets() {
        // Check for existing target with same host
        let ipAddress = device.ipAddress
        let descriptor = FetchDescriptor<NetworkTarget>(
            predicate: #Predicate<NetworkTarget> { target in
                target.host == ipAddress
            }
        )

        do {
            let existingTargets = try modelContext.fetch(descriptor)

            if !existingTargets.isEmpty {
                // Target already exists
                addToTargetsMessage = "A monitoring target for \(device.ipAddress) already exists."
                showAddToTargetsAlert = true
                return
            }

            // Create new target
            let target = NetworkTarget(
                name: device.displayName,
                host: device.ipAddress,
                port: nil,
                targetProtocol: .icmp,
                checkInterval: 30,
                timeout: 10,
                isEnabled: true
            )
            modelContext.insert(target)
            try modelContext.save()

            // Show success message
            addToTargetsMessage = "Successfully added \(device.displayName) to monitoring targets."
            showAddToTargetsAlert = true

        } catch {
            // Show error message
            addToTargetsMessage = "Failed to add target: \(error.localizedDescription)"
            showAddToTargetsAlert = true
        }
    }

    // MARK: - Sheet Views

    private var pingSheetView: some View {
        DevicePingSheet(device: device, isPresented: $showPingSheet)
    }

    private var portScanSheetView: some View {
        DevicePortScanSheet(device: device, isPresented: $showPortScanSheet)
    }
}

// swiftlint:enable type_body_length
