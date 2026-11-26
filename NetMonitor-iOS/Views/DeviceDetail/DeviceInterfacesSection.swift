import NetMonitorCore
import SwiftUI

/// Device detail's Interfaces section (#594), shown for a device with two or more interfaces
/// (rows grouped as one device): each member's address, MAC, last seen and open ports, which stay
/// on the interface they were found on. Another member's notes are edited on its row (the
/// primary's are the Notes section's), and each row offers "Remove this interface".
struct DeviceInterfacesSection: View {
    /// Every member, the current one first.
    let interfaces: [LocalDevice]
    /// The device's primary: its notes are the Notes section's.
    let primary: LocalDevice
    let presence: PresenceSnapshot
    /// Asks to remove a member; device detail confirms first when the member has user content.
    let onRemove: (LocalDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Interfaces")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_interfacesTitle")

            ForEach(Array(interfaces.enumerated()), id: \.element.id) { index, member in
                interfaceRow(member)
                if index < interfaces.count - 1 {
                    Divider().background(Theme.Colors.glassBorder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_section_interfaces")
    }

    private func key(_ member: LocalDevice) -> String {
        member.ipAddress.replacingOccurrences(of: ".", with: "_")
    }

    private func interfaceRow(_ member: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PresenceDot(freshness: presence.freshness(of: member))
                Text(member.ipAddress)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(presence.relativeLastSeen(member))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(presence.accessibilityText(member))
            .accessibilityIdentifier("deviceDetail_row_interface_\(key(member))")

            Text(member.formattedMacAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityIdentifier("deviceDetail_label_interfaceMAC_\(key(member))")

            if let ports = member.openPorts, !ports.isEmpty {
                Text("Open ports: \(ports.map(String.init).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("deviceDetail_label_interfacePorts_\(key(member))")
            }

            if member !== primary {
                TextField("Notes about this interface", text: Binding(
                    get: { member.notes ?? "" },
                    set: { member.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_textfield_interfaceNotes_\(key(member))")
            }

            Button(role: .destructive) {
                onRemove(member)
            } label: {
                Label("Remove this interface", systemImage: "minus.circle")
                    .font(.caption)
            }
            .accessibilityIdentifier("deviceDetail_button_removeInterface_\(key(member))")
        }
    }
}
