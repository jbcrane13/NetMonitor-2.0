import SwiftUI
import NetMonitorCore

/// Dashboard card showing VPN connection status.
struct VPNInfoView: View {
    @State private var viewModel = VPNInfoViewModel()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                // Header
                HStack {
                    Image(systemName: "network.badge.shield.half.filled")
                        .foregroundStyle(Theme.Colors.info)
                    Text("VPN")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    StatusBadge(
                        status: viewModel.isVPNActive ? .online : .offline,
                        size: .small
                    )
                    .accessibilityIdentifier("dashboard_vpn_status")
                }

                if viewModel.isVPNActive {
                    vpnActiveContent
                } else {
                    vpnInactiveContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_vpn")
        .task {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var vpnActiveContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: Theme.Layout.smallCornerRadius) {
                ToolResultRow(label: "Interface", value: viewModel.interfaceName, icon: "cable.connector", isMonospaced: true)
                ToolResultRow(label: "Protocol", value: viewModel.protocolName, icon: "lock.shield")
                if !viewModel.connectionDuration.isEmpty {
                    ToolResultRow(label: "Duration", value: viewModel.connectionDuration, icon: "clock")
                }
            }
            .accessibilityIdentifier("vpnInfo_section_details")
        }
    }

    private var vpnInactiveContent: some View {
        Text("No VPN detected")
            .font(.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

#Preview {
    VPNInfoView()
        .padding()
        .themedBackground()
}
