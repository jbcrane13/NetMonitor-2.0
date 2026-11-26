import SwiftUI
import SwiftData
import NetMonitorCore
import os

/// Device detail's Interfaces section (#594), shown for a device of two or more interfaces: each
/// member's address, MAC, last seen and open ports (a port stays on the interface it was measured
/// on), and Remove this interface. Used by both device detail views.
struct DeviceInterfacesCard: View {
    let device: DeviceProjection
    /// Deletes the member; called after the user confirmed when it holds user content.
    let onRemove: (LocalDevice) -> Void

    @Environment(\.presence) private var presence
    @Environment(\.modelContext) private var modelContext
    @Environment(AlertRuleStore.self) private var ruleStore: AlertRuleStore?
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
            Text(Self.removalMessage(for: member, references: references(to: member)))
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
                if DeviceGroups.hasUserContent(member) || !references(to: member).isEmpty {
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
        .accessibilityIdentifier("deviceDetail_row_interface_\(member.ipAddress)")
    }

    static func portsText(_ ports: [Int]?) -> String {
        let ports = Set(ports ?? []).sorted()
        return ports.isEmpty ? "No open ports" : "Open ports: " + ports.map(String.init).joined(separator: ", ")
    }

    /// The rules and monitoring targets that name the member's row (v3.1 §1).
    private func references(to member: LocalDevice) -> [String] {
        InterfaceRemoval.references(to: member.id, rules: ruleStore?.rules ?? [], in: modelContext) { ruleStore?.device(forTarget: $0) }
    }

    /// The confirmation's text: "This deletes 192.168.77.61 with its custom name and its notes. The
    /// rule ‘Studio down’ names this interface and won't find it after." The user-content wording is
    /// Core's (`DeviceGroups.userContent(of:)`), shared with iOS.
    static func removalMessage(for member: LocalDevice, references: [String]) -> String {
        let content = DeviceGroups.userContent(of: member)
        var text = "This deletes \(member.ipAddress)"
        text += content.isEmpty ? "." : " with " + ListFormatter.localizedString(byJoining: content) + "."
        if !references.isEmpty {
            let named = ListFormatter.localizedString(byJoining: references)
            let verb = references.count == 1 ? "names" : "name"
            text += " " + named.prefix(1).uppercased() + named.dropFirst() + " \(verb) this interface and won't find it after."
        }
        return text
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
        let live: (LocalDevice) -> Bool = { $0.modelContext != nil && !$0.isDeleted }
        var members = rows.filter { live($0) && $0.networkProfileID == row.networkProfileID }
        if live(row), !members.contains(where: { $0 === row }) {
            members.append(row)
        }
        return DeviceGroups.project(members).first { $0.contains(row.id) } ?? DeviceGroups.project([row])[0]
    }
}

/// Remove this interface (#594), in two steps so no view draws a deleted row: lists holding rows
/// drop it first (`willRemove`), and the row is deleted through `DeviceGroupWriter` on the next
/// turn of the main run loop, once they have redrawn.
enum InterfaceRemoval {
    /// Posted with the row's ID (`object`) before it is deleted.
    static let willRemove = Notification.Name("netmonitor.deviceInterfaceWillBeRemoved")

    /// "the rule ‘Studio down’", "the monitoring target ‘Studio’": each rule whose device is the row
    /// and each target a rule linked to it.
    @MainActor
    static func references(
        to rowID: UUID, rules: [AlertRule], in context: ModelContext, linkedDevice: (UUID) -> UUID?
    ) -> [String] {
        let ruleNames = rules.filter { $0.conditions.deviceID == rowID }.map { "the rule ‘\($0.name)’" }
        let targets = (try? context.fetch(FetchDescriptor<NetworkTarget>())) ?? []
        let targetNames = targets.filter { linkedDevice($0.id) == rowID }.map { "the monitoring target ‘\($0.name)’" }
        return ruleNames + targetNames
    }

    @MainActor
    static func remove(_ rowID: UUID, in context: ModelContext) {
        NotificationCenter.default.post(name: willRemove, object: rowID)
        DispatchQueue.main.async {
            do {
                try DeviceGroupWriter(context: context).removeInterface(rowID)
            } catch {
                Logger.data.error("Failed to remove interface: \(error)")
            }
        }
    }
}

extension LocalDevice {
    /// The serial number device detail shows on the primary (#561), when one is set.
    var shownSerial: String? {
        serialNumber.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }
}
