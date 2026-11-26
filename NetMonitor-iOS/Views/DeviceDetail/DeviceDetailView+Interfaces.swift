import NetMonitorCore
import SwiftUI

// MARK: - Interfaces (#594)

/// Device detail's Wake on LAN for a device with several interfaces: one packet to every
/// interface's MAC, sent from here, since the Wake on LAN tool takes one MAC.
struct WakeAllInterfacesButton: View {
    let viewModel: DeviceDetailViewModel

    var body: some View {
        Button {
            Task { await viewModel.wakeAllInterfaces() }
        } label: {
            HStack {
                Image(systemName: "power")
                    .foregroundStyle(Theme.Colors.success)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake on LAN")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let result = viewModel.wakeResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityIdentifier("deviceDetail_label_wakeResult")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("deviceDetail_button_wakeOnLan")
    }
}

/// The service usually on a port, for device detail's Services & Ports list.
enum WellKnownServices {
    static func name(for port: Int) -> String? {
        let wellKnownPorts: [Int: String] = [
            22: "SSH", 53: "DNS", 80: "HTTP", 443: "HTTPS",
            21: "FTP", 25: "SMTP", 110: "POP3", 143: "IMAP",
            445: "SMB", 548: "AFP", 631: "IPP", 3389: "RDP",
            5900: "VNC", 8080: "HTTP Proxy", 8443: "HTTPS Alt",
            3000: "Dev Server", 5353: "mDNS", 62078: "iSync"
        ]
        return wellKnownPorts[port]
    }
}
