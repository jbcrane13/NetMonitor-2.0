//
//  PortForwardsToolView.swift
//  NetMonitor
//
//  Lists the port forwards the router opened through UPnP (#400). Read-only.
//

import SwiftUI
import SwiftData
import NetMonitorCore

struct PortForwardsToolView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @Environment(\.modelContext) private var modelContext
    @Query(LocalDeviceQueries.recents()) private var devices: [LocalDevice]
    @State private var state = PortForwardsState()

    var body: some View {
        ToolSheetContainer(
            title: "Port Forwards",
            iconName: NetworkTool.portForwards.iconName,
            closeAccessibilityID: "portForwards_button_close",
            minWidth: 680,
            minHeight: 420,
            headerTrailing: {
                Button {
                    load()
                } label: {
                    Label(state.isLoading ? "Reading…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .accessibilityIdentifier("portForwards_button_refresh")
            },
            inputArea: { EmptyView() },
            outputArea: { content },
            footerContent: { footer }
        )
        .onAppear { load() }
        .onDisappear { state.cancel() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Asking the router for its port forwards…")
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("portForwards_label_loading")
        case .noLocalNetwork:
            message("No local network", detail: "Connect to a network to read its router's port forwards.", id: "noNetwork")
        case .noGateway:
            message(
                "No router answered",
                detail: "Nothing on this network answered the UPnP search. "
                    + "The router may have UPnP turned off, which means apps can't open ports on it.",
                id: "noGateway"
            )
        case .noWANService:
            message(
                "Router doesn't list port forwards",
                detail: "Devices answered the UPnP search, but none offers the service that lists port forwards.",
                id: "noWANService"
            )
        case let .loaded(rows, isComplete):
            VStack(alignment: .leading, spacing: 8) {
                if !isComplete {
                    Label("Couldn't read all forwards, so this list may be incomplete.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacTheme.Colors.warning)
                        .accessibilityIdentifier("portForwards_label_incomplete")
                }
                if rows.isEmpty, isComplete {
                    message("No port forwards", detail: "The router has no ports opened through UPnP.", id: "empty")
                } else {
                    table(rows)
                }
            }
        }
    }

    private func table(_ rows: [PortForwardRow]) -> some View {
        Table(rows) {
            TableColumn("External") { row in
                Text("\(String(row.externalPort)) \(row.protocolName)")
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("portForwards_row_\(row.id)")
            }
            .width(min: 90, ideal: 100)
            TableColumn("Device") { row in
                Text(row.clientLabel)
            }
            TableColumn("Internal port") { row in
                Text(String(row.internalPort))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 80, ideal: 90)
            TableColumn("Description") { row in
                Text(row.description.isEmpty ? "—" : row.description)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            TableColumn("Lease") { row in
                Text(row.isEnabled ? row.leaseText : "\(row.leaseText) (off)")
            }
            .width(min: 80, ideal: 100)
        }
        .accessibilityIdentifier("portForwards_table_forwards")
    }

    private func message(_ title: String, detail: String, id: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("portForwards_label_\(id)")
    }

    private var footer: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.white.opacity(0.5))
            Text("Read-only. Apps and devices open these through UPnP; check any you don't recognize in the router's settings.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Loading

    private func load() {
        // The Mac's own interface, not the last scanned network's (#441).
        let interface = profileManager?.localProfile?.interfaceName ?? "en0"
        // Every interface's address names its device (#594).
        let names = ChangeDigestBuilder.deviceNames(LocalDeviceQueries.completed(devices, in: modelContext))
        state.load(interface: interface, deviceNames: names)
    }
}

#Preview {
    PortForwardsToolView()
}
