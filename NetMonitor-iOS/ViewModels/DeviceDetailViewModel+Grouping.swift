import Foundation
import NetMonitorCore
import SwiftData

// MARK: - Grouping interfaces as one device (#594 PR2)

/// What the undo toast offers after the user grouped or separated devices (#594 PR2): the
/// message, and how to reverse exactly that action. Undo covers the user's own actions only.
struct DeviceGroupingToast: Equatable {
    let message: String
    /// The receipt `DeviceGroupWriter.undo` reverses; nil once there is nothing to undo.
    let undo: DeviceGroupUndo?
    /// The row detail stays open on after an undo.
    let anchor: UUID
}

/// Device detail's grouping state (#594 PR2), written only by the view model's grouping actions
/// below, so views read it and never set it.
@MainActor
@Observable
final class DeviceGroupingState {
    /// Devices with an interface that answered for the same strong Bonjour name recently: the
    /// banner's "Same Bonjour name as X: same device?".
    fileprivate(set) var suggestions: [DeviceProjection] = []
    /// The device a grouping waits on while the user confirms overriding their "Not the same device".
    fileprivate(set) var pendingOverride: DeviceProjection?
    /// The undo toast after the user's last grouping action.
    fileprivate(set) var toast: DeviceGroupingToast?
}

extension DeviceDetailViewModel {
    /// "Same device as…" (#594 PR2): this network's other devices, suggestions first, filtered by
    /// `query` (`DeviceGroupingChoices`: name, and each interface's address, MAC and names).
    func sameDeviceCandidates(matching query: String = "") -> [DeviceProjection] {
        guard let projection else { return [] }
        return DeviceGroupingChoices.candidates(for: projection, among: networkRows(), now: clock(), search: query)
    }

    /// Whether `device` is among the suggestions, for the picker's section.
    func isSuggested(_ device: DeviceProjection) -> Bool {
        grouping.suggestions.contains { $0.id == device.id }
    }

    /// "Grouped by Bonjour name" for an interface the scan grouped automatically, else nil.
    func groupLabel(for member: LocalDevice) -> String? {
        DeviceGroupingChoices.label(for: member)
    }

    /// "Same device" on a suggestion, or a pick in "Same device as…": groups the two devices, with the
    /// device shown here keeping its primary. When the user said earlier that two of their interfaces
    /// are different devices, asks first (``DeviceGroupingState/pendingOverride``) unless `overridingExclusions`.
    func groupWith(_ other: DeviceProjection, overridingExclusions: Bool = false) {
        guard let projection, let modelContext else { return }
        // The shown device anchors the group: it keeps its group ID and its primary.
        let anchor = projection.primary.id
        saveContext()
        do {
            let undo = try writer(modelContext).groupForUser(
                DeviceGroupingChoices.rowIDs(joining: other, to: projection), primary: anchor, overridingExclusions: overridingExclusions
            )
            grouping.pendingOverride = nil
            grouping.toast = DeviceGroupingToast(message: DeviceGroupingChoices.grouped(with: other.displayName), undo: undo, anchor: anchor)
        } catch DeviceGroupWriter.Refusal.excluded {
            grouping.pendingOverride = other
            return
        } catch {
            self.error = "These devices couldn't be grouped. Try again."
            return
        }
        reloadDevice(anchor)
    }

    /// The user confirmed "You said these were different devices. Group them anyway?".
    func confirmGroupOverride() {
        guard let other = grouping.pendingOverride else { return }
        groupWith(other, overridingExclusions: true)
    }

    func cancelGroupOverride() {
        grouping.pendingOverride = nil
    }

    /// "Not the same device" on a suggestion: the two devices are recorded as different, so the
    /// suggestion goes and doesn't come back.
    func dismissGroupSuggestion(_ other: DeviceProjection) {
        guard let projection, let modelContext else { return }
        saveContext()
        do {
            try writer(modelContext).exclude(projection.primary.id, other.primary.id)
        } catch {
            self.error = "That couldn't be saved. Try again."
            return
        }
        reloadDevice(projection.primary.id)
    }

    /// "Not the same device" on an interface: it becomes a device of its own, with an undo. Detail
    /// stays on the interfaces that remain.
    func separateInterface(_ member: LocalDevice) {
        guard let modelContext, let projection, projection.isGroup,
              let anchor = projection.members.first(where: { $0.id != member.id })?.id
        else { return }
        prepareForLeaving(member)
        do {
            let undo = try writer(modelContext).ungroupForUser(member.id)
            grouping.toast = DeviceGroupingToast(message: DeviceGroupingChoices.separated(member.ipAddress), undo: undo, anchor: anchor)
        } catch {
            self.error = "The interface couldn't be separated. Try again."
            return
        }
        reloadDevice(anchor)
        startSuggestion()
    }

    /// The toast's Undo: reverses the last grouping action, or says why it can't.
    func undoGrouping() {
        guard let toast = grouping.toast, let undo = toast.undo, let modelContext else { return }
        saveContext()
        do {
            try writer(modelContext).undo(undo)
            grouping.toast = nil
        } catch DeviceGroupWriter.Refusal.undoUnavailable {
            grouping.toast = DeviceGroupingToast(message: DeviceGroupingChoices.undoUnavailable, undo: nil, anchor: toast.anchor)
            return
        } catch {
            self.error = "That couldn't be undone. Try again."
            return
        }
        reloadDevice(toast.anchor)
    }

    func dismissGroupingToast() {
        grouping.toast = nil
    }

    /// The suggestions for the shown device, from its network's rows (complete groups) as of now.
    func refreshGroupSuggestions() {
        guard let projection else {
            grouping.suggestions = []
            return
        }
        grouping.suggestions = DeviceGroups.suggestions(for: projection, among: networkRows(), now: clock())
    }

    /// Every row on the shown device's network, so each group is complete.
    private func networkRows() -> [LocalDevice] {
        guard let modelContext, let network = device.map({ $0.networkProfileID }) else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == network }))) ?? []
    }

    private func writer(_ context: ModelContext) -> DeviceGroupWriter {
        DeviceGroupWriter(context: context, references: references)
    }

    /// Shows the device `anchor` is a member of, read again after the writer saved in its own context.
    private func reloadDevice(_ anchor: UUID) {
        guard let modelContext else { return }
        showDevice(of: Self.row(named: anchor, in: modelContext))
    }
}
