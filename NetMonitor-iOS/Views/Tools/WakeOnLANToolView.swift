import SwiftUI
import NetMonitorCore

/// Wake on LAN tool view for waking devices remotely
struct WakeOnLANToolView: View {
    let initialMacAddress: String?
    @State private var viewModel: WakeOnLANToolViewModel

    init(initialMacAddress: String? = nil) {
        self.initialMacAddress = initialMacAddress
        self._viewModel = State(initialValue: WakeOnLANToolViewModel(initialMacAddress: initialMacAddress))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                inputSection
                controlSection
                resultSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Wake on LAN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_wolTool")
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Device")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            // MAC Address input
            VStack(alignment: .leading, spacing: 4) {
                ToolInputField(
                    text: $viewModel.macAddress,
                    placeholder: "Enter MAC address (e.g., AA:BB:CC:DD:EE:FF)",
                    icon: "network",
                    autocapitalization: .characters,
                    accessibilityID: "wol_input_mac",
                    onSubmit: {
                        if viewModel.canSend {
                            Task { await viewModel.sendWakePacket() }
                        }
                    }
                )

                if !viewModel.macAddress.isEmpty {
                    HStack {
                        if viewModel.isValidMACAddress {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.success)
                            Text("Valid MAC address")
                                .foregroundStyle(Theme.Colors.success)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.error)
                            Text("Invalid MAC address format")
                                .foregroundStyle(Theme.Colors.error)
                        }
                    }
                    .font(.caption)
                    .padding(.leading, 4)
                }
            }

            // Broadcast address
            VStack(alignment: .leading, spacing: 4) {
                Text("Broadcast Address")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                ToolInputField(
                    text: $viewModel.broadcastAddress,
                    placeholder: "255.255.255.255",
                    icon: "antenna.radiowaves.left.and.right",
                    keyboardType: .numbersAndPunctuation,
                    accessibilityID: "wol_input_broadcast"
                )

                Text("Usually 255.255.255.255 for local network")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        ToolRunButton(
            title: "Send Wake Packet",
            icon: "power",
            isRunning: viewModel.isSending,
            stopTitle: "Sending...",
            action: {
                Task { await viewModel.sendWakePacket() }
            }
        )
        .disabled(!viewModel.canSend)
        .accessibilityIdentifier("wol_button_send")
    }

    // MARK: - Result Section

    @ViewBuilder
    private var resultSection: some View {
        if let error = viewModel.errorMessage {
            GlassCard {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.error)

                    VStack(alignment: .leading) {
                        Text("Failed to send")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }

                    Spacer()
                }
            }
            .accessibilityIdentifier("wol_error")
        }

        if let result = viewModel.lastResult, result.success {
            GlassCard {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.success)

                    VStack(alignment: .leading) {
                        Text("Wake packet sent!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Magic packet sent to \(viewModel.formattedMACAddress)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()
                }
            }
            .accessibilityIdentifier("wol_success")
        }

        // Info card
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.info)
                    Text("How it works")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Text("Wake on LAN sends a \"magic packet\" containing the target device's MAC address. The device must support WOL and have it enabled in BIOS/firmware settings.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("wol_info")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WakeOnLANToolView()
    }
}
