import Foundation
import NetMonitorCore
import os
import SwiftData

/// The user's device-group actions on device detail (#594 PR2): accept or dismiss a suggestion,
/// "Same device as…", "Not the same device", and a session Undo (the toast's and Edit › Undo).
///
/// One model for the window, held above device detail: grouping changes the device's ID (a row's
/// becomes its group's), which recreates the detail view, so the toast and the undo receipt live
/// here. Every write goes through `DeviceGroupWriter`, which works in its own context; lists
/// refresh on its save.
@MainActor @Observable final class DeviceGroupingViewModel {
    struct Toast: Equatable {
        let message: String
        let canUndo: Bool
    }

    /// A "Same device as…" the user said was a different device before: waiting for "Group them
    /// anyway?".
    struct PendingOverride: Equatable {
        let rowIDs: [UUID]
        let primary: UUID
        let otherName: String
        let context: ModelContext

        static func == (lhs: PendingOverride, rhs: PendingOverride) -> Bool {
            lhs.rowIDs == rhs.rowIDs && lhs.primary == rhs.primary && lhs.otherName == rhs.otherName
        }
    }

    static let overrideQuestion = "You said these were different devices. Group them anyway?"
    static let undoUnavailableMessage = "Can't undo: these devices changed since."

    private(set) var toast: Toast?
    private(set) var pendingOverride: PendingOverride?
    private(set) var errorMessage: String?
    /// A row of the device the list should select after the last action or undo (any member's ID
    /// selects its device), with a counter so the same row selects again.
    private(set) var selection: (rowID: UUID, revision: Int)?

    private var last: (undo: DeviceGroupUndo, container: ModelContainer, anchor: UUID)?
    private weak var undoManager: UndoManager?
    private var toastTask: Task<Void, Never>?
    private let toastDuration: Duration

    init(toastDuration: Duration = .seconds(10)) {
        self.toastDuration = toastDuration
    }

    // MARK: - Reading

    /// The network's rows of `device`, complete groups (a group lives on one network).
    static func networkRows(of device: DeviceProjection, in context: ModelContext) -> [LocalDevice] {
        let network = device.primary.networkProfileID
        let descriptor = network.map { id in FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == id }) }
            ?? FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == nil })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.filter { $0.modelContext != nil && !$0.isDeleted }
    }

    /// "Same Bonjour name as X: same device?": Core's suggestions for `device` on its network.
    func suggestions(for device: DeviceProjection, in context: ModelContext, now: Date = Date()) -> [DeviceProjection] {
        DeviceGroups.suggestions(for: device, among: Self.networkRows(of: device, in: context), now: now)
    }

    /// The picker's devices: the other devices on `device`'s network, suggestions first, then the
    /// rest by name; `search` matches any interface's name, address or MAC.
    func candidates(for device: DeviceProjection, search: String, in context: ModelContext, now: Date = Date()) -> [DeviceProjection] {
        let rows = Self.networkRows(of: device, in: context)
        let suggested = DeviceGroups.suggestions(for: device, among: rows, now: now)
        let suggestedIDs = Set(suggested.map(\.id))
        let rest = DeviceGroups.project(rows)
            .filter { $0.id != device.id && !suggestedIDs.contains($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return (suggested + rest).filter { Self.matches($0, search) }
    }

    static func matches(_ device: DeviceProjection, _ search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let fields = [device.displayName] + device.members.flatMap { [$0.ipAddress, $0.macAddress, $0.hostname ?? "", $0.matchName ?? ""] }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Actions

    /// "Same device" on a suggestion, or a pick in "Same device as…": `other` joins `device`,
    /// which keeps its primary. An exclusion between them asks first (`pendingOverride`).
    func group(_ device: DeviceProjection, with other: DeviceProjection, in context: ModelContext, undoManager: UndoManager?) {
        self.undoManager = undoManager
        let rowIDs = [device.primary.id, other.primary.id]
        do {
            let undo = try DeviceGroupWriter(context: context).groupForUser(rowIDs, primary: device.primary.id)
            completed(undo, container: context.container, anchor: device.primary.id, message: "Grouped with \(other.displayName)")
        } catch DeviceGroupWriter.Refusal.excluded {
            pendingOverride = PendingOverride(rowIDs: rowIDs, primary: device.primary.id, otherName: other.displayName, context: context)
        } catch {
            fail("Couldn't group the devices", error)
        }
    }

    /// "Group them anyway": the exclusions between the two devices are cleared and they group.
    func confirmOverride() {
        guard let pending = pendingOverride else { return }
        pendingOverride = nil
        do {
            let undo = try DeviceGroupWriter(context: pending.context)
                .groupForUser(pending.rowIDs, primary: pending.primary, overridingExclusions: true)
            completed(undo, container: pending.context.container, anchor: pending.primary, message: "Grouped with \(pending.otherName)")
        } catch {
            fail("Couldn't group the devices", error)
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
            fail("Couldn't dismiss the suggestion", error)
        }
    }

    /// "Not the same device" on an interface of a group: it becomes a device of its own, excluded
    /// from the rest so no scan regroups it. The list keeps showing the device it left.
    func separate(_ member: LocalDevice, from device: DeviceProjection, in context: ModelContext, undoManager: UndoManager?) {
        self.undoManager = undoManager
        let address = member.ipAddress
        let remaining = device.members.first { $0.id != member.id }?.id ?? member.id
        do {
            let undo = try DeviceGroupWriter(context: context).ungroupForUser(member.id)
            completed(undo, container: context.container, anchor: remaining, message: "\(address) is a separate device")
        } catch {
            fail("Couldn't separate \(address)", error)
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
        } catch DeviceGroupWriter.Refusal.undoUnavailable {
            show(Toast(message: Self.undoUnavailableMessage, canUndo: false))
        } catch {
            fail("Couldn't undo", error)
        }
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

    private func completed(_ undo: DeviceGroupUndo, container: ModelContainer, anchor: UUID, message: String) {
        select(anchor)
        guard !undo.isEmpty else { return }
        last = (undo, container, anchor)
        undoManager?.removeAllActions(withTarget: self)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.undo() }
        }
        undoManager?.setActionName(message.hasPrefix("Grouped") ? "Group Devices" : "Separate Device")
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

    private func fail(_ what: String, _ error: any Error) {
        Logger.data.error("\(what, privacy: .public): \(error)")
        errorMessage = "\(what): \(error.localizedDescription)"
    }
}
