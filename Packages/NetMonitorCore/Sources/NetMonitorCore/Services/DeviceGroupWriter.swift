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
///   (`references`) to the device's primary, before the save.
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
        /// The rows changed since the operation an undo would reverse (#594 PR2).
        case undoUnavailable
        /// An automatic grouping whose rows' models or makers name different devices (#619).
        case conflictingIdentity

        /// The refusal for two rows, whichever order they were found in.
        public static func excluded(between first: UUID, and second: UUID) -> Refusal {
            first.uuidString < second.uuidString ? .excluded(first, second) : .excluded(second, first)
        }
    }

    private let container: ModelContainer
    private let references: [any DeviceReferenceStore]
    private let save: @MainActor (ModelContext) throws -> Void
    /// Where the user's grouping actions report a device's presence changing (#619 verification):
    /// an offline device grouped into an online one comes back online, once.
    private let dispatcher: (any DeviceEventDispatcherProtocol)?

    public init(
        container: ModelContainer,
        references: [any DeviceReferenceStore] = [],
        dispatcher: (any DeviceEventDispatcherProtocol)? = nil,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.references = references
        self.dispatcher = dispatcher
        self.save = save
    }

    /// A writer on `context`'s container; it still works in its own context.
    public init(
        context: ModelContext,
        references: [any DeviceReferenceStore] = [],
        dispatcher: (any DeviceEventDispatcherProtocol)? = nil,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.init(container: context.container, references: references, dispatcher: dispatcher, save: save)
    }

    // MARK: Grouping

    /// Makes the rows (and every member of a group any of them is in) one device, and returns the
    /// group's ID. An existing group's ID and primary are kept; `primary` chooses one for a new
    /// group (else ``DeviceGroups/preferredPrimary(among:)``). Rows already in a group keep their
    /// `groupSource`; the others get `source`.
    @discardableResult
    public func group(_ rowIDs: [UUID], primary: UUID?, source: DeviceGroupSource) throws -> UUID {
        try committing { context in
            let (named, members) = try groupRows(rowIDs, in: context)
            return try Self.join(named, members: members, primary: primary, source: source)
        }
    }

    /// "Same device as…" (#594 PR2): groups the rows as the user said, and returns how to undo it.
    /// `primary` is the device the user is on: it keeps its group and its primary, and the rest are
    /// re-keyed to it with `groupSource = user`.
    /// With `overridingExclusions` (the user confirmed "You said these were different devices"),
    /// exactly the exclusions between the rows that would join are cleared first.
    public func groupForUser(_ rowIDs: [UUID], primary: UUID?, overridingExclusions: Bool = false) throws -> DeviceGroupUndo {
        try reporting { context, window in
            let (named, members) = try groupRows(rowIDs, in: context)
            window.watch(members)
            return try recording(members) {
                if overridingExclusions {
                    while let pair = DeviceGroups.excludedPair(in: members) {
                        if let lhs = members.first(where: { $0.id == pair.0 }), let rhs = members.first(where: { $0.id == pair.1 }) {
                            removeExclusion(lhs, rhs)
                        }
                    }
                }
                _ = try Self.join(named, members: members, primary: primary, source: .user, anchor: primary)
            }
        }
    }

    /// "Not the same device" with an undo (#594 PR2): ``ungroup(_:)``, recorded.
    public func ungroupForUser(_ rowID: UUID) throws -> DeviceGroupUndo {
        try reporting { context, window in
            let row = try self.row(rowID, in: context)
            let members = try row.deviceGroupID.map { try DeviceGroups.members(ofGroups: [$0], in: context) } ?? [row]
            window.watch(members)
            return try recording(members) { ungroupRow(row, others: members.filter { $0.id != row.id }) }
        }
    }

    /// Reverses exactly what `undo` recorded, when the rows it touched are still as that operation
    /// left them; otherwise refuses with ``Refusal/undoUnavailable`` and changes nothing.
    public func undo(_ undo: DeviceGroupUndo) throws {
        try reporting { context, window in
            let touched = try rows(Set(undo.after.keys), in: context)
            // The groups the operation left must still have exactly the members it left them.
            let groups = Set(undo.after.values.compactMap(\.groupID))
            let members = try DeviceGroups.members(ofGroups: groups, in: context)
            let expected = Set(undo.after.filter { $0.value.groupID != nil }.keys)
            guard Set(members.map(\.id)) == expected,
                  touched.count == undo.after.count,
                  touched.allSatisfy({ DeviceGroupUndo.Fields($0) == undo.after[$0.id] }),
                  undo.added.allSatisfy({ pair in pairExists(pair, in: touched) }),
                  undo.removed.allSatisfy({ pair in !pairExists(pair, in: touched) })
            else { throw Refusal.undoUnavailable }
            window.watch(touched)
            for row in touched {
                undo.before[row.id]?.apply(to: row)
            }
            let byID = Dictionary(touched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for pair in undo.added {
                if let lhs = byID[pair.first], let rhs = byID[pair.second] {
                    removeExclusion(lhs, rhs)
                }
            }
            for pair in undo.removed {
                if let lhs = byID[pair.first], let rhs = byID[pair.second] {
                    addExclusion(lhs, rhs)
                }
            }
        }
    }

    /// The named rows and every member of a group one of them is in.
    private func groupRows(_ rowIDs: [UUID], in context: ModelContext) throws -> (named: [LocalDevice], members: [LocalDevice]) {
        let named = try rows(Set(rowIDs), in: context)
        guard named.count == Set(rowIDs).count else { throw Refusal.notFound }
        var members = named
        for member in try DeviceGroups.members(ofGroups: Set(named.compactMap(\.deviceGroupID)), in: context)
            where !members.contains(where: { $0.id == member.id }) {
            members.append(member)
        }
        return (named, members)
    }

    /// Makes `members` (the named rows and the rest of their groups) one group: the one grouping
    /// mutation the writer and the reconciler's automatic grouping share. An existing group's ID and
    /// primary are kept; rows already in a group keep their `groupSource`. Throws a ``Refusal``
    /// before changing anything.
    @discardableResult
    static func join(
        _ named: [LocalDevice], members: [LocalDevice], primary: UUID?, source: DeviceGroupSource, anchor: UUID? = nil
    ) throws -> UUID {
        guard members.count >= 2 else { throw Refusal.tooFewMembers }
        guard Set(members.map(\.networkProfileID)).count <= 1 else { throw Refusal.differentNetworks }
        if let pair = DeviceGroups.excludedPair(in: members) {
            throw Refusal.excluded(between: pair.0, and: pair.1)
        }
        // Scan evidence never joins rows that say they're different hardware, checked again here
        // because an earlier join in the same scan can change a group (#619). The user may.
        if source == .bonjour, DeviceGrouping.hasConflictingIdentity(members) {
            throw Refusal.conflictingIdentity
        }
        // "Same device as…" (#594 PR2, v3 §3): the device the user is on keeps its group and its
        // primary; every row that joins it is re-keyed to it, as the user's grouping.
        if let anchor, let anchorRow = members.first(where: { $0.id == anchor }) {
            let groupID = anchorRow.deviceGroupID ?? UUID()
            let primaryID = anchorRow.groupPrimaryID.flatMap { id in members.first { $0.id == id }?.id } ?? anchorRow.id
            for member in members {
                if member.deviceGroupID != anchorRow.deviceGroupID || member.deviceGroupID == nil {
                    member.groupSource = source.rawValue
                }
                member.deviceGroupID = groupID
                member.groupPrimaryID = primaryID
            }
            return groupID
        }
        let existingGroups = named.compactMap(\.deviceGroupID)
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

    /// Takes the row out of its group ("Not the same device") and excludes it from each member
    /// that remains, so no later grouping puts it back without the user.
    public func ungroup(_ rowID: UUID) throws {
        try committing { context in
            let row = try self.row(rowID, in: context)
            guard let groupID = row.deviceGroupID else { return }
            try ungroupRow(row, others: DeviceGroups.members(ofGroups: [groupID], in: context).filter { $0.id != row.id })
        }
    }

    private func ungroupRow(_ row: LocalDevice, others: [LocalDevice]) {
        guard row.deviceGroupID != nil else { return }
        clearGroup(row)
        for other in others {
            addExclusion(row, other)
        }
        settle(others)
    }

    /// Runs `change` on `rows` and records their group fields and exclusions before and after.
    private func recording(_ rows: [LocalDevice], _ change: () throws -> Void) throws -> DeviceGroupUndo {
        let before = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, DeviceGroupUndo.Fields($0)) })
        let pairsBefore = pairs(in: rows)
        try change()
        let pairsAfter = pairs(in: rows)
        return DeviceGroupUndo(
            before: before, after: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, DeviceGroupUndo.Fields($0)) }),
            added: pairsAfter.subtracting(pairsBefore), removed: pairsBefore.subtracting(pairsAfter)
        )
    }

    private func pairs(in rows: [LocalDevice]) -> Set<DeviceGroupUndo.Pair> {
        let ids = Set(rows.map(\.id))
        return Set(rows.flatMap { row in (row.notSameAsIDs ?? []).filter(ids.contains).map { DeviceGroupUndo.Pair(row.id, $0) } })
    }

    private func pairExists(_ pair: DeviceGroupUndo.Pair, in rows: [LocalDevice]) -> Bool {
        rows.contains { $0.id == pair.first && ($0.notSameAsIDs ?? []).contains(pair.second) }
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
        try committing { context in
            let row = try self.row(rowID, in: context)
            let others = try row.deviceGroupID.map { id in
                try DeviceGroups.members(ofGroups: [id], in: context).filter { $0.id != row.id }
            } ?? []
            context.delete(row)
            // Before the save: pointing at the device's primary is safe even if the save then
            // fails (it is a live row of the same device), and no crash after the save can leave a
            // rule or a link naming a deleted row.
            if let primary = settle(others) {
                for store in references {
                    store.repoint(from: rowID, to: primary)
                }
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

    /// The rows a user action touches, compared before and after it (#619 verification).
    private final class EventWindow {
        private var rows: [LocalDevice] = []
        private var before: [DeviceEventReducer.RowState] = []

        /// Call once the rows are fetched, before anything changes.
        func watch(_ rows: [LocalDevice]) {
            self.rows = rows
            before = DeviceEventReducer.snapshot(rows)
        }

        var network: UUID? { rows.first?.networkProfileID }

        func events() -> [DeviceEvent] {
            rows.isEmpty ? [] : DeviceEventReducer.reduce(before: before, after: DeviceEventReducer.snapshot(rows), isBaseline: false)
        }
    }

    /// A user action: `change` watches the rows it touches, and once the save succeeds any device
    /// event between before and after is delivered (#619 verification). An offline device grouped
    /// into an online one comes back online, so its Timeline entry and its rule outage end; a row
    /// separated or undone keeps its saved presence, which is no event.
    private func reporting<Result>(_ change: (ModelContext, EventWindow) throws -> Result) throws -> Result {
        let window = EventWindow()
        var events: [DeviceEvent] = []
        let result = try committing { context in
            let result = try change(context, window)
            events = window.events()
            return result
        }
        dispatcher?.deliver(DeviceEventBatch(networkProfileID: window.network, scanDate: Date(), events: events))
        return result
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

/// How to reverse one "Same device as…" or "Not the same device" (#594 PR2): a session undo. It
/// restores exactly the group fields and the exclusion pairs that operation changed, and only while
/// the rows are still as it left them.
public struct DeviceGroupUndo: Sendable, Equatable {
    struct Fields: Sendable, Equatable {
        let groupID: UUID?
        let primaryID: UUID?
        let source: String?

        init(_ row: LocalDevice) {
            groupID = row.deviceGroupID
            primaryID = row.groupPrimaryID
            source = row.groupSource
        }

        func apply(to row: LocalDevice) {
            row.deviceGroupID = groupID
            row.groupPrimaryID = primaryID
            row.groupSource = source
        }
    }

    /// An exclusion between two rows, either way round.
    struct Pair: Sendable, Hashable {
        let first: UUID
        let second: UUID

        init(_ lhs: UUID, _ rhs: UUID) {
            (first, second) = lhs.uuidString < rhs.uuidString ? (lhs, rhs) : (rhs, lhs)
        }
    }

    let before: [UUID: Fields]
    let after: [UUID: Fields]
    let added: Set<Pair>
    let removed: Set<Pair>

    /// Whether the operation changed anything.
    public var isEmpty: Bool { before == after && added.isEmpty && removed.isEmpty }
}
