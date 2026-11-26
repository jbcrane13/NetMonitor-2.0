import NetMonitorCore
import SwiftUI

// MARK: - Interfaces (#594)

extension DeviceDetailView {
    /// The device's state: the best member's.
    var freshness: PresenceFreshness {
        if let projection = viewModel.projection {
            return presence.freshness(of: projection)
        }
        return viewModel.device.map { presence.freshness(of: $0) } ?? .offline
    }

    /// The latest member's last sighting.
    func lastSeen(_ device: LocalDevice) -> Date {
        viewModel.projection?.lastSeen ?? device.lastSeen
    }

    /// The earliest member's first sighting.
    var firstSeen: Date {
        viewModel.members.map(\.firstSeen).min() ?? viewModel.device?.firstSeen ?? Date()
    }

    func currentMAC(_ device: LocalDevice) -> String {
        let mac = viewModel.current?.macAddress ?? device.macAddress
        return mac.isEmpty ? "—" : mac
    }

    /// Removes a member at once, or after a confirmation naming what goes with it.
    func requestRemoval(_ member: LocalDevice) {
        if viewModel.userContent(of: member).isEmpty {
            viewModel.removeInterface(member)
        } else {
            removingInterface = member
        }
    }

    var isConfirmingRemoval: Binding<Bool> {
        Binding(
            get: { removingInterface != nil },
            set: { isPresented in
                if !isPresented {
                    removingInterface = nil
                }
            }
        )
    }

    func removalMessage(_ member: LocalDevice) -> String {
        "This deletes \(member.ipAddress) from this device, with \(ListFormatter.localizedString(byJoining: viewModel.userContent(of: member)))."
    }

    var removalTitle: String {
        "Remove \(removingInterface?.ipAddress ?? "this interface")?"
    }

    /// Wake on LAN to every interface's MAC, from here: the tool takes one MAC.
    var wakeAllButton: some View {
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

    /// The service usually on `port`, for the Services & Ports list.
    func wellKnownServiceName(for port: Int) -> String? {
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
