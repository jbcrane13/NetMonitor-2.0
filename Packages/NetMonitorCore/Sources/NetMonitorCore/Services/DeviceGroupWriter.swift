import Foundation
import SwiftData

/// The only code that writes the device-group fields (`deviceGroupID`, `groupPrimaryID`,
/// `groupSource`, `notSameAsIDs`) or deletes device rows (#594, design v3.1 §1, §4).
///
/// Every operation fetches the rows it touches freshly in `context`, checks membership and every
/// cross-member exclusion at commit, and saves once; on a refusal or a failed save the context is
/// rolled back and the error thrown, so nothing half-applied is saved later.
///
/// - A group is identified by its own `deviceGroupID`, which never changes. Its primary
///   (`groupPrimaryID`, the same on every member) changes only when the primary leaves:
///   ``DeviceGroups/preferredPrimary(among:)`` picks the next.
/// - A group left with one member is cleared.
/// - Exclusions are kept per pair on both rows.
@MainActor
public struct DeviceGroupWriter {
    public enum Refusal: Error, Equatable {
        /// A row isn't in the store.
        case notFound
        /// The rows are on different networks; a group lives on one.
        case differentNetworks
        /// The user said these two rows aren't the same device (in ``excluded(between:and:)`` order).
        case excluded(UUID, UUID)

        /// The refusal for two rows, whichever order they were found in.
        public static func excluded(between first: UUID, and second: UUID) -> Refusal {
            first.uuidString < second.uuidString ? .excluded(first, second) : .excluded(second, first)
        }
    }

    private let context: ModelContext
    private let save: @MainActor (ModelContext) throws -> Void

    public init(context: ModelContext, save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.save = save
    }

    // MARK: Grouping

    /// Makes the rows (and every member of a group any of them is in) one device, and returns the
    /// group's ID. An existing group's ID and primary are kept; `primary` chooses one for a new
    /// group (else ``DeviceGroups/preferredPrimary(among:)``). Rows already in a group keep their
    /// `groupSource`; the others get `source`.
    @discardableResult
    public func group(_ rowIDs: [UUID], primary: UUID?, source: DeviceGroupSource) throws -> UUID {
        try committing {
            let all = try fetchAll()
            let named = try rowIDs.map { id in
                guard let row = all.first(where: { $0.id == id }) else { throw Refusal.notFound }
                return row
            }
            let existingGroups = named.compactMap(\.deviceGroupID)
            let members = all.filter { row in named.contains { $0 === row } || row.deviceGroupID.map(existingGroups.contains) == true }
            guard Set(members.map(\.networkProfileID)).count <= 1 else { throw Refusal.differentNetworks }
            if let pair = excludedPair(in: members) {
                throw Refusal.excluded(between: pair.0, and: pair.1)
            }
            let groupID = existingGroups.first ?? UUID()
            let existingPrimary = existingGroups.first.flatMap { id in all.first { $0.deviceGroupID == id }?.groupPrimaryID }
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
        try committing {
            let all = try fetchAll()
            guard let row = all.first(where: { $0.id == rowID }) else { throw Refusal.notFound }
            guard let groupID = row.deviceGroupID else { return }
            let others = all.filter { $0.deviceGroupID == groupID && $0 !== row }
            clearGroup(row)
            for other in others {
                addExclusion(row, other)
            }
            settle(others)
        }
    }

    /// Records that the two rows aren't the same device, on both.
    public func exclude(_ first: UUID, _ second: UUID) throws {
        try committing {
            let (lhs, rhs) = try pair(first, second)
            addExclusion(lhs, rhs)
        }
    }

    /// Forgets that the two rows were said to be different devices, on both.
    public func include(_ first: UUID, _ second: UUID) throws {
        try committing {
            let (lhs, rhs) = try pair(first, second)
            removeExclusion(lhs, rhs)
        }
    }

    // MARK: Deleting

    /// "Remove this interface": deletes one member row. The group keeps its ID; a removed primary
    /// passes to the next member.
    public func removeInterface(_ rowID: UUID) throws {
        try committing {
            let all = try fetchAll()
            guard let row = all.first(where: { $0.id == rowID }) else { throw Refusal.notFound }
            let others = row.deviceGroupID.map { id in all.filter { $0.deviceGroupID == id && $0 !== row } } ?? []
            context.delete(row)
            settle(others)
        }
    }

    /// "Delete device": deletes every member of the device `id` names (a group's ID or any
    /// member's row ID).
    public func deleteDevice(_ id: UUID) throws {
        try committing {
            let all = try fetchAll()
            guard let device = DeviceGroupResolver(rows: all).device(for: id) else { throw Refusal.notFound }
            for member in device.members {
                context.delete(member)
            }
        }
    }

    /// Deletes every device row (Settings › clear saved devices).
    public func deleteAll() throws {
        try committing {
            try context.delete(model: LocalDevice.self)
        }
    }

    // MARK: Repair

    /// Makes every group consistent: one primary that is a member, the same on every member, and
    /// at least two members. Run at launch; cheap when nothing is wrong.
    public func repair() throws {
        try committing {
            let grouped = try context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID != nil }))
            for members in Dictionary(grouping: grouped, by: { GroupScope($0) }).values {
                settle(members)
            }
        }
    }

    // MARK: Helpers

    private struct GroupScope: Hashable {
        let groupID: UUID?
        let network: UUID?
        init(_ row: LocalDevice) {
            groupID = row.deviceGroupID
            network = row.networkProfileID
        }
    }

    /// Gives the remaining members one member primary, or clears a group of one.
    private func settle(_ members: [LocalDevice]) {
        guard members.count > 1 else {
            members.forEach(clearGroup)
            return
        }
        let chosen = DeviceGroups.primary(of: members).id
        for member in members where member.groupPrimaryID != chosen {
            member.groupPrimaryID = chosen
        }
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

    private func pair(_ first: UUID, _ second: UUID) throws -> (LocalDevice, LocalDevice) {
        let all = try fetchAll()
        guard let lhs = all.first(where: { $0.id == first }), let rhs = all.first(where: { $0.id == second }) else {
            throw Refusal.notFound
        }
        return (lhs, rhs)
    }

    private func fetchAll() throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>())
    }

    /// Runs `change`, then saves when anything changed; rolls back and rethrows on any failure.
    private func committing<Result>(_ change: () throws -> Result) throws -> Result {
        do {
            let result = try change()
            if context.hasChanges {
                try save(context)
            }
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
