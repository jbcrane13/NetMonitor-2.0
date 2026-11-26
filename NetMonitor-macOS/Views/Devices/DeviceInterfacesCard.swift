import SwiftUI
import SwiftData
import NetMonitorCore
import os

/// Device detail's Interfaces section (#594), shown for a device of two or more interfaces: each
/// member's address, MAC, last seen and open ports (a port stays on the interface it was measured
/// on), "Not the same device" (#594 PR2), the label "Grouped by Bonjour name" on an interface
/// that joined automatically, and Remove this interface. Used by both device detail views.
struct DeviceInterfacesCard: View {
    let device: DeviceProjection
    /// Deletes the member; called after the user confirmed when it holds user content or a rule
    /// or target names it. A thrown error is shown.
    let onRemove: @MainActor (LocalDevice) async throws -> Void

    @Environment(\.presence) private var presence
    @Environment(AlertRuleStore.self) private var ruleStore: AlertRuleStore?
    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query private var targets: [NetworkTarget]
    @State private var pendingRemoval: LocalDevice?
    @State private var removalError: String?

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
                remove(member)
            }
            .accessibilityIdentifier("deviceDetail_button_confirmRemoveInterface")
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(DeviceGroups.removalMessage(for: member, references: references(to: member)))
        }
        .alert(
            "Couldn't Remove the Interface",
            isPresented: Binding(get: { removalError != nil }, set: {
                if !$0 {
                    removalError = nil
                }
            })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalError ?? "")
        }
    }

    private func remove(_ member: LocalDevice) {
        let address = member.ipAddress
        Task {
            do {
                try await onRemove(member)
            } catch {
                removalError = "\(address) wasn't removed: \(error.localizedDescription)"
            }
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
                if let label = Self.groupLabel(for: member) {
                    Label(label, systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                        .help("This interface answered for the same Bonjour name as the device in one scan")
                        .accessibilityIdentifier("deviceDetail_label_groupedByBonjour_\(member.ipAddress)")
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

            Button {
                // The member becomes a device of its own, with an undo toast.
                grouping?.separate(member, from: device, in: modelContext, undoManager: undoManager)
            } label: {
                Label("Not the same device", systemImage: "link.badge.minus")
            }
            .controlSize(.small)
            .help("This interface is another device: show it on its own")
            .accessibilityIdentifier("deviceDetail_button_notSameDevice_\(member.ipAddress)")

            Button(role: .destructive) {
                if DeviceGroups.hasUserContent(member) || !references(to: member).isEmpty {
                    pendingRemoval = member
                } else {
                    remove(member)
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

    /// "Grouped by Bonjour name" for a member that joined automatically (spoofing is accepted,
    /// with this label); nil otherwise.
    static func groupLabel(for member: LocalDevice) -> String? {
        member.groupSource == DeviceGroupSource.bonjour.rawValue ? "Grouped by Bonjour name" : nil
    }

    static func portsText(_ ports: [Int]?) -> String {
        let ports = Set(ports ?? []).sorted()
        return ports.isEmpty ? "No open ports" : "Open ports: " + ports.map(String.init).joined(separator: ", ")
    }

    /// The rules and monitoring targets that name the member's row (v3.1 §1).
    private func references(to member: LocalDevice) -> [String] {
        ruleStore?.references(to: member.id, targets: targets) ?? []
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
/// drop it first (`willRemove`), and the row is deleted through `DeviceGroupWriter` after the main
/// actor has yielded, once they have redrawn. The writer re-points the row's rules, target links
/// and Timeline entries to the device's primary.
enum InterfaceRemoval {
    /// Posted with the row's ID (`object`) before it is deleted.
    static let willRemove = Notification.Name("netmonitor.deviceInterfaceWillBeRemoved")
    /// Posted with the row's ID when the deletion failed, so lists that dropped it reload.
    static let didFail = Notification.Name("netmonitor.deviceInterfaceRemovalFailed")

    /// Removes the row; the task's error is the writer's.
    @MainActor
    @discardableResult
    static func remove(_ rowID: UUID, in context: ModelContext, ruleStore: AlertRuleStore?) -> Task<Void, any Error> {
        NotificationCenter.default.post(name: willRemove, object: rowID)
        let references: [any DeviceReferenceStore] = (ruleStore.map { [$0] } ?? []) + [NetworkEventService.shared]
        return Task { @MainActor in
            await Task.yield()
            do {
                try DeviceGroupWriter(context: context, references: references).removeInterface(rowID)
            } catch {
                Logger.data.error("Failed to remove interface: \(error)")
                NotificationCenter.default.post(name: didFail, object: rowID)
                throw error
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
