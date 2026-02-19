//
//  ConnectionInfoCard.swift
//  NetMonitor
//
//  SwiftUI card displaying current network connection information.
//

import SwiftUI
import NetMonitorCore

struct ConnectionInfoCard: View {
    @State private var connectionInfo: ConnectionInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var networkService = NetworkInfoService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: connectionIcon)
                    .foregroundStyle(.secondary)

                Text("Connection")
                    .font(.headline)

                Spacer()

                // Refresh Button
                Button(action: refreshConnection) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityIdentifier("connection_card_button_refresh")
            }

            Divider()

            // Connection Details
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)

                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unknown Network")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let info = connectionInfo {
                VStack(alignment: .leading, spacing: 8) {
                    // Network Name
                    HStack {
                        Text(networkDisplayName(info))
                            .font(.title3)
                            .fontWeight(.semibold)

                        Spacer()

                        // Connection Type Badge
                        Text(info.connectionType.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    // Signal Strength (WiFi only)
                    if let signal = info.signalStrength {
                        HStack(spacing: 6) {
                            signalBars(for: signal)

                            Text("\(signal) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let channel = info.channel {
                                Text("• Channel \(channel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Interface Name
                    Text("Interface: \(info.interfaceName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No network connection detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("connection_card")
        .task {
            await loadConnectionInfo()
        }
    }

    // MARK: - Actions

    private func refreshConnection() {
        Task {
            await loadConnectionInfo()
        }
    }

    private func loadConnectionInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            connectionInfo = try await networkService.getCurrentConnection()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helpers

    private var connectionIcon: String {
        guard let info = connectionInfo else {
            return "network.slash"
        }

        switch info.connectionType {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "cable.connector"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .none:
            return "network.slash"
        }
    }

    private func networkDisplayName(_ info: ConnectionInfo) -> String {
        if let ssid = info.ssid {
            return ssid
        }

        switch info.connectionType {
        case .wifi:
            return "WiFi Connected"
        case .ethernet:
            return "Ethernet Connected"
        case .cellular:
            return "Cellular Connected"
        case .none:
            return "Unknown Network"
        }
    }

    @ViewBuilder
    private func signalBars(for rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(barColor(for: rssi, bar: index))
                    .frame(width: 3, height: CGFloat((index + 1) * 3))
            }
        }
    }

    private func barColor(for rssi: Int, bar: Int) -> Color {
        let strength = signalStrength(rssi: rssi)

        if bar < strength {
            switch strength {
            case 4:
                return .green
            case 3:
                return .green
            case 2:
                return .orange
            default:
                return .red
            }
        } else {
            return .gray.opacity(0.3)
        }
    }

    private func signalStrength(rssi: Int) -> Int {
        if rssi >= -50 {
            return 4
        } else if rssi >= -60 {
            return 3
        } else if rssi >= -70 {
            return 2
        } else {
            return 1
        }
    }
}

// MARK: - Preview

#Preview {
    ConnectionInfoCard()
        .frame(width: 350)
        .padding()
}
