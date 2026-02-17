import SwiftUI
import NetMonitorCore

struct ConnectionSettingsSection: View {
    let connectionService: MacConnectionService
    @Binding var showPairingSheet: Bool
    var onDisconnect: (() -> Void)?

    var body: some View {
        Section {
            // Connection Status Row
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    if let macName = connectionService.connectedMacName,
                       connectionService.connectionState.isConnected == true {
                        Text(macName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.success)
                    } else if case .connecting = connectionService.connectionState {
                        Text("Connecting…")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Establishing connection")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Text("No Mac Connected")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Standalone mode")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Spacer()

                StatusDot(
                    status: connectionService.connectionState.isConnected == true ? .online : .offline,
                    animated: connectionService.connectionState.isConnected == true
                )
            }
            .accessibilityIdentifier("settings_row_connectionStatus")

            // Connect / Disconnect Button
            if connectionService.connectionState.isConnected == true {
                Button {
                    onDisconnect?()
                } label: {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(Theme.Colors.error)
                        Text("Disconnect")
                            .foregroundStyle(Theme.Colors.error)
                        Spacer()
                    }
                }
                .accessibilityIdentifier("settings_button_disconnect")
            } else {
                Button {
                    showPairingSheet = true
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Connect to Mac")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .accessibilityIdentifier("settings_button_connectMac")
            }

            // Last Connected Timestamp
            if let lastStatus = connectionService.lastStatusUpdate {
                HStack {
                    Text("Monitoring")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(lastStatus.isMonitoring ? "Active" : "Paused")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(lastStatus.isMonitoring ? Theme.Colors.success : Theme.Colors.warning)
                }
                .accessibilityIdentifier("settings_row_monitoringStatus")

                HStack {
                    Text("Targets")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("\(lastStatus.onlineTargets) online, \(lastStatus.offlineTargets) offline")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("settings_row_targetCounts")
            }
        } header: {
            Text("Mac Companion")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .listRowBackground(Theme.Colors.glassBackground)
    }

    // MARK: - Computed

    private var statusIcon: String {
        switch connectionService.connectionState {
        case .connected: return "desktopcomputer"
        case .connecting, .browsing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        case .disconnected: return "desktopcomputer"
        }
    }

    private var statusColor: Color {
        switch connectionService.connectionState {
        case .connected: return Theme.Colors.success
        case .connecting, .browsing: return Theme.Colors.accent
        case .error: return Theme.Colors.error
        case .disconnected: return Theme.Colors.textTertiary
        }
    }
}

#Preview {
    List {
        ConnectionSettingsSection(
            connectionService: .shared,
            showPairingSheet: .constant(false)
        )
    }
    .scrollContentBackground(.hidden)
    .themedBackground()
}
