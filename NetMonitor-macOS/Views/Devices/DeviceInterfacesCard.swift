import SwiftUI
import SwiftData
import NetMonitorCore

/// Device detail's Interfaces section (#594), shown for a device of two or more interfaces: each
/// member's address, MAC, last seen and open ports (a port stays on the interface it was measured
/// on), and Remove this interface. Used by both device detail views.
struct DeviceInterfacesCard: View {
    let device: DeviceProjection
    /// Deletes the member; called after the user confirmed when it holds user content.
    let onRemove: (LocalDevice) -> Void

    @Environment(\.presence) private var presence
    @State private var pendingRemoval: LocalDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Interfaces", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Divider()

            ForEach(device.members, id: \.id) { member in
                interfaceRow(member)
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_card_interfaces")
        .confirmationDialog(
            pendingRemoval.map { "Remove \($0.ipAddress) from this device?" } ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: {
                    if !$0 {
                        pendingRemoval = nil
                    }
                }
            ),
            presenting: pendingRemoval
        ) { member in
            Button("Remove Interface", role: .destructive) {
                onRemove(member)
            }
            .accessibilityIdentifier("deviceDetail_button_confirmRemoveInterface")
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(Self.removalMessage(for: member))
        }
    }

    private func interfaceRow(_ member: LocalDevice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.ipAddress)
                        .fontDesign(.monospaced)
                        .fontWeight(.medium)
                    if member.id == device.current.id {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(MacTheme.Colors.info.opacity(0.15))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(Capsule())
                    }
                }
                if !member.macAddress.isEmpty {
                    Text(member.macAddress)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                Text("Last seen \(presence.relativeLastSeen(member))")
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                Text(Self.portsText(member.openPorts))
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
            }

            Spacer()

            Button(role: .destructive) {
                if DeviceGroups.hasUserContent(member) {
                    pendingRemoval = member
                } else {
                    onRemove(member)
                }
            } label: {
                Label("Remove this interface", systemImage: "minus.circle")
            }
            .controlSize(.small)
            .help("Delete this interface's saved row; the device keeps its other interfaces")
            .accessibilityIdentifier("deviceDetail_button_removeInterface_\(member.ipAddress)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_interface_\(member.ipAddress)")
    }

    static func portsText(_ ports: [Int]?) -> String {
        let ports = Set(ports ?? []).sorted()
        return ports.isEmpty ? "No open ports" : "Open ports: " + ports.map(String.init).joined(separator: ", ")
    }

    /// What goes with the interface: "Its custom name “Office Mac”, notes and serial number are
    /// deleted with it."
    static func removalMessage(for member: LocalDevice) -> String {
        var parts: [String] = []
        if let name = member.customName, !name.isEmpty {
            parts.append("custom name “\(name)”")
        }
        if let notes = member.notes, !notes.isEmpty {
            parts.append("notes")
        }
        if let serial = member.serialNumber, !serial.isEmpty {
            parts.append("serial number")
        }
        let identity = member.identity
        if [identity.maker, identity.model].contains(where: { $0?.source == .userConfirmed }) {
            parts.append("confirmed maker and model")
        }
        guard !parts.isEmpty else { return "This interface's saved row is deleted." }
        let list = ListFormatter.localizedString(byJoining: parts)
        return "Its \(list) \(parts.count == 1 && parts[0] != "notes" ? "is" : "are") deleted with it."
    }
}

/// How a device detail finds its device's other interfaces (#594): a live query for the rows of
/// the row's group (or the row alone), projected on the row's network.
enum DeviceGroupMembers {
    static func query(for row: LocalDevice) -> Query<LocalDevice, [LocalDevice]> {
        let rowID = row.id
        if let groupID = row.deviceGroupID {
            return Query(filter: #Predicate<LocalDevice> { $0.deviceGroupID == groupID })
        }
        return Query(filter: #Predicate<LocalDevice> { $0.id == rowID })
    }

    /// The device `row` belongs to, from the query's `rows`.
    static func projection(of row: LocalDevice, rows: [LocalDevice]) -> DeviceProjection {
        var members = rows.filter { !$0.isDeleted && $0.networkProfileID == row.networkProfileID }
        if !row.isDeleted, !members.contains(where: { $0 === row }) {
            members.append(row)
        }
        return DeviceGroups.project(members).first { $0.contains(row.id) } ?? DeviceGroups.project([row])[0]
    }
}
