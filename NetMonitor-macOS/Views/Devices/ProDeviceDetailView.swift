import Foundation
import SwiftUI
import SwiftData
import NetMonitorCore

struct ProDeviceDetailView: View {
    @Bindable var device: LocalDevice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var selectedDeviceType: DeviceType = .unknown

    @State private var showPingSheet = false
    @State private var showPortScanSheet = false
    @State private var wolAction = WakeOnLanAction()

    @State private var bonjourServices: [String] = []
    @State private var latencyHistory: [Double] = []

    // Enrichment loading states — shown as subtle spinners in each section
    @State private var isLoadingLatency = false
    @State private var isLoadingPorts = false
    @State private var isLoadingVendor = false
    @State private var isLoadingHostname = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                networkDetailsSection
                portsAndServicesSection
                latencyStatsSection
                hardwareSection
                wakeOnLanSection
                timelineSection
                notesSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle(device.displayName)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                // ⌘[ is the standard macOS "Back" shortcut; avoids conflict with
                // the sheet's own ESC handler which would dismiss the whole sheet.
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityIdentifier("deviceDetail_button_back")
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
            }
        }
        .task { await loadData() }
        .wakeOnLanAlert(wolAction)
        .sheet(isPresented: $showPingSheet) {
            DevicePingSheet(device: device, isPresented: $showPingSheet)
        }
        .sheet(isPresented: $showPortScanSheet) {
            DevicePortScanSheet(device: device, isPresented: $showPortScanSheet)
        }
    }

}

private extension ProDeviceDetailView {
    // MARK: - Header Section

    var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: device.deviceType.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Device Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(device.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                        .frame(width: 10, height: 10)

                    Text(device.status == .online ? "Online" : "Offline")
                        .font(.headline)
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .secondary)

                    if device.status == .online, let latency = device.lastLatency {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(latencyText(latency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let vendor = device.vendor {
                    Text(vendor)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if device.isGateway {
                    Text("Gateway")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MacTheme.Colors.info.opacity(0.2))
                        .foregroundStyle(MacTheme.Colors.info)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if isEditing {
                Picker("Type", selection: $selectedDeviceType) {
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Label(type.rawValue.capitalized, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .labelsHidden()
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Network Details Section

    var networkDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Network Details", systemImage: "network")
                    .font(.headline)
                if isLoadingHostname {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("IP Address")
                        .foregroundStyle(.secondary)
                    Text(device.ipAddress)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("MAC Address")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(device.macAddress.isEmpty ? "-" : device.macAddress)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)

                        if !device.macAddress.isEmpty {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(device.macAddress, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if let hostname = device.hostname, !hostname.isEmpty {
                    GridRow {
                        Text("Hostname")
                            .foregroundStyle(.secondary)
                        Text(hostname)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }

                if let resolved = device.resolvedHostname, !resolved.isEmpty {
                    GridRow {
                        Text("Resolved")
                            .foregroundStyle(.secondary)
                        Text(resolved)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Ports and Services Section

    var portsAndServicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ports & Services", systemImage: "server.rack")
                    .font(.headline)
                if isLoadingPorts {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
            }

            Divider()

            if let ports = device.openPorts, !ports.isEmpty {
                Text("Open Ports: \(ports.sorted().map(String.init).joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.Colors.info)
            } else {
                Text("No open ports detected")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if !bonjourServices.isEmpty {
                Divider()
                Text("Discovered Services:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(bonjourServices, id: \.self) { service in
                        Text(service)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MacTheme.Colors.info.opacity(0.1))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Latency Stats Section

    var latencyStatsSection: some View {
        let currentLatency = device.lastLatency
        let minLatency = latencyHistory.min()
        let maxLatency = latencyHistory.max()
        let avgLatency = latencyHistory.isEmpty ? nil : latencyHistory.reduce(0, +) / Double(latencyHistory.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latency Statistics", systemImage: "waveform.path")
                    .font(.headline)
                if isLoadingLatency {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
            }

            Divider()

            HStack(spacing: 24) {
                latencyStatItem(title: "Current", value: currentLatency.map(latencyText) ?? "-")
                latencyStatItem(title: "Min", value: minLatency.map(latencyText) ?? "-")
                latencyStatItem(title: "Max", value: maxLatency.map(latencyText) ?? "-")
                latencyStatItem(title: "Avg", value: avgLatency.map(latencyText) ?? "-")
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Latency Stat Item

    func latencyStatItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
        }
    }

    // MARK: - Hardware Section

    var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hardware", systemImage: "cpu")
                    .font(.headline)
                if isLoadingVendor {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Manufacturer")
                        .foregroundStyle(.secondary)
                    Text(device.vendor ?? "Unknown")
                }

                GridRow {
                    Text("Device Type")
                        .foregroundStyle(.secondary)
                    Label(device.deviceType.rawValue.capitalized, systemImage: device.deviceType.iconName)
                }

                GridRow {
                    Text("Supports WOL")
                        .foregroundStyle(.secondary)
                    Text(device.supportsWakeOnLan ? "Yes" : "No")
                        .foregroundStyle(device.supportsWakeOnLan ? MacTheme.Colors.success : .secondary)
                }

                if !device.macAddress.isEmpty {
                    GridRow {
                        Text("OUI")
                            .foregroundStyle(.secondary)
                        Text(String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)))
                            .fontDesign(.monospaced)
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Wake on LAN Section

    var wakeOnLanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wake on LAN", systemImage: "power")
                .font(.headline)

            Divider()

            if device.supportsWakeOnLan && !device.macAddress.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MAC Address")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(device.macAddress)
                            .fontDesign(.monospaced)
                    }

                    Spacer()

                    Button {
                        Task {
                            await wolAction.wake(device: device)
                        }
                    } label: {
                        Label("Wake", systemImage: "power")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Wake on LAN not supported")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Timeline Section

    var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timeline", systemImage: "clock")
                .font(.headline)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("First Seen")
                        .foregroundStyle(.secondary)
                    Text(device.firstSeen.formatted(date: .abbreviated, time: .shortened))
                }

                GridRow {
                    Text("Last Seen")
                        .foregroundStyle(.secondary)
                    Text(device.lastSeen.formatted(date: .abbreviated, time: .shortened))
                }

                GridRow {
                    Text("Time Since Last")
                        .foregroundStyle(.secondary)
                    Text(timeSinceLastSeen)
                }

                GridRow {
                    Text("Total Tracked")
                        .foregroundStyle(.secondary)
                    Text(totalTimeTracked)
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Notes Section

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Divider()

            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let notes = device.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("No notes")
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Actions Section

    var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Divider()

            HStack(spacing: 12) {
                actionButton(title: "Ping", icon: "waveform.path") {
                    showPingSheet = true
                }

                actionButton(title: "Port Scan", icon: "network") {
                    showPortScanSheet = true
                }

                actionButton(title: "Copy IP", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.ipAddress, forType: .string)
                }

                actionButton(title: "Copy MAC", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.macAddress, forType: .string)
                }
                .disabled(device.macAddress.isEmpty)
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Action Button

    func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    func latencyText(_ latency: Double) -> String {
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }

    var timeSinceLastSeen: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours" }
        return "\(Int(interval / 86400)) days"
    }

    var totalTimeTracked: String {
        let interval = Date().timeIntervalSince(device.firstSeen)
        if interval < 3600 { return "\(Int(interval / 60)) min" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours" }
        return "\(Int(interval / 86400)) days"
    }

    func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        selectedDeviceType = device.deviceType
    }

    func saveChanges() {
        device.customName = editedName.isEmpty ? nil : editedName
        device.notes = editedNotes.isEmpty ? nil : editedNotes
        device.deviceType = selectedDeviceType
        try? modelContext.save()
    }

    func loadData() async {
        // Seed immediately from persisted model so UI is never blank on open
        bonjourServices = device.discoveredServices ?? []
        latencyHistory = device.lastLatency.map { [$0] } ?? []

        // Run all enrichment in parallel — each writes back to the persisted
        // device model so the data is available on subsequent opens too.
        async let _ = enrichLatency()
        async let _ = enrichVendor()
        async let _ = enrichHostname()
        async let _ = enrichPorts()
        async let _ = enrichBonjourServices()
    }

    // MARK: - Live Enrichment

    /// Ping the device (5 probes) and populate latencyHistory with real stats.
    private func enrichLatency() async {
        isLoadingLatency = true
        defer { isLoadingLatency = false }

        let pingService = ShellPingService()
        guard let result = try? await pingService.ping(host: device.ipAddress, count: 5, timeout: 3),
              result.isReachable else { return }

        // Build history from min/avg/max so the stats table shows meaningful data
        let samples = [result.minLatency, result.avgLatency, result.maxLatency]
            .filter { $0 > 0 }
        latencyHistory = samples

        // Update the persisted lastLatency to the average
        device.updateLatency(result.avgLatency)
        try? modelContext.save()
    }

    /// Look up vendor from MAC if missing, write it back.
    private func enrichVendor() async {
        guard !device.macAddress.isEmpty,
              (device.vendor == nil || device.vendor?.isEmpty == true) else { return }
        isLoadingVendor = true
        defer { isLoadingVendor = false }

        let service = MACVendorLookupService()
        if let vendor = await service.lookupVendorEnhanced(macAddress: device.macAddress) {
            device.vendor = vendor
            try? modelContext.save()
        }
    }

    /// Resolve hostname via reverse DNS / mDNS / NetBIOS if missing.
    private func enrichHostname() async {
        guard device.hostname == nil || device.hostname?.isEmpty == true else { return }
        isLoadingHostname = true
        defer { isLoadingHostname = false }

        let resolver = DeviceNameResolver()
        if let name = await resolver.resolveName(for: device.ipAddress) {
            device.hostname = name
            try? modelContext.save()
        }
    }

    /// Quick scan of common ports if we have none yet.
    private func enrichPorts() async {
        guard device.openPorts == nil || device.openPorts?.isEmpty == true else { return }
        isLoadingPorts = true
        defer { isLoadingPorts = false }

        // Common fingerprinting ports — same set as the coordinator uses
        let commonPorts = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]
        let ip = device.ipAddress

        // PortScannerService is an actor; call scan() within a Task to satisfy isolation
        let found: [Int] = await Task.detached {
            let scanner = PortScannerService()
            var open: [Int] = []
            for await result in await scanner.scan(host: ip, ports: commonPorts, timeout: 1.5) {
                if result.state == .open {
                    open.append(result.port)
                }
            }
            return open.sorted()
        }.value

        if !found.isEmpty {
            device.openPorts = found
            try? modelContext.save()
        }
    }

    /// Browse Bonjour for up to 4 seconds to collect services advertised by this device.
    private func enrichBonjourServices() async {
        guard let bonjourScanner = coordinator?.bonjourScanner else { return }

        let targetIP = device.ipAddress
        let targetHostname = device.hostname ?? device.resolvedHostname ?? ""
        var found = Set(device.discoveredServices ?? [])

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

        // Browse for up to 4 seconds
        try? await Task.sleep(for: .seconds(4))
        browseTask.cancel()
        await bonjourScanner.stopDiscovery()

        let services = found.sorted()
        if !services.isEmpty {
            bonjourServices = services
            device.discoveredServices = services
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
