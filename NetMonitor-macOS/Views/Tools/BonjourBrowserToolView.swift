//
//  BonjourBrowserToolView.swift
//  NetMonitor
//
//  Bonjour browser tool for discovering local network services.
//

import SwiftUI
import NetMonitorCore

struct BonjourBrowserToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var isScanning = false
    @State private var services: [BonjourService] = []
    @State private var selectedService: BonjourService?
    @State private var errorMessage: String?
    @State private var browseTask: Task<Void, Never>?

    @State private var discoveryService = BonjourDiscoveryService()

    /// Group services by type for display
    private var groupedServices: [(type: String, services: [BonjourService])] {
        let grouped = Dictionary(grouping: services) { $0.type }
        return grouped.map { (type: $0.key, services: $0.value) }
            .sorted { $0.type < $1.type }
    }

    var body: some View {
        ToolSheetContainer(
            title: "Bonjour Browser",
            iconName: "bonjour",
            closeAccessibilityID: "bonjour_button_close",
            minWidth: 600,
            minHeight: 500,
            headerTrailing: {
                Button {
                    startScan()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
                .accessibilityIdentifier("bonjour_button_refresh")
            },
            inputArea: { contentArea },
            footerContent: { footer }
        )
        .task {
            startScan()
        }
        .onDisappear {
            browseTask?.cancel()
            browseTask = nil
            discoveryService.stopDiscovery()
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        HSplitView {
            // Service list
            serviceList
                .frame(minWidth: 250)

            // Detail view
            detailView
                .frame(minWidth: 300)
        }
        .background(Color.black.opacity(0.2))
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if services.isEmpty && !isScanning {
                    Text("No services found")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(groupedServices, id: \.type) { group in
                        serviceGroupHeader(group.type)

                        ForEach(group.services) { service in
                            serviceRow(service)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func serviceGroupHeader(_ type: String) -> some View {
        HStack {
            Image(systemName: iconForServiceType(type))
                .foregroundStyle(accentColor)
            Text(friendlyServiceName(type))
                .font(.headline)
            Spacer()
            Text("\(groupedServices.first { $0.type == type }?.services.count ?? 0)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }

    private func serviceRow(_ service: BonjourService) -> some View {
        Button {
            selectedService = service
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let hostname = service.hostName {
                        Text(hostname)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let port = service.port {
                    Text(":\(port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedService?.id == service.id ? accentColor.opacity(0.2) : Color.clear)
        .accessibilityIdentifier("bonjour_row_\(service.id)")
    }

    private var detailView: some View {
        Group {
            if let service = selectedService {
                serviceDetailView(service)
            } else {
                Text("Select a service to view details")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func serviceDetailView(_ service: BonjourService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: iconForServiceType(service.type))
                        .font(.largeTitle)
                        .foregroundStyle(accentColor)

                    VStack(alignment: .leading) {
                        Text(service.name)
                            .font(.title2.bold())
                        Text(friendlyServiceName(service.type))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Connection info
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connection", systemImage: "network")
                        .font(.headline)

                    detailRow(label: "Hostname", value: service.hostName ?? "Unknown")

                    if let ip = service.addresses.first {
                        detailRow(label: "IP Address", value: ip)
                    }

                    if let port = service.port {
                        detailRow(label: "Port", value: String(port))
                    }

                    detailRow(label: "Type", value: service.type)
                    detailRow(label: "Domain", value: service.domain)
                }

                // TXT Records
                if !service.txtRecords.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("TXT Records", systemImage: "doc.text")
                            .font(.headline)

                        ForEach(service.txtRecords.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            detailRow(label: key, value: value)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning for services...")
                    .foregroundStyle(.secondary)
            } else if !services.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(services.count) service(s) found")
                    .foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage ?? "")
                    .foregroundStyle(.secondary)
            } else {
                Text("Discover Bonjour services on your network")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func startScan() {
        // Cancel any previous scan before starting a new one so the old
        // browseTask cannot call stopDiscovery() and sabotage the new session.
        browseTask?.cancel()
        browseTask = nil

        isScanning = true
        services.removeAll()
        selectedService = nil
        errorMessage = nil

        browseTask = Task { @MainActor in
            let stream = discoveryService.discoveryStream(serviceType: nil)
            services = []

            // Schedule a 10-second timeout. When it fires, stop the discovery
            // service so the stream finishes and unblocks the for-await below.
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                discoveryService.stopDiscovery()
            }

            // Iterate results until the stream finishes (either by timeout or
            // by the service's own 30-second auto-finish).
            for await service in stream {
                if !services.contains(where: { $0.id == service.id }) {
                    services.append(service)
                }
            }

            timeoutTask.cancel()

            // Only update UI state if this task was not cancelled (i.e. the
            // view is still visible and no newer scan was started).
            guard !Task.isCancelled else { return }
            discoveryService.stopDiscovery()
            isScanning = false
        }
    }

    // periphery:ignore
    private func stopScan() {
        browseTask?.cancel()
        browseTask = nil
        discoveryService.stopDiscovery()
        isScanning = false
    }

    // MARK: - Helpers

    private func iconForServiceType(_ type: String) -> String {
        switch type {
        case "_http._tcp", "_https._tcp":
            return "globe"
        case "_ssh._tcp", "_sftp._tcp":
            return "terminal"
        case "_smb._tcp", "_afp._tcp":
            return "folder"
        case "_airplay._tcp", "_raop._tcp":
            return "airplayaudio"
        case "_printer._tcp", "_ipp._tcp":
            return "printer"
        case "_scanner._tcp":
            return "scanner"
        case "_homekit._tcp", "_hap._tcp":
            return "house"
        case "_companion-link._tcp":
            return "applewatch"
        case "_sleep-proxy._udp":
            return "moon"
        default:
            return "bonjour"
        }
    }

    private func friendlyServiceName(_ type: String) -> String {
        switch type {
        case "_http._tcp": return "Web Server (HTTP)"
        case "_https._tcp": return "Web Server (HTTPS)"
        case "_ssh._tcp": return "SSH"
        case "_sftp._tcp": return "SFTP"
        case "_smb._tcp": return "SMB File Sharing"
        case "_afp._tcp": return "AFP File Sharing"
        case "_airplay._tcp": return "AirPlay"
        case "_raop._tcp": return "AirPlay Audio"
        case "_printer._tcp": return "Printer"
        case "_ipp._tcp": return "IPP Printer"
        case "_scanner._tcp": return "Scanner"
        case "_homekit._tcp": return "HomeKit"
        case "_hap._tcp": return "HomeKit Accessory"
        case "_companion-link._tcp": return "Companion Link"
        case "_sleep-proxy._udp": return "Sleep Proxy"
        default: return type
        }
    }
}

#Preview {
    BonjourBrowserToolView()
}
