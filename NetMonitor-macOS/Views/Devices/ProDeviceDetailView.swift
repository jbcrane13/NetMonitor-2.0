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

    // Enrichment loading states
    @State private var isLoadingLatency = false
    @State private var isLoadingPorts = false
    @State private var isLoadingVendor = false
    @State private var isLoadingHostname = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar bar
            topBar
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    detailColumns
                    portsAndServicesSection
                    notesSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .macThemedBackground()
        .task { await loadData() }
        .wakeOnLanAlert(wolAction)
        .sheet(isPresented: $showPingSheet) {
            DevicePingSheet(device: device, isPresented: $showPingSheet)
        }
        .sheet(isPresented: $showPortScanSheet) {
            DevicePortScanSheet(device: device, isPresented: $showPortScanSheet)
        }
        .accessibilityIdentifier("screen_deviceDetail")
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
                    .foregroundStyle(.secondary)
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

                if device.supportsWakeOnLan && !device.macAddress.isEmpty {
                    Button {
                        Task<Void, Never> {
                            await wolAction.wake(device: device)
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
                    .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.12) : Color.gray.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
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
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(device.status == .online ? "Online" : "Offline")
                        .font(.subheadline)
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .secondary)

                    if device.status == .online, let latency = device.lastLatency {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(latencyText(latency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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

                if let vendor = device.vendor {
                    Text(vendor)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Latency stats cluster (top-right)
            if !latencyHistory.isEmpty || device.lastLatency != nil {
                latencyCluster
            }
        }
        .padding(16)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Latency Cluster (compact)

    var latencyCluster: some View {
        let currentLatency = device.lastLatency
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
                .foregroundStyle(.tertiary)
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

            detailRow("IP Address", device.ipAddress, mono: true, copyable: true)
            detailRow("MAC Address", device.macAddress.isEmpty ? "—" : device.formattedMacAddress, mono: true, copyable: !device.macAddress.isEmpty)

            if let hostname = device.hostname, !hostname.isEmpty {
                detailRow("Hostname", hostname, mono: true)
            }
            if let resolved = device.resolvedHostname, !resolved.isEmpty {
                detailRow("Resolved", resolved, mono: true)
            }

            Divider().padding(.vertical, 2)

            detailRow("First Seen", device.firstSeen.formatted(date: .abbreviated, time: .shortened))
            detailRow("Last Seen", device.lastSeen.formatted(date: .abbreviated, time: .shortened))
            detailRow("Since Last", timeSinceLastSeen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    var hardwareAndTimelineColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Hardware", icon: "cpu", loading: isLoadingVendor)

            detailRow("Manufacturer", device.vendor ?? "Unknown")
            detailRow("Device Type", device.deviceType.rawValue.capitalized)

            if !device.macAddress.isEmpty {
                detailRow("OUI", String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)), mono: true)
            }

            detailRow("Wake-on-LAN", device.supportsWakeOnLan ? "Supported" : "No",
                       valueColor: device.supportsWakeOnLan ? MacTheme.Colors.success : .secondary)

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

            if let ports = device.openPorts, !ports.isEmpty {
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
                    .foregroundStyle(.tertiary)
            }

            if !bonjourServices.isEmpty {
                Divider().padding(.vertical, 2)

                Text("BONJOUR SERVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
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

    // MARK: - Notes

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Notes", icon: "note.text")

            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("deviceDetail_textfield_notes")
            } else if let notes = device.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("No notes — click Edit to add")
                    .foregroundStyle(.tertiary)
                    .italic()
                    .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Reusable Components

    func sectionHeader(_ title: String, icon: String, loading: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
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
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Group {
                if mono {
                    Text(value)
                        .fontDesign(.monospaced)
                } else {
                    Text(value)
                }
            }
            .font(.subheadline)
            .foregroundStyle(valueColor ?? .primary)
            .textSelection(.enabled)

            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("deviceDetail_button_copy_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }

            Spacer()
        }
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

        // Run all enrichment in parallel
        async let _ = enrichLatency()
        async let _ = enrichVendor()
        async let _ = enrichHostname()
        async let _ = enrichPorts()
        async let _ = enrichBonjourServices()
    }

    // MARK: - Live Enrichment

    private func enrichLatency() async {
        isLoadingLatency = true
        defer { isLoadingLatency = false }

        let pingService = ShellPingService()
        guard let result = try? await pingService.ping(host: device.ipAddress, count: 5, timeout: 3),
              result.isReachable else { return }

        let samples = [result.minLatency, result.avgLatency, result.maxLatency]
            .filter { $0 > 0 }
        latencyHistory = samples

        device.updateLatency(result.avgLatency)
        try? modelContext.save()
    }

    private func enrichVendor() async {
        guard !device.macAddress.isEmpty,
              device.vendor == nil || device.vendor?.isEmpty == true else { return }
        isLoadingVendor = true
        defer { isLoadingVendor = false }

        let service = MACVendorLookupService()
        if let vendor = await service.lookupVendorEnhanced(macAddress: device.macAddress) {
            device.vendor = vendor
            try? modelContext.save()
        }
    }

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

    private func enrichPorts() async {
        guard device.openPorts == nil || device.openPorts?.isEmpty == true else { return }
        isLoadingPorts = true
        defer { isLoadingPorts = false }

        let commonPorts = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]
        let ip = device.ipAddress

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
