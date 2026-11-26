import Foundation
import SwiftUI
import SwiftData
import NetMonitorCore
import os

/// The Pro device detail (#594): `device` is the device's primary row; the view finds the other
/// interfaces itself (see `DeviceDetailView`).
struct ProDeviceDetailView: View {
    @Bindable var device: LocalDevice
    /// The rows of `device`'s group (or `device` alone), read live.
    @Query private var groupRows: [LocalDevice]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presence) private var presence
    @Environment(AlertRuleStore.self) private var ruleStore: AlertRuleStore?
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?

    @State private var isEditing = false
    /// Device detail's grouping actions (#594 PR2): the Devices list's, else this detail's own, so
    /// a detail opened from the dashboard, Ask or Security Readout can group and separate (#619).
    @Environment(DeviceGroupingViewModel.self) private var installedGrouping: DeviceGroupingViewModel?
    @State private var ownGrouping = DeviceGroupingViewModel(dispatcher: DeviceEventDispatcher.shared)
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var editedMemberNotes: [UUID: String] = [:]
    /// Why the last edit couldn't be saved; shown in an alert.
    @State private var saveError: String?
    /// The shown row, removed as an interface: deleted once the sheet has closed, so the sheet
    /// never draws a deleted row.
    @State private var removalOnClose: UUID?
    @State private var selectedDeviceType: DeviceType = .unknown

    @State private var showPingSheet = false
    @State private var showPortScanSheet = false
    @State private var wolAction = WakeOnLanAction()

    @State private var bonjourServices: [String] = []
    @State private var latencyHistory: [Double] = []

    // Enrichment loading states
    @State private var isLoadingLatency = false
    @State private var isLoadingPorts = false
    @State private var isLoadingVendor = false
    @State private var isLoadingHostname = false

    init(device: LocalDevice) {
        _device = Bindable(device)
        _groupRows = DeviceGroupMembers.query(for: device)
    }

    var projection: DeviceProjection { DeviceGroupMembers.projection(of: device, rows: groupRows) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar bar
            topBar
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    // Risks first, where they are seen without scrolling (#454).
                    securitySection
                    detailColumns
                    DeviceGroupingSection(device: projection)
                    if projection.isGroup {
                        DeviceInterfacesCard(device: projection, onRemove: removeInterface)
                    }
                    portsAndServicesSection
                    DeviceNotesCard(
                        device: projection, row: device, isEditing: isEditing,
                        editedNotes: $editedNotes, editedMemberNotes: $editedMemberNotes
                    )
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .macThemedBackground()
        .task { await loadData() }
        // Grouping can change the device's identity, which recreates this view: its draft is
        // saved first (#619).
        .environment(\.commitDeviceDetailEdits) {
            if isEditing {
                saveChanges()
                isEditing = false
            }
        }
        .wakeOnLanAlert(wolAction)
        .saveErrorAlert($saveError)
        .deviceGroupingFeedback()
        .sheet(isPresented: $showPingSheet) {
            DevicePingSheet(device: projection.current, name: device.displayName, isPresented: $showPingSheet)
        }
        .sheet(isPresented: $showPortScanSheet) {
            DevicePortScanSheet(device: projection.current, name: device.displayName, isPresented: $showPortScanSheet)
        }
        .onDisappear {
            if let removalOnClose {
                // The sheet is gone; a failure is logged and the list reloads (`didFail`).
                InterfaceRemoval.remove(removalOnClose, in: modelContext, ruleStore: ruleStore)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen_deviceDetail")
        .environment(installedGrouping ?? ownGrouping)
    }
}

private extension ProDeviceDetailView {

    // MARK: - Top Bar

    var topBar: some View {
        HStack(spacing: 12) {
            // Close
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
            .accessibilityIdentifier("deviceDetail_button_close")

            Text(device.displayName)
                .font(.headline)
                .lineLimit(1)

            if isAnyLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    showPingSheet = true
                } label: {
                    Label("Ping", systemImage: "waveform.path")
                }
                .accessibilityIdentifier("deviceDetail_button_ping")

                Button {
                    showPortScanSheet = true
                } label: {
                    Label("Scan Ports", systemImage: "network")
                }
                .accessibilityIdentifier("deviceDetail_button_portScan")

                // Every interface's MAC (#594).
                if projection.members.contains(where: \.supportsWakeOnLan) && !projection.realMACs.isEmpty {
                    Button {
                        Task<Void, Never> {
                            await wolAction.wake(device: projection)
                        }
                    } label: {
                        Label("Wake", systemImage: "power")
                    }
                    .accessibilityIdentifier("deviceDetail_button_wake")
                }

                Divider()
                    .frame(height: 18)

                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                    isEditing.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("deviceDetail_button_edit")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    var isAnyLoading: Bool {
        isLoadingLatency || isLoadingPorts || isLoadingVendor || isLoadingHostname
    }

    // MARK: - Header Section

    var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(MacTheme.Colors.presenceColor(presence.freshness(of: projection)).opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(MacTheme.Colors.presenceColor(presence.freshness(of: projection)))
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    HStack(spacing: 8) {
                        TextField("Device Name", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .accessibilityIdentifier("deviceDetail_textfield_name")

                        Picker("Type", selection: $selectedDeviceType) {
                            ForEach(DeviceType.allCases, id: \.self) { type in
                                Label(type.rawValue.capitalized, systemImage: type.iconName)
                                    .tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .accessibilityIdentifier("deviceDetail_picker_type")
                    }
                } else {
                    Text(device.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                HStack(spacing: 8) {
                    PresenceStatusLabel(device: projection, font: .subheadline)
                        .accessibilityIdentifier("deviceDetail_label_presence")

                    if let latency = presence.currentLatency(projection) {
                        Text("·")
                            .foregroundStyle(MacTheme.Colors.labelTertiary)
                        Text(latencyText(latency))
                            .font(.subheadline)
                            .foregroundStyle(MacTheme.Colors.labelSecondary)
                    }

                    if device.isGateway {
                        Text("Gateway")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MacTheme.Colors.info.opacity(0.15))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(Capsule())
                    }
                }

                if let maker = device.maker {
                    Text(maker)
                        .font(.subheadline)
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                }
            }

            Spacer()

            // Latency stats cluster (top-right): only while the device is online (#583).
            if presence.currentLatency(projection) != nil {
                latencyCluster
            }
        }
        .padding(16)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Latency Cluster (compact)

    var latencyCluster: some View {
        let currentLatency = presence.currentLatency(projection)
        let minLatency = latencyHistory.min()
        let maxLatency = latencyHistory.max()
        let avgLatency = latencyHistory.isEmpty ? nil : latencyHistory.reduce(0, +) / Double(latencyHistory.count)

        return HStack(spacing: 16) {
            latencyStatItem(title: "CUR", value: currentLatency.map(latencyText) ?? "—")
            latencyStatItem(title: "MIN", value: minLatency.map(latencyText) ?? "—")
            latencyStatItem(title: "MAX", value: maxLatency.map(latencyText) ?? "—")
            latencyStatItem(title: "AVG", value: avgLatency.map(latencyText) ?? "—")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func latencyStatItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MacTheme.Colors.labelQuaternary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }

    // MARK: - Two-Column Details

    var detailColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: Network
            networkColumn
            // Right: Hardware & Timeline
            hardwareAndTimelineColumn
        }
    }

    var networkColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Network", icon: "network", loading: isLoadingHostname)

            // The current interface's (#594); Interfaces lists the others.
            let current = projection.current
            detailRow("IP Address", current.ipAddress, mono: true, copyable: true)
            detailRow(
                "MAC Address", current.macAddress.isEmpty ? "—" : current.formattedMacAddress, mono: true, copyable: !current.macAddress.isEmpty
            )

            if let hostname = device.hostname, !hostname.isEmpty {
                detailRow("Hostname", hostname, mono: true)
            }
            if let resolved = device.resolvedHostname, !resolved.isEmpty {
                detailRow("Resolved", resolved, mono: true)
            }
            if let model = device.modelName, !model.isEmpty {
                HStack(spacing: 4) {
                    detailRow("Model", model, mono: true)
                    if device.isModelSuggested {
                        SuggestedMarker()
                    }
                }
            }

            // The device's serial lives on its primary (#561).
            if let serial = device.shownSerial {
                detailRow("Serial", serial, mono: true, copyable: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("deviceDetail_label_serial")
            }

            Divider().padding(.vertical, 2)

            detailRow("First Seen", device.firstSeen.formatted(date: .abbreviated, time: .shortened))
            detailRow("Last Seen", projection.lastSeen.formatted(date: .abbreviated, time: .shortened))
            detailRow("Since Last", timeSinceLastSeen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    var hardwareAndTimelineColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Hardware", icon: "cpu", loading: isLoadingVendor)

            HStack(spacing: 4) {
                detailRow("Manufacturer", device.maker ?? "Unknown")
                if device.isMakerSuggested {
                    SuggestedMarker()
                }
            }
            // The MAC prefix names the network chip's maker (Espressif, Murata), often not the
            // brand on the device (ADR-022).
            if let chipMaker = device.vendor, !chipMaker.isEmpty, chipMaker != device.maker {
                detailRow("Network Chip", chipMaker)
            }
            // A suggested type is shown, not written, until the user accepts it (#449).
            if let suggestedType = coordinator?.suggestedType(for: device) {
                HStack(spacing: 4) {
                    detailRow("Device Type", suggestedType.rawValue.capitalized)
                    SuggestedMarker()
                }
            } else {
                detailRow("Device Type", device.deviceType.rawValue.capitalized)
            }

            if !device.macAddress.isEmpty {
                detailRow("OUI", String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)), mono: true)
            }

            detailRow("Wake-on-LAN", device.supportsWakeOnLan ? "Supported" : "No",
                       valueColor: device.supportsWakeOnLan ? MacTheme.Colors.success : MacTheme.Colors.labelSecondary)

            // Hidden while editing: Done writes the picker's type over an accepted one.
            if !isEditing, let coordinator, coordinator.isShowingSuggestion(device) {
                DeviceSuggestionBar(
                    onAccept: { coordinator.acceptSuggestion(for: device) },
                    onDismiss: { coordinator.dismissSuggestion(for: device) }
                )
            }

            Divider().padding(.vertical, 2)

            detailRow("Tracked For", totalTimeTracked)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Ports & Services

    var portsAndServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Ports & Services", icon: "server.rack", loading: isLoadingPorts)

            // The current interface's; Interfaces lists each interface's own (#594).
            if let ports = projection.current.openPorts, !ports.isEmpty {
                HStack(spacing: 6) {
                    ForEach(ports.sorted(), id: \.self) { port in
                        Text("\(port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MacTheme.Colors.info.opacity(0.1))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .accessibilityIdentifier("deviceDetail_list_ports")
            } else {
                Text("No open ports detected")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
            }

            if !bonjourServices.isEmpty {
                Divider().padding(.vertical, 2)

                Text("BONJOUR SERVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.labelQuaternary)
                    .tracking(0.5)

                FlowLayout(spacing: 8) {
                    ForEach(bonjourServices, id: \.self) { service in
                        Text(service)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MacTheme.Colors.success.opacity(0.08))
                            .foregroundStyle(MacTheme.Colors.success)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Security (#454)

    /// This device's security-readout findings, computed from its rows (every interface's, #594);
    /// nothing when it has none.
    @ViewBuilder
    var securitySection: some View {
        let findings = SecurityRuleTable.findings(for: projection.members)
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Security", icon: "exclamationmark.shield")
                ForEach(findings) { finding in
                    SecurityFindingRow(finding: finding, showsDevice: false)
                        .accessibilityIdentifier("deviceDetail_row_security_\(finding.ruleID)_\(finding.port)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("deviceDetail_section_security")
        }
    }

    // MARK: - Reusable Components

    func sectionHeader(_ title: String, icon: String, loading: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.Colors.labelTertiary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .tracking(0.8)
            if loading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.bottom, 2)
    }

    func detailRow(_ label: String, _ value: String, mono: Bool = false, copyable: Bool = false, valueColor: Color? = nil) -> some View {
        LabelValueRow(
            label: label,
            value: value,
            labelWidth: 100,
            labelFont: .subheadline,
            valueFont: .subheadline,
            isMonospaced: mono,
            isCopyable: copyable,
            valueColor: valueColor ?? .primary
        )
    }

    // MARK: - Helpers

    func latencyText(_ latency: Double) -> String {
        if latency < 1 {
            return "<1 ms"
        }
        return String(format: "%.0f ms", latency)
    }

    var timeSinceLastSeen: String {
        presence.relativeLastSeen(projection)
    }

    var totalTimeTracked: String {
        let interval = Date().timeIntervalSince(device.firstSeen)
        if interval < 3600 {
            return "\(Int(interval / 60)) min"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600)) hours"
        }
        return "\(Int(interval / 86400)) days"
    }

    func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        editedMemberNotes = DeviceNotesCard.memberDrafts(projection, row: device)
        selectedDeviceType = device.deviceType
    }

    func saveChanges() {
        let edits = DeviceDetailEdits(name: editedName, notes: editedNotes, type: selectedDeviceType, memberNotes: editedMemberNotes)
        editedMemberNotes = [:]
        do {
            try edits.commit(to: device, device: projection, in: modelContext)
        } catch {
            Logger.data.error("Failed to save device changes: \(error)")
            saveError = error.localizedDescription
        }
    }

    /// Remove this interface (#594). Removing the row the sheet shows closes the sheet first, and
    /// the row goes once it has closed.
    func removeInterface(_ member: LocalDevice) async throws {
        coordinator?.cancelSuggestions()
        if member === device {
            removalOnClose = member.id
            dismiss()
        } else {
            try await InterfaceRemoval.remove(member.id, in: modelContext, ruleStore: ruleStore).value
        }
    }

    /// Enrichment measures the current interface (#594) and saves on its row: a port or a latency
    /// belongs to the interface it was measured on.
    func loadData() async {
        let currentMember = projection.current
        // Seed immediately from persisted model so UI is never blank on open
        bonjourServices = currentMember.discoveredServices ?? []
        latencyHistory = currentMember.lastLatency.map { [$0] } ?? []

        // Run all enrichment in parallel
        async let _ = enrichLatency()
        async let _ = enrichVendor()
        async let _ = enrichHostname()
        async let _ = enrichPorts()
        async let _ = enrichBonjourServices()
    }

    // MARK: - Live Enrichment

    private func enrichLatency() async {
        let currentMember = projection.current
        isLoadingLatency = true
        defer { isLoadingLatency = false }

        let pingService = ShellPingService()
        guard let result = try? await pingService.ping(host: currentMember.ipAddress, count: 5, timeout: 3),
              result.isReachable else { return }

        let samples = [result.minLatency, result.avgLatency, result.maxLatency]
            .filter { $0 > 0 }
        latencyHistory = samples

        currentMember.updateLatency(result.avgLatency)
        try? modelContext.save()
    }

    private func enrichVendor() async {
        let currentMember = projection.current
        guard !currentMember.macAddress.isEmpty,
              currentMember.vendor == nil || currentMember.vendor?.isEmpty == true else { return }
        isLoadingVendor = true
        defer { isLoadingVendor = false }

        let service = MACVendorLookupService()
        if let vendor = await service.lookupVendorEnhanced(macAddress: currentMember.macAddress) {
            currentMember.vendor = vendor
            try? modelContext.save()
        }
    }

    private func enrichHostname() async {
        let currentMember = projection.current
        guard currentMember.hostname == nil || currentMember.hostname?.isEmpty == true else { return }
        isLoadingHostname = true
        defer { isLoadingHostname = false }

        let resolver = ShellDeviceNameResolver()
        if let name = await resolver.resolveName(for: currentMember.ipAddress) {
            currentMember.hostname = name
            try? modelContext.save()
        }
    }

    private func enrichPorts() async {
        let currentMember = projection.current
        guard currentMember.openPorts == nil || currentMember.openPorts?.isEmpty == true else { return }
        isLoadingPorts = true
        defer { isLoadingPorts = false }

        let commonPorts = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]
        let ip = currentMember.ipAddress

        let found: [Int] = await Task.detached {
            let scanner = PortScannerService()
            var open: [Int] = []
            for await result in await scanner.scan(host: ip, ports: commonPorts, timeout: 1.5) where result.state == .open {
                open.append(result.port)
            }
            return open.sorted()
        }.value

        if !found.isEmpty {
            currentMember.openPorts = found
            try? modelContext.save()
        }
    }

    private func enrichBonjourServices() async {
        let currentMember = projection.current
        guard let bonjourScanner = coordinator?.bonjourScanner else { return }

        let targetIP = currentMember.ipAddress
        let targetHostname = currentMember.hostname ?? currentMember.resolvedHostname ?? ""
        var found = Set(currentMember.discoveredServices ?? [])

        let stream = await bonjourScanner.discoveryStream(serviceType: nil)
        let browseTask = Task {
            for await service in stream {
                let matchesIP = service.addresses.contains(targetIP)
                let matchesHost = !targetHostname.isEmpty &&
                    (service.hostName?.localizedCaseInsensitiveContains(targetHostname) == true ||
                     targetHostname.localizedCaseInsensitiveContains(service.hostName ?? "") == true)
                if matchesIP || matchesHost {
                    let label = service.name.isEmpty ? service.type : "\(service.name) (\(service.type))"
                    found.insert(label)
                }
            }
        }

        try? await Task.sleep(for: .seconds(4))
        browseTask.cancel()
        await bonjourScanner.stopDiscovery()

        let services = found.sorted()
        if !services.isEmpty {
            bonjourServices = services
            currentMember.discoveredServices = services
            try? modelContext.save()
        }
    }
}

#Preview {
    ProDeviceDetailView(device: LocalDevice(
        ipAddress: "192.168.1.1",
        macAddress: "AA:BB:CC:DD:EE:FF",
        hostname: "router.local",
        vendor: "Apple",
        deviceType: .router,
        status: .online,
        lastLatency: 2.5,
        isGateway: true,
        supportsWakeOnLan: true,
        openPorts: [22, 80, 443, 8080],
        discoveredServices: ["SSH", "HTTP", "HTTPS", "HTTP-ALT"]
    ))
}
