import SwiftUI
import NetMonitorCore

struct MacPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var connectionService = MacConnectionService.shared
    @State private var selectedMac: DiscoveredMac?
    @State private var manualHost: String = ""
    @State private var manualPort: String = .init(CompanionLink.defaultPort)
    @State private var showManualEntry: Bool = false
    /// The Mac the pairing screen opens for; a QR-only pairing uses `pairsFromQR`.
    @State private var macToPair: DiscoveredMac?
    @State private var pairsFromQR = false
    @State private var confirmsForget = false

    /// Called when a connection is established, passing the service and Mac name.
    var onConnected: ((MacConnectionService) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                pairedMacSection

                if let problem = connectionService.linkProblem {
                    Section {
                        Label(problem.message, systemImage: "lock.trianglebadge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.warning)
                            .accessibilityIdentifier("pairing_label_linkProblem")
                    }
                    .listRowBackground(Theme.Colors.glassBackground)
                }

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
                        .accessibilityIdentifier("pairing_label_searching")
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
                        .accessibilityIdentifier("pairing_label_empty")
                    } else {
                        ForEach(connectionService.discoveredMacs) { mac in
                            Button {
                                select(mac)
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
                                        Text(pairingBadge(for: mac))
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                            .accessibilityIdentifier("pairing_label_badge_\(mac.name)")
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
                            .accessibilityIdentifier("pairing_row_\(mac.name)")
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
                    .accessibilityIdentifier("pairing_toggle_manual")

                    if showManualEntry {
                        VStack(spacing: 12) {
                            TextField("Hostname or IP Address", text: $manualHost)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityIdentifier("macPairing_textfield_host")

                            TextField("Port", text: $manualPort)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityIdentifier("macPairing_textfield_port")

                            GlassButton(
                                title: "Connect",
                                icon: "link",
                                style: .primary,
                                size: .medium,
                                isFullWidth: true
                            ) {
                                connectManually()
                            }
                            .accessibilityIdentifier("pairing_button_manualConnect")
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
                                Button {
                                    onConnected?(connectionService)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.Colors.success)
                                        Text("Done")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.Colors.success)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                                .accessibilityIdentifier("pairing_button_done")
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
                    .accessibilityIdentifier("pairing_button_cancel")
                }
            }
            .navigationDestination(item: $macToPair) { mac in
                PairWithMacView(mac: mac)
            }
            .navigationDestination(isPresented: $pairsFromQR) {
                PairWithMacView(mac: nil)
            }
            .confirmationDialog(
                "Forget \(connectionService.pairedMac?.macName ?? "this Mac")?",
                isPresented: $confirmsForget,
                titleVisibility: .visible
            ) {
                Button("Forget This Mac", role: .destructive) {
                    Task { await connectionService.forgetMac() }
                }
                .accessibilityIdentifier("pairing_button_confirmForget")
            } message: {
                Text("This iPhone deletes its key and asks the Mac to remove it. You'll need to pair again.")
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

    // MARK: - Pairing (#590)

    private var pairedMacSection: some View {
        Section {
            if let paired = connectionService.pairedMac {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Theme.Colors.success)
                    Text("Paired with \(paired.macName)")
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("pairing_label_pairedMac")
                }
                Button(role: .destructive) {
                    confirmsForget = true
                } label: {
                    Text("Forget This Mac")
                }
                .accessibilityIdentifier("pairing_button_forget")
            }
            if let forgetError = connectionService.forgetError {
                Text(forgetError)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("pairing_label_forgetError")
            }
            if connectionService.pairedMac == nil {
                Button {
                    pairsFromQR = true
                } label: {
                    Label("Pair with QR Code", systemImage: "qrcode.viewfinder")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("pairing_button_pairQR")
            }
        } header: {
            Text("Pairing")
                .foregroundStyle(Theme.Colors.textSecondary)
        } footer: {
            Text("A paired iPhone and Mac talk over an encrypted link that other devices can't join.")
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .listRowBackground(Theme.Colors.glassBackground)
    }

    private func pairingBadge(for mac: DiscoveredMac) -> String {
        if !mac.isCurrent {
            return "Needs a NetMonitor update"
        }
        return connectionService.isPaired(with: mac) ? "Paired" : "Not paired"
    }

    private func select(_ mac: DiscoveredMac) {
        selectedMac = mac
        if !mac.isCurrent || connectionService.isPaired(with: mac) {
            connectionService.connect(to: mac)
        } else {
            macToPair = mac
        }
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
        let port = UInt16(manualPort) ?? CompanionLink.defaultPort
        connectionService.connectDirect(host: host, port: port)
    }
}

#Preview {
    MacPairingView()
}
