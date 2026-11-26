import Foundation
import SwiftData

/// A store outside SwiftData that keeps `LocalDevice` row IDs: rules, target links, Timeline
/// events (#594). When an interface is removed from a device that keeps other interfaces, its
/// references move to the device's primary, so a rule or a link never names a deleted row.
@MainActor
public protocol DeviceReferenceStore: AnyObject {
    /// Points every reference to the row `removed` at the row `device` instead.
    func repoint(from removed: UUID, to device: UUID)
}

/// The only code that writes the device-group fields (`deviceGroupID`, `groupPrimaryID`,
/// `groupSource`, `notSameAsIDs`) or deletes device rows (#594, design v3.1 §1, §4).
///
/// Every operation runs in its **own** `ModelContext` on the container: it fetches the rows it
/// touches by predicate, checks membership and every cross-member exclusion at commit, and saves
/// once; on a refusal or a failed save only that context is rolled back, so nobody's unsaved edits
/// are touched. Callers holding rows from another context refetch them afterwards (SwiftData
/// doesn't update another context's objects at once).
///
/// - A group is identified by its own `deviceGroupID`, which never changes. Its primary
///   (`groupPrimaryID`, the same on every member) changes only when the primary leaves:
///   ``DeviceGroups/preferredPrimary(among:)`` picks the next.
/// - A group has at least two members; one left with one member is cleared.
/// - Exclusions are kept per pair on both rows.
/// - Removing an interface that leaves the device other interfaces re-points its references
///   (`references`) to the device's primary, after the save.
@MainActor
public struct DeviceGroupWriter {
    public enum Refusal: Error, Equatable {
        /// A row isn't in the store.
        case notFound
        /// The rows are on different networks; a group lives on one.
        case differentNetworks
        /// The user said these two rows aren't the same device (in ``excluded(between:and:)`` order).
        case excluded(UUID, UUID)
        /// A group needs at least two rows.
        case tooFewMembers

        /// The refusal for two rows, whichever order they were found in.
        public static func excluded(between first: UUID, and second: UUID) -> Refusal {
            first.uuidString < second.uuidString ? .excluded(first, second) : .excluded(second, first)
        }
    }

    private let container: ModelContainer
    private let references: [any DeviceReferenceStore]
    private let save: @MainActor (ModelContext) throws -> Void

    public init(
        container: ModelContainer,
        references: [any DeviceReferenceStore] = [],
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.references = references
        self.save = save
    }

    /// A writer on `context`'s container; it still works in its own context.
    public init(
        context: ModelContext,
        references: [any DeviceReferenceStore] = [],
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.init(container: context.container, references: references, save: save)
    }

    // MARK: Grouping

    /// Makes the rows (and every member of a group any of them is in) one device, and returns the
    /// group's ID. An existing group's ID and primary are kept; `primary` chooses one for a new
    /// group (else ``DeviceGroups/preferredPrimary(among:)``). Rows already in a group keep their
    /// `groupSource`; the others get `source`.
    @discardableResult
    public func group(_ rowIDs: [UUID], primary: UUID?, source: DeviceGroupSource) throws -> UUID {
        try committing { context in
            let named = try rows(Set(rowIDs), in: context)
            guard named.count == Set(rowIDs).count else { throw Refusal.notFound }
            let existingGroups = named.compactMap(\.deviceGroupID)
            var members = named
            for member in try DeviceGroups.members(ofGroups: Set(existingGroups), in: context)
                where !members.contains(where: { $0.id == member.id }) {
                members.append(member)
            }
            guard members.count >= 2 else { throw Refusal.tooFewMembers }
            guard Set(members.map(\.networkProfileID)).count <= 1 else { throw Refusal.differentNetworks }
            if let pair = excludedPair(in: members) {
                throw Refusal.excluded(between: pair.0, and: pair.1)
            }
            let groupID = existingGroups.first ?? UUID()
            let existingPrimary = members.first { $0.deviceGroupID == groupID }?.groupPrimaryID
            let primaryID = existingPrimary.flatMap { id in members.first { $0.id == id }?.id }
                ?? primary.flatMap { id in members.first { $0.id == id }?.id }
                ?? DeviceGroups.preferredPrimary(among: members)?.id
            for member in members {
                if member.deviceGroupID == nil {
                    member.groupSource = source.rawValue
                }
                member.deviceGroupID = groupID
                member.groupPrimaryID = primaryID
            }
            return groupID
        }
    }

    /// Takes the row out of its group ("Not the same device") and excludes it from each member
    /// that remains, so no later grouping puts it back without the user.
    public func ungroup(_ rowID: UUID) throws {
        try committing { context in
            let row = try self.row(rowID, in: context)
            guard let groupID = row.deviceGroupID else { return }
            let others = try DeviceGroups.members(ofGroups: [groupID], in: context).filter { $0.id != row.id }
            clearGroup(row)
            for other in others {
                addExclusion(row, other)
            }
            settle(others)
        }
    }

    /// Records that the two rows aren't the same device, on both.
    public func exclude(_ first: UUID, _ second: UUID) throws {
        try committing { context in
            try addExclusion(row(first, in: context), row(second, in: context))
        }
    }

    /// Forgets that the two rows were said to be different devices, on both.
    public func include(_ first: UUID, _ second: UUID) throws {
        try committing { context in
            try removeExclusion(row(first, in: context), row(second, in: context))
        }
    }

    // MARK: Deleting

    /// "Remove this interface": deletes one member row. The group keeps its ID; a removed primary
    /// passes to the next member. When interfaces remain, the row's references move to the
    /// device's primary.
    public func removeInterface(_ rowID: UUID) throws {
        let primary: UUID? = try committing { context in
            let row = try self.row(rowID, in: context)
            let others = try row.deviceGroupID.map { id in
                try DeviceGroups.members(ofGroups: [id], in: context).filter { $0.id != row.id }
            } ?? []
            context.delete(row)
            return settle(others)
        }
        if let primary {
            for store in references {
                store.repoint(from: rowID, to: primary)
            }
        }
    }

    /// "Delete device": deletes every member of the device `id` names (a group's ID or any
    /// member's row ID).
    public func deleteDevice(_ id: UUID) throws {
        try committing { context in
            let members = try deviceMembers(id, in: context)
            guard !members.isEmpty else { throw Refusal.notFound }
            members.forEach(context.delete)
        }
    }

    /// "Delete device" for several devices at once (a list's Clear): every member of each, in one
    /// save. IDs that name no device are skipped.
    public func deleteDevices(_ ids: [UUID]) throws {
        try committing { context in
            for id in ids {
                try deviceMembers(id, in: context).forEach(context.delete)
            }
        }
    }

    /// Deletes every device row (Settings › clear saved devices).
    public func deleteAll() throws {
        try committing { context in
            try context.delete(model: LocalDevice.self)
        }
    }

    // MARK: Repair

    /// Makes every group consistent: one primary that is a member, the same on every member, and
    /// at least two members. Run at launch; cheap when nothing is wrong.
    public func repair() throws {
        try committing { context in
            let grouped = try context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID != nil }))
            for members in Dictionary(grouping: grouped, by: DeviceGroupKey.init).values {
                settle(members)
            }
        }
    }

    // MARK: Helpers

    /// Gives the remaining members one member primary and returns it, or clears a group of one
    /// (returning that row, the device that is left) or of none.
    @discardableResult
    private func settle(_ members: [LocalDevice]) -> UUID? {
        guard members.count > 1 else {
            members.forEach(clearGroup)
            return members.first?.id
        }
        let chosen = DeviceGroups.primary(of: members).id
        for member in members where member.groupPrimaryID != chosen {
            member.groupPrimaryID = chosen
        }
        return chosen
    }

    private func clearGroup(_ row: LocalDevice) {
        row.deviceGroupID = nil
        row.groupPrimaryID = nil
        row.groupSource = nil
    }

    private func excludedPair(in members: [LocalDevice]) -> (UUID, UUID)? {
        for member in members {
            for other in members where other !== member && (member.notSameAsIDs ?? []).contains(other.id) {
                return (member.id, other.id)
            }
        }
        return nil
    }

    private func addExclusion(_ lhs: LocalDevice, _ rhs: LocalDevice) {
        for (row, other) in [(lhs, rhs), (rhs, lhs)] where !(row.notSameAsIDs ?? []).contains(other.id) {
            row.notSameAsIDs = (row.notSameAsIDs ?? []) + [other.id]
        }
    }

    private func removeExclusion(_ lhs: LocalDevice, _ rhs: LocalDevice) {
        for (row, other) in [(lhs, rhs), (rhs, lhs)] {
            let kept = (row.notSameAsIDs ?? []).filter { $0 != other.id }
            row.notSameAsIDs = kept.isEmpty ? nil : kept
        }
    }

    private func rows(_ ids: Set<UUID>, in context: ModelContext) throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { ids.contains($0.id) }))
    }

    private func row(_ id: UUID, in context: ModelContext) throws -> LocalDevice {
        guard let row = try rows([id], in: context).first else { throw Refusal.notFound }
        return row
    }

    /// The rows of the device `id` names: a row and the rest of its group, or a group's members.
    private func deviceMembers(_ id: UUID, in context: ModelContext) throws -> [LocalDevice] {
        if let row = try rows([id], in: context).first {
            return try DeviceGroups.device(of: row, in: context).members
        }
        return try DeviceGroups.members(ofGroups: [id], in: context)
    }

    /// Runs `change` in a new context and saves it when anything changed; rolls back and rethrows
    /// on any failure.
    private func committing<Result>(_ change: (ModelContext) throws -> Result) throws -> Result {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try context.commitOrRollback(save: save) { try change(context) }
    }
}

public extension ModelContext {
    /// Runs `change`, then saves with `save` when anything changed; on any failure rolls this
    /// context back and rethrows, so nothing half-applied is saved later (#594). The one
    /// save-or-rollback both the writer and the launch passes use.
    func commitOrRollback<Result>(
        save: (ModelContext) throws -> Void = { try $0.save() }, _ change: () throws -> Result
    ) throws -> Result {
        do {
            let result = try change()
            if hasChanges {
                try save(self)
            }
            return result
        } catch {
            rollback()
            throw error
        }
    }
}
