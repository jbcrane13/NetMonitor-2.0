import SwiftUI
import NetMonitorCore

struct MacPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var connectionService = MacConnectionService.shared
    @State private var selectedMac: DiscoveredMac?
    @State private var manualHost: String = ""
    @State private var manualPort: String = "8849"
    @State private var showManualEntry: Bool = false

    /// Called when a connection is established, passing the service and Mac name.
    var onConnected: ((MacConnectionService) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Discovered Macs
                Section {
                    if connectionService.isBrowsing && connectionService.discoveredMacs.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                            Text("Searching for NetMonitor Macs…")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                        .accessibilityIdentifier("pairing_searching")
                    } else if connectionService.discoveredMacs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("No Macs Found")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Make sure NetMonitor is running on your Mac and both devices are on the same network.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .accessibilityIdentifier("pairing_empty")
                    } else {
                        ForEach(connectionService.discoveredMacs) { mac in
                            Button {
                                selectedMac = mac
                                connectionService.connect(to: mac)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                        .font(.title2)
                                        .foregroundStyle(Theme.Colors.accent)
                                        .frame(width: 36)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mac.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        Text("NetMonitor Companion")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }

                                    Spacer()

                                    if selectedMac?.id == mac.id {
                                        connectionStateIndicator
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pairing_mac_\(mac.name)")
                        }
                    }
                } header: {
                    Text("Discovered Macs")
                        .foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    Text("NetMonitor automatically discovers Macs running the companion service on your local network.")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .listRowBackground(Theme.Colors.glassBackground)

                // MARK: - Manual Connection
                Section {
                    Button {
                        withAnimation {
                            showManualEntry.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Enter Address Manually")
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: showManualEntry ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("pairing_manual_toggle")

                    if showManualEntry {
                        VStack(spacing: 12) {
                            TextField("Hostname or IP Address", text: $manualHost)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityIdentifier("pairing_manual_host")

                            TextField("Port", text: $manualPort)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityIdentifier("pairing_manual_port")

                            GlassButton(
                                title: "Connect",
                                icon: "link",
                                style: .primary,
                                size: .medium,
                                isFullWidth: true
                            ) {
                                connectManually()
                            }
                            .accessibilityIdentifier("pairing_manual_connect")
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Manual Connection")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .listRowBackground(Theme.Colors.glassBackground)

                // MARK: - Connection Status
                if connectionService.connectionState != .disconnected {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                connectionStateIcon
                                Text(connectionService.connectionState.displayText)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }

                            if case .error(let msg) = connectionService.connectionState {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.error)
                            }

                            if connectionService.connectionState.isConnected {
                                GlassButton(
                                    title: "Done",
                                    icon: "checkmark",
                                    style: .success,
                                    size: .medium,
                                    isFullWidth: true
                                ) {
                                    onConnected?(connectionService)
                                    dismiss()
                                }
                                .accessibilityIdentifier("pairing_done")
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Status")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowBackground(Theme.Colors.glassBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Connect to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        connectionService.disconnect()
                        connectionService.stopBrowsing()
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityIdentifier("pairing_cancel")
                }
            }
            .onAppear {
                connectionService.startBrowsing()
            }
            .onDisappear {
                connectionService.stopBrowsing()
            }
        }
        .accessibilityIdentifier("screen_macPairing")
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStateIndicator: some View {
        switch connectionService.connectionState {
        case .connecting, .browsing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                .scaleEffect(0.8)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.error)
        case .disconnected:
            EmptyView()
        }
    }

    @ViewBuilder
    private var connectionStateIcon: some View {
        switch connectionService.connectionState {
        case .connecting, .browsing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                .scaleEffect(0.7)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.error)
        case .disconnected:
            Image(systemName: "circle")
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func connectManually() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        let port = UInt16(manualPort) ?? 8849
        connectionService.connectDirect(host: host, port: port)
    }
}

#Preview {
    MacPairingView()
}
