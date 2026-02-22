import SwiftUI
import NetMonitorCore
import SwiftData
import AppKit
import Darwin

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Query(sort: \LocalDevice.lastSeen, order: .reverse) private var devices: [LocalDevice]

    @State private var selectedDevice: LocalDevice?
    @State private var searchText: String = ""
    @State private var filterOnlineOnly: Bool = false
    @State private var sortOrder: DeviceSortOrder = .lastSeen
    @State private var wolAction = WakeOnLanAction()
    @State private var availableNetworks: [NetworkProfile] = []
    @State private var selectedNetworkID: UUID?

    // Context menu action state
    @State private var deviceToPing: LocalDevice?
    @State private var deviceToScan: LocalDevice?

    enum DeviceSortOrder: String, CaseIterable {
        case lastSeen = "Last Seen"
        case name = "Name"
        case ipAddress = "IP Address"
        case status = "Status"

        var icon: String {
            switch self {
            case .lastSeen: return "clock"
            case .name: return "textformat"
            case .ipAddress: return "number"
            case .status: return "circle.fill"
            }
        }
    }

    var filteredDevices: [LocalDevice] {
        var result = devices.filter { $0.networkProfileID == activeProfileID }

        if filterOnlineOnly {
            result = result.filter { $0.status == .online }
        }

        if !searchText.isEmpty {
            result = result.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.ipAddress.contains(searchText) ||
                device.macAddress.localizedCaseInsensitiveContains(searchText) ||
                (device.vendor?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply sort order
        switch sortOrder {
        case .lastSeen:
            result.sort { $0.lastSeen > $1.lastSeen }
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .ipAddress:
            result.sort { compareIPAddresses($0.ipAddress, $1.ipAddress) }
        case .status:
            result.sort { ($0.status == .online ? 0 : 1) < ($1.status == .online ? 0 : 1) }
        }

        return result
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

    /// Compare IP addresses numerically (192.168.2.3 < 192.168.2.10)
    private func compareIPAddresses(_ a: String, _ b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<min(aParts.count, bParts.count) {
            if aParts[i] != bParts[i] { return aParts[i] < bParts[i] }
        }
        return aParts.count < bParts.count
    }

    var body: some View {
        HStack(spacing: 0) {
            // Device list
            VStack(spacing: 0) {
                deviceList
            }
            .frame(minWidth: 280, idealWidth: 350, maxWidth: 450)

            Divider()

            // Detail pane
            if let device = selectedDevice {
                DeviceDetailView(device: device)
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
        .navigationTitle("Devices")
        .toolbar {
            toolbarContent
        }
        .searchable(text: $searchText, prompt: "Search devices...")
        .accessibilityIdentifier("devices_search_field")
        .wakeOnLanAlert(wolAction)
        .sheet(item: $deviceToPing) { device in
            DevicePingSheet(device: device, isPresented: Binding(
                get: { deviceToPing != nil },
                set: { if !$0 { deviceToPing = nil } }
            ))
        }
        .sheet(item: $deviceToScan) { device in
            DevicePortScanSheet(device: device, isPresented: Binding(
                get: { deviceToScan != nil },
                set: { if !$0 { deviceToScan = nil } }
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkProfilesDidChange)) { _ in
            availableNetworks = coordinator?.networkProfileManager.profiles
                ?? NetworkProfileManager.detectActiveProfiles()
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        Group {
            if filteredDevices.isEmpty && coordinator?.isScanning != true {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network",
                    description: Text("Click Scan to discover devices on your network")
                )
                .accessibilityIdentifier("devices_label_empty")
            } else {
                List(filteredDevices, selection: $selectedDevice) { device in
                    DeviceRowView(device: device)
                        .tag(device)
                        .contextMenu {
                            deviceContextMenu(for: device)
                        }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("devices_list")
            }
        }
        .overlay {
            if coordinator?.isScanning == true {
                scanningOverlay
            }
        }
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
                .foregroundStyle(.secondary)

            Button("Stop") {
                coordinator?.stopScan()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("devices_button_stopScan")
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let profile = selectedNetwork {
                    coordinator?.scanNetwork(profile)
                } else {
                    coordinator?.startScan()
                }
            } label: {
                Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(coordinator?.isScanning == true)
            .accessibilityIdentifier("devices_button_scan")
        }

        ToolbarItem(placement: .automatic) {
            Picker("Network", selection: $selectedNetworkID) {
                Label("Auto", systemImage: "sparkles")
                    .tag(UUID?.none)
                ForEach(availableNetworks) { profile in
                    Label(profile.displayName, systemImage: profile.connectionType.iconName)
                        .tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("devices_picker_network")
            .onAppear {
                availableNetworks = coordinator?.networkProfileManager.profiles
                    ?? NetworkProfileManager.detectActiveProfiles()
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Label(order.rawValue, systemImage: order.icon)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("devices_menu_sort")
        }

        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $filterOnlineOnly) {
                Label("Online Only", systemImage: "circle.fill")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("devices_toggle_onlineOnly")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                clearDevices()
            } label: {
                Label("Clear List", systemImage: "trash")
            }
            .disabled(filteredDevices.isEmpty)
            .accessibilityIdentifier("devices_button_clear")
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                Text("\(filteredDevices.count)")
                    .fontWeight(.semibold)
                Text("devices")
                    .foregroundStyle(.secondary)

                if let lastScan = coordinator?.lastScanTime {
                    Text("· Last scan: \(lastScan, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func clearDevices() {
        selectedDevice = nil
        for device in filteredDevices {
            modelContext.delete(device)
        }
        try? modelContext.save()
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func deviceContextMenu(for device: LocalDevice) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.ipAddress, forType: .string)
        } label: {
            Label("Copy IP Address", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("devices_menu_copyIP")

        if !device.macAddress.isEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.macAddress, forType: .string)
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

        if !device.macAddress.isEmpty {
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
                selectedDevice = nil
            }
            modelContext.delete(device)
            try? modelContext.save()
        } label: {
            Label("Remove Device", systemImage: "trash")
        }
        .accessibilityIdentifier("devices_menu_remove")
    }
}

// MARK: - Helper Sheet Views

struct DevicePingSheet: View {
    let device: LocalDevice
    @Binding var isPresented: Bool

    @State private var pingResults: [String] = []
    @State private var isPinging = false
    @State private var pingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Ping \(device.displayName)", systemImage: "waveform.path")
                    .font(.headline)
                Spacer()
                Button {
                    stopPing()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Device info
            HStack {
                Text("Target:")
                    .foregroundStyle(.secondary)
                Text(device.ipAddress)
                    .fontDesign(.monospaced)
                if let hostname = device.hostname {
                    Text("(\(hostname))")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))

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
                .background(Color.black.opacity(0.2))
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
                        .foregroundStyle(.secondary)
                } else {
                    Text(pingResults.isEmpty ? "Ready to ping" : "Completed")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isPinging && !pingResults.isEmpty {
                    Button("Clear") {
                        pingResults.removeAll()
                    }
                }

                Button(isPinging ? "Stop" : "Run") {
                    if isPinging {
                        stopPing()
                    } else {
                        runPing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("devices_ping_button_run")
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .accessibilityIdentifier("devices_sheet_ping")
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
    let device: LocalDevice
    @Binding var isPresented: Bool

    @State private var portScanResults: [(port: Int, name: String, isOpen: Bool)] = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0.0
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Port Scan \(device.displayName)", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button {
                    stopPortScan()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Device info
            HStack {
                Text("Target:")
                    .foregroundStyle(.secondary)
                Text(device.ipAddress)
                    .fontDesign(.monospaced)
                if let hostname = device.hostname {
                    Text("(\(hostname))")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            Divider()

            // Progress
            if isScanning {
                VStack(spacing: 8) {
                    ProgressView(value: scanProgress)
                        .progressViewStyle(.linear)
                    Text("\(Int(scanProgress * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(result.isOpen ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(result.isOpen ? "Open" : "Closed")
                                    .foregroundStyle(result.isOpen ? .green : .secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(result.isOpen ? Color.green.opacity(0.1) : Color.clear)
                    }
                }
            }
            .background(Color.black.opacity(0.1))

            Divider()

            // Footer
            HStack {
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning ports...")
                        .foregroundStyle(.secondary)
                } else {
                    let openCount = portScanResults.filter { $0.isOpen }.count
                    Text(portScanResults.isEmpty ? "Ready to scan" : "\(openCount) open ports found")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isScanning && !portScanResults.isEmpty {
                    Button("Clear") {
                        portScanResults.removeAll()
                        scanProgress = 0.0
                    }
                }

                Button(isScanning ? "Stop" : "Scan") {
                    if isScanning {
                        stopPortScan()
                    } else {
                        runPortScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("devices_portScan_button_scan")
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .accessibilityIdentifier("devices_sheet_portScan")
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

#if DEBUG
#Preview {
    DevicesView()
        .modelContainer(PreviewContainer().container)
}
#endif
