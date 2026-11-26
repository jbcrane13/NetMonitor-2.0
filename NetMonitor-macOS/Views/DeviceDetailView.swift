// swiftlint:disable type_body_length
import SwiftUI
import SwiftData
import NetMonitorCore
import Darwin
import os

/// A device's detail (#594): `device` is the device's primary row, where its name, notes, type and
/// rules live. The view finds the device's other interfaces itself and shows them in Interfaces.
struct DeviceDetailView: View {
    @Bindable var device: LocalDevice
    var isSheet: Bool = false
    /// Called after Remove this interface, with a remaining member's row ID, so the list can
    /// reselect the device (whose primary may have changed).
    var onInterfaceRemoved: (UUID?) -> Void = { _ in }
    /// The rows of `device`'s group (or `device` alone): the members, read live.
    @Query private var groupRows: [LocalDevice]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeviceDiscoveryCoordinator.self) private var discoveryCoordinator: DeviceDiscoveryCoordinator?
    @Environment(\.appAccentColor) private var accentColor
    @Environment(\.presence) private var presence

    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    /// Drafts of the other members' notes, by row ID, while editing.
    @State private var editedMemberNotes: [UUID: String] = [:]
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

    init(device: LocalDevice, isSheet: Bool = false, onInterfaceRemoved: @escaping (UUID?) -> Void = { _ in }) {
        _device = Bindable(device)
        self.isSheet = isSheet
        self.onInterfaceRemoved = onInterfaceRemoved
        _groupRows = DeviceGroupMembers.query(for: device)
    }

    /// The device as lists show it: `device` and every other member of its group.
    private var projection: DeviceProjection {
        DeviceGroupMembers.projection(of: device, rows: groupRows)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                quickActionBar
                networkInfoCard
                if projection.isGroup {
                    DeviceInterfacesCard(device: projection, onRemove: removeInterface)
                }
                manufacturerSection
                timelineSection
                servicesSection
                DeviceNotesCard(
                    device: projection, row: device, isEditing: isEditing,
                    editedNotes: $editedNotes, editedMemberNotes: $editedMemberNotes
                )
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
        .task(id: projection.members.map(\.ipAddress)) {
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
                    .fill(MacTheme.Colors.presenceColor(presence.freshness(of: projection)).opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.title)
                    .foregroundStyle(MacTheme.Colors.presenceColor(presence.freshness(of: projection)))
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

                PresenceStatusLabel(device: projection, font: .subheadline)
                    .accessibilityIdentifier("deviceDetail_label_presence")

                if let maker = device.maker {
                    Text(maker)
                        .font(.caption)
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
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

            if !projection.realMACs.isEmpty {
                quickActionIcon(
                    title: "Wake",
                    systemImage: "power",
                    color: MacTheme.Colors.success,
                    action: { Task { await wolAction.wake(device: projection) } }
                )
                .accessibilityIdentifier("deviceDetail_button_qaWake")
            }

            quickActionIcon(
                title: "Copy IP",
                systemImage: "doc.on.doc",
                color: .secondary,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(projection.current.ipAddress, forType: .string)
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

            // The current interface's (#594); Interfaces lists the others.
            infoRow(label: "IP Address", value: projection.current.ipAddress, monospace: true)

            if !projection.current.macAddress.isEmpty {
                infoRow(label: "MAC Address", value: projection.current.macAddress, monospace: true)
            }

            if let hostname = projection.current.hostname ?? device.hostname {
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

            if let maker = device.maker {
                HStack(spacing: 4) {
                    infoRow(label: "Manufacturer", value: maker)
                    if device.isMakerSuggested {
                        SuggestedMarker()
                    }
                }
            }

            if let model = device.modelName {
                HStack(spacing: 4) {
                    infoRow(label: "Model", value: model, monospace: true)
                    if device.isModelSuggested {
                        SuggestedMarker()
                    }
                }
            }

            // A suggested type is shown, not written, until the user accepts it (#449).
            if let suggestedType = discoveryCoordinator?.suggestedType(for: device) {
                HStack(spacing: 4) {
                    infoRow(label: "Device Type", value: suggestedType.rawValue.capitalized)
                    SuggestedMarker()
                }
            } else {
                infoRow(label: "Device Type", value: device.deviceType.rawValue.capitalized)
            }

            if !device.macAddress.isEmpty {
                infoRow(label: "MAC Address", value: device.macAddress, monospace: true)

                infoRow(
                    label: "OUI Prefix",
                    value: String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)),
                    monospace: true
                )
            }

            // Hidden while editing: Done writes the picker's type over an accepted one.
            if !isEditing, let discoveryCoordinator, discoveryCoordinator.isShowingSuggestion(device) {
                Divider()
                DeviceSuggestionBar(
                    onAccept: { discoveryCoordinator.acceptSuggestion(for: device) },
                    onDismiss: { discoveryCoordinator.dismissSuggestion(for: device) }
                )
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        // Keeps the suggestion controls' own identifiers (#449).
        .accessibilityElement(children: .contain)
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
                value: firstSeen.formatted(date: .abbreviated, time: .shortened)
            )

            infoRow(
                label: "Last Seen",
                value: projection.lastSeen.formatted(date: .abbreviated, time: .shortened)
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
                    .foregroundStyle(MacTheme.Colors.textSecondary)
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

                if !projection.realMACs.isEmpty {
                    actionButton(
                        title: "Wake",
                        systemImage: "power",
                        action: {
                            Task {
                                await wolAction.wake(device: projection)
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
        LabelValueRow(label: label, value: value, isMonospaced: monospace, valueLineLimit: 1)
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
        presence.relativeLastSeen(projection)
    }

    /// The earliest of the members'.
    private var firstSeen: Date {
        projection.members.map(\.firstSeen).min() ?? device.firstSeen
    }

    private var totalTimeTracked: String {
        let interval = Date().timeIntervalSince(firstSeen)
        if interval < 3600 {
            return "\(Int(interval / 60)) minutes"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600)) hours"
        }
        return "\(Int(interval / 86400)) days"
    }

    // MARK: - Actions

    private func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        editedMemberNotes = DeviceNotesCard.memberDrafts(projection, row: device)
        selectedDeviceType = device.deviceType
    }

    private func saveChanges() {
        device.customName = editedName.isEmpty ? nil : editedName
        device.notes = editedNotes.isEmpty ? nil : editedNotes
        device.deviceType = selectedDeviceType
        DeviceNotesCard.save(editedMemberNotes, to: projection)
        editedMemberNotes = [:]
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
        // Services answer by address; any interface's are the device's (#594).
        let addresses = Set(projection.members.map(\.ipAddress))
        let deviceServices = cachedServices.filter { service in
            service.addresses.contains(where: addresses.contains)
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
        let ipAddress = projection.current.ipAddress
        let descriptor = FetchDescriptor<NetworkTarget>(
            predicate: #Predicate<NetworkTarget> { target in
                target.host == ipAddress
            }
        )

        do {
            let existingTargets = try modelContext.fetch(descriptor)

            if !existingTargets.isEmpty {
                // Target already exists
                addToTargetsMessage = "A monitoring target for \(ipAddress) already exists."
                showAddToTargetsAlert = true
                return
            }

            // Create new target
            let target = NetworkTarget(
                name: device.displayName,
                host: ipAddress,
                port: nil,
                targetProtocol: .icmp,
                // Settings › Monitoring › Timing, like Add Target (#445).
                checkInterval: TargetDefaults.interval(),
                timeout: TargetDefaults.timeout(),
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

    // MARK: - Interfaces (#594)

    /// Remove this interface: deletes the member's row through `DeviceGroupWriter`. The group
    /// keeps its ID; a removed primary passes to the next member.
    private func removeInterface(_ member: LocalDevice) {
        let remaining = projection.members.first { $0.id != member.id }?.id
        discoveryCoordinator?.cancelSuggestions()
        InterfaceRemoval.remove(member.id, in: modelContext)
        onInterfaceRemoved(remaining)
    }

    // MARK: - Sheet Views

    private var pingSheetView: some View {
        DevicePingSheet(device: projection.current, name: device.displayName, isPresented: $showPingSheet)
    }

    private var portScanSheetView: some View {
        DevicePortScanSheet(device: projection.current, name: device.displayName, isPresented: $showPortScanSheet)
    }
}

// swiftlint:enable type_body_length

// MARK: - Model Suggestions (#449)

/// Marks a value the on-device model suggested. Used by both device detail views.
struct SuggestedMarker: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.info)
            .help("Suggested by on-device model")
            .accessibilityLabel("Suggested by on-device model")
    }
}

/// The "Suggested" badge with Accept and Dismiss, shown while a device's maker, model or
/// type comes from the on-device model. Used by both device detail views.
struct DeviceSuggestionBar: View {
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("Suggested", systemImage: "sparkles")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MacTheme.Colors.info.opacity(0.15))
                .foregroundStyle(MacTheme.Colors.info)
                .clipShape(Capsule())
                .help("Suggested by on-device model")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Suggested by on-device model")
                .accessibilityIdentifier("deviceDetail_badge_suggested")

            Spacer(minLength: 8)

            Button("Dismiss", action: onDismiss)
                .help("Remove the suggestion")
                .accessibilityIdentifier("deviceDetail_button_dismissSuggestion")

            Button("Accept", action: onAccept)
                .buttonStyle(.borderedProminent)
                .help("Keep the suggested maker, model and type")
                .accessibilityIdentifier("deviceDetail_button_acceptSuggestion")
        }
        .controlSize(.small)
    }
}
