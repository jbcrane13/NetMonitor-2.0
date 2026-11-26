import SwiftUI
import SwiftData
import NetMonitorCore

/// Lists the port forwards the router opened through UPnP (#400). Read-only.
///
/// On iPhone the SSDP search needs the multicast entitlement (#381); until Apple grants
/// it, this shows "No router answered".
struct PortForwardsToolView: View {
    let env: AppEnvironment
    @State private var state = PortForwardsState()
    /// Saved rows that are one device's interfaces, named by their device (#594).
    @Query(filter: #Predicate<LocalDevice> { $0.deviceGroupID != nil }) private var groupedRows: [LocalDevice]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                controlSection
                resultsSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Port Forwards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear { load() }
        .onDisappear { state.cancel() }
        .accessibilityIdentifier("screen_portForwardsTool")
    }

    // MARK: - Control

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Router port forwards")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Ports apps and devices opened on your router through UPnP. Read-only.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ToolRunButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                isRunning: state.isLoading,
                stopTitle: "Reading…",
                action: { load() }
            )
            .disabled(state.isLoading)
            .accessibilityIdentifier("portForwards_button_refresh")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        switch state.phase {
        case .idle, .loading:
            ProgressView("Asking the router…")
                .accessibilityIdentifier("portForwards_label_loading")
        case .noLocalNetwork:
            message("No local network", detail: "Join a Wi-Fi network to read its router's port forwards.", id: "noNetwork")
        case .noGateway:
            message(
                "No router answered",
                detail: "Nothing answered the UPnP search. The router may have UPnP turned off.",
                id: "noGateway"
            )
        case .noWANService:
            message("Router doesn't list port forwards", detail: "No device offers the service that lists port forwards.", id: "noWANService")
        case let .loaded(rows, isComplete):
            VStack(spacing: 8) {
                if !isComplete {
                    Label("Couldn't read all forwards, so this list may be incomplete.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityIdentifier("portForwards_label_incomplete")
                }
                if rows.isEmpty, isComplete {
                    message("No port forwards", detail: "The router has no ports opened through UPnP.", id: "empty")
                }
                ForEach(rows) { row in
                    forwardRow(row)
                }
            }
        }
    }

    private func forwardRow(_ row: PortForwardRow) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(String(row.externalPort)) \(row.protocolName)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(row.isEnabled ? row.leaseText : "\(row.leaseText) (off)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text("→ \(row.clientLabel) : \(String(row.internalPort))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if !row.description.isEmpty {
                    Text(row.description)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("portForwards_row_\(row.id)")
    }

    private func message(_ title: String, detail: String, id: String) -> some View {
        GlassCard {
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("portForwards_label_\(id)")
    }

    // MARK: - Loading

    /// Each address's name: a device of several interfaces by its device's name at every address
    /// (#594), else the scan's.
    private func load() {
        var names = GroupedDeviceNames.byAddress(groupedRows)
        for device in env.deviceDiscovery.discoveredDevices where names[device.ipAddress] == nil {
            names[device.ipAddress] = device.displayName == device.ipAddress ? nil : device.displayName
        }
        state.load(interface: "en0", deviceNames: names)
    }
}
