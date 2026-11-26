import Foundation
import NetMonitorCore
import os
import SwiftData

/// The user's device-group actions on device detail (#594 PR2): accept or dismiss a suggestion,
/// "Same device as…", "Not the same device", and a session Undo (the toast's and Edit › Undo).
///
/// One model for the window, held above device detail: grouping changes the device's ID (a row's
/// becomes its group's), which recreates the detail view, so the toast and the undo receipt live
/// here. Choices and wording are Core's `DeviceGroupingChoices`, shared with the iPhone. Every
/// write goes through `DeviceGroupWriter`, which works in its own context; lists refresh on its
/// save. Views read state; the model fetches when detail shows a device, the picker opens, the
/// search changes, or an action changes the rows.
@MainActor @Observable final class DeviceGroupingViewModel {
    struct Toast: Equatable {
        let message: String
        let canUndo: Bool
    }

    /// A "Same device as…" the user said was a different device before: waiting for "Group them
    /// anyway?".
    struct PendingOverride: Equatable {
        let rowIDs: [UUID]
        let anchor: UUID
        let otherName: String
    }

    private(set) var toast: Toast?
    private(set) var pendingOverride: PendingOverride?
    private(set) var errorMessage: String?
    /// A row of the device the list should select after the last action or undo (any member's ID
    /// selects its device), with a counter so the same row selects again.
    private(set) var selection: (rowID: UUID, revision: Int)?
    /// "Same Bonjour name as X: same device?" for the device detail shows.
    private(set) var suggestions: [DeviceProjection] = []
    /// The picker's devices, for `search`.
    private(set) var candidates: [DeviceProjection] = []
    /// The picker's search; set through ``search(_:)``.
    private(set) var search = ""

    /// The device detail shows (its primary row) and where its rows are.
    private var shown: (primary: UUID, container: ModelContainer)?
    /// The network's rows read when the picker opened; the search filters them.
    private var pickerRows: [LocalDevice] = []
    private var last: (undo: DeviceGroupUndo, container: ModelContainer, anchor: UUID)?
    private weak var undoManager: UndoManager?
    private var toastTask: Task<Void, Never>?
    private let toastDuration: Duration
    private let now: () -> Date

    init(toastDuration: Duration = .seconds(10), now: @escaping () -> Date = Date.init) {
        self.toastDuration = toastDuration
        self.now = now
    }

    // MARK: - Reading

    /// Detail shows `device`: reads its suggestions.
    func show(_ device: DeviceProjection, in context: ModelContext) {
        shown = (device.primary.id, context.container)
        refreshSuggestions()
    }

    /// "Same device as…" opened for `device`: reads its network's rows once.
    func openPicker(for device: DeviceProjection, in context: ModelContext) {
        shown = (device.primary.id, context.container)
        pickerRows = Self.networkRows(of: device, in: context)
        search = ""
        refreshCandidates()
    }

    func search(_ text: String) {
        search = text
        refreshCandidates()
    }

    func closePicker() {
        pickerRows = []
        candidates = []
        search = ""
    }

    /// The network's rows of `device`, complete groups (a group lives on one network).
    static func networkRows(of device: DeviceProjection, in context: ModelContext) -> [LocalDevice] {
        let network = device.primary.networkProfileID
        let descriptor = network.map { id in FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == id }) }
            ?? FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == nil })
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.modelContext != nil && !$0.isDeleted }
    }

    /// The device `rowID` belongs to now, read in a fresh context on `container`.
    private static func device(of rowID: UUID, in context: ModelContext) -> DeviceProjection? {
        guard let row = try? context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == rowID })).first else { return nil }
        return try? DeviceGroups.device(of: row, in: context)
    }

    private func refreshSuggestions() {
        guard let shown else { return }
        let context = ModelContext(shown.container)
        guard let device = Self.device(of: shown.primary, in: context) else {
            suggestions = []
            return
        }
        suggestions = DeviceGroups.suggestions(for: device, among: Self.networkRows(of: device, in: context), now: now())
    }

    private func refreshCandidates() {
        guard let shown, !pickerRows.isEmpty, let device = DeviceGroups.project(pickerRows).first(where: { $0.contains(shown.primary) })
        else {
            candidates = []
            return
        }
        candidates = DeviceGroupingChoices.candidates(for: device, among: pickerRows, now: now(), search: search)
    }

    // MARK: - Actions

    /// "Same device" on a suggestion, or a pick in "Same device as…": `other` joins `device`, which
    /// keeps its group and primary (the anchor). An exclusion between them asks first
    /// (`pendingOverride`).
    func group(_ device: DeviceProjection, with other: DeviceProjection, in context: ModelContext, undoManager: UndoManager?) {
        self.undoManager = undoManager
        let rowIDs = DeviceGroupingChoices.rowIDs(joining: other, to: device)
        do {
            let undo = try DeviceGroupWriter(context: context).groupForUser(rowIDs, primary: device.primary.id)
            completed(undo, container: context.container, anchor: device.primary.id, message: DeviceGroupingChoices.grouped(with: other.displayName))
        } catch DeviceGroupWriter.Refusal.excluded {
            pendingOverride = PendingOverride(rowIDs: rowIDs, anchor: device.primary.id, otherName: other.displayName)
        } catch {
            fail("group", title: "Couldn't group the devices", error)
        }
    }

    /// "Group them anyway": the exclusions between the two devices are cleared and they group.
    func confirmOverride(in context: ModelContext) {
        guard let pending = pendingOverride else { return }
        pendingOverride = nil
        do {
            let undo = try DeviceGroupWriter(context: context).groupForUser(pending.rowIDs, primary: pending.anchor, overridingExclusions: true)
            completed(undo, container: context.container, anchor: pending.anchor, message: DeviceGroupingChoices.grouped(with: pending.otherName))
        } catch {
            fail("group anyway", title: "Couldn't group the devices", error)
        }
    }

    func cancelOverride() {
        pendingOverride = nil
    }

    /// "Not the same device" on a suggestion: the suggestion goes and doesn't come back.
    func dismissSuggestion(_ other: DeviceProjection, for device: DeviceProjection, in context: ModelContext) {
        do {
            try DeviceGroupWriter(context: context).exclude(device.primary.id, other.primary.id)
        } catch {
            fail("dismiss suggestion", title: "Couldn't dismiss the suggestion", error)
        }
        refreshSuggestions()
    }

    /// "Not the same device" on an interface of a group: it becomes a device of its own, excluded
    /// from the rest so no scan regroups it. The list keeps showing the device it left.
    func separate(_ member: LocalDevice, from device: DeviceProjection, in context: ModelContext, undoManager: UndoManager?) {
        self.undoManager = undoManager
        let address = member.ipAddress
        let remaining = device.members.first { $0.id != member.id }?.id ?? member.id
        do {
            let undo = try DeviceGroupWriter(context: context).ungroupForUser(member.id)
            completed(undo, container: context.container, anchor: remaining, message: DeviceGroupingChoices.separated(address))
        } catch {
            fail("separate", title: "Couldn't separate \(address)", error)
        }
    }

    /// The toast's Undo and Edit › Undo: reverses the last action, when its devices haven't
    /// changed since.
    func undo() {
        guard let last else { return }
        self.last = nil
        undoManager?.removeAllActions(withTarget: self)
        do {
            try DeviceGroupWriter(container: last.container).undo(last.undo)
            select(last.anchor)
            hideToast()
        } catch {
            show(Toast(message: DeviceGroupingChoices.undoUnavailable, canUndo: false))
            if !(error is DeviceGroupWriter.Refusal) {
                Logger.data.error("Undoing a device-group action failed: \(error)")
            }
        }
        refreshSuggestions()
    }

    func hideToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    static func actionName(for message: String) -> String {
        message.hasPrefix("Grouped") ? "Group Devices" : "Separate Device"
    }

    private func completed(_ undo: DeviceGroupUndo, container: ModelContainer, anchor: UUID, message: String) {
        select(anchor)
        // The shown device's ID may have changed (a row became a group): follow its anchor row.
        shown = (anchor, container)
        refreshSuggestions()
        guard !undo.isEmpty else { return }
        last = (undo, container, anchor)
        if let undoManager {
            let name = Self.actionName(for: message)
            undoManager.removeAllActions(withTarget: self)
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.undo() }
            }
            // Edit › Undo's action name ("Undo Group Devices") where the menu shows names.
            undoManager.setActionName(name)
        }
        show(Toast(message: message, canUndo: true))
    }

    private func select(_ rowID: UUID) {
        selection = (rowID, (selection?.revision ?? 0) + 1)
    }

    private func show(_ toast: Toast) {
        toastTask?.cancel()
        self.toast = toast
        let duration = toastDuration
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Logs the operation and the error, never an address or a name; a writer's refusal (the
    /// devices changed under the action) shows the fixed wording.
    private func fail(_ operation: String, title: String, _ error: any Error) {
        Logger.data.error("Device-group action \(operation, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
        // A refusal means the rows changed under the action; its own description says nothing useful.
        errorMessage = error is DeviceGroupWriter.Refusal ? "\(title). These devices changed since." : "\(title): \(error.localizedDescription)"
    }
}
