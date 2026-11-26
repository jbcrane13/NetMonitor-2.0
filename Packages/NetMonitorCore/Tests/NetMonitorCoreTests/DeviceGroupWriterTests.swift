import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 (design v3.1 §1, §4): the only code that writes the group fields or deletes rows. Every
/// operation works in its own context: it fetches the rows freshly, checks them at commit and saves
/// once, or rolls back. The tests read results in a fresh context, as callers must.
@Suite("Device group writer", .serialized)
@MainActor
struct DeviceGroupWriterTests {
    let home = UUID()
    private let container: ModelContainer
    private let context: ModelContext
    private let writer: DeviceGroupWriter

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        writer = DeviceGroupWriter(context: context)
    }

    @discardableResult
    func row(_ ip: String, notes: String? = nil, firstSeen: TimeInterval = 0, network: UUID? = nil) throws -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", notes: notes, networkProfileID: network ?? home)
        row.firstSeen = Date(timeIntervalSince1970: 1_800_000_000 + firstSeen)
        context.insert(row)
        try context.save()
        return row
    }

    /// Every row as the store has it now (a fresh context, not the main context's cached objects).
    func all() throws -> [LocalDevice] {
        try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
    }

    /// `row` as the store has it now.
    func fresh(_ row: LocalDevice) throws -> LocalDevice {
        let id = row.id
        return try #require(try ModelContext(container).fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == id })).first)
    }

    @Test("Grouping mints a group ID, sets the primary on every member and records the source")
    func groups() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        for member in try [fresh(alpha), fresh(bravo)] {
            #expect(member.deviceGroupID == id)
            #expect(member.groupPrimaryID == alpha.id)
            #expect(member.groupSource == "user")
        }
        #expect(try DeviceGroups.project(all()).count == 1)
    }

    @Test("Joining a row to a grouped row keeps the group's ID and primary")
    func joinsExistingGroup() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.41")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        #expect(try writer.group([charlie.id, bravo.id], primary: nil, source: .bonjour) == id)
        let joined = try fresh(charlie)
        #expect(joined.deviceGroupID == id && joined.groupPrimaryID == alpha.id && joined.groupSource == "bonjour")
        #expect(try fresh(bravo).groupSource == "user", "an existing member's source stays")
    }

    @Test("Excluded pairs, other networks and unknown rows are refused, and nothing changes")
    func refuses() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.50", network: UUID())
        try writer.exclude(alpha.id, bravo.id)
        #expect(throws: DeviceGroupWriter.Refusal.excluded(between: alpha.id, and: bravo.id)) {
            try writer.group([alpha.id, bravo.id], primary: nil, source: .user)
        }
        #expect(throws: DeviceGroupWriter.Refusal.differentNetworks) { try writer.group([alpha.id, charlie.id], primary: nil, source: .user) }
        #expect(throws: DeviceGroupWriter.Refusal.notFound) { try writer.group([alpha.id, UUID()], primary: nil, source: .user) }
        #expect(try all().allSatisfy { $0.deviceGroupID == nil })
    }

    @Test("An exclusion against any member of the other group refuses the union")
    func groupWideExclusion() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.50")
        _ = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        try writer.exclude(bravo.id, charlie.id)
        #expect(throws: DeviceGroupWriter.Refusal.excluded(between: charlie.id, and: bravo.id)) {
            try writer.group([alpha.id, charlie.id], primary: nil, source: .user)
        }
    }

    @Test("Exclusions are added and removed per pair, on both rows")
    func exclusionsPerPair() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.50")
        try writer.exclude(alpha.id, bravo.id)
        try writer.exclude(alpha.id, charlie.id)
        try writer.exclude(alpha.id, bravo.id)
        #expect(try Set(fresh(alpha).notSameAsIDs ?? []) == [bravo.id, charlie.id])
        #expect(try fresh(bravo).notSameAsIDs == [alpha.id])
        try writer.include(alpha.id, bravo.id)
        #expect(try fresh(alpha).notSameAsIDs == [charlie.id])
        #expect(try fresh(bravo).notSameAsIDs == nil)
    }

    @Test("Ungrouping a member excludes it from the rest; a group of one is cleared")
    func ungroups() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        _ = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        try writer.ungroup(bravo.id)
        for member in try [fresh(alpha), fresh(bravo)] {
            #expect(member.deviceGroupID == nil && member.groupPrimaryID == nil && member.groupSource == nil)
        }
        #expect(try fresh(alpha).notSameAsIDs == [bravo.id])
        #expect(try fresh(bravo).notSameAsIDs == [alpha.id])
    }

    @Test("Removing the primary interface re-keys the group to user content, then the earliest first seen; the group ID stays")
    func removingPrimaryReKeys() throws {
        let alpha = try row("10.0.0.10", firstSeen: 0)
        let bravo = try row("10.0.0.40", firstSeen: 100)
        let charlie = try row("10.0.0.41", notes: "spare NIC", firstSeen: 200)
        let id = try writer.group([alpha.id, bravo.id, charlie.id], primary: alpha.id, source: .user)
        try writer.removeInterface(alpha.id)
        #expect(try all().count == 2)
        let (left, spare) = try (fresh(bravo), fresh(charlie))
        #expect(left.deviceGroupID == id && spare.deviceGroupID == id)
        #expect(left.groupPrimaryID == charlie.id && spare.groupPrimaryID == charlie.id)
        try writer.removeInterface(charlie.id)
        let last = try fresh(bravo)
        #expect(last.deviceGroupID == nil && last.groupPrimaryID == nil, "one member left: not a group")
    }

    @Test("Deleting a device deletes every member, and nothing else")
    func deletesDevice() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), other = try row("10.0.0.50")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        try writer.deleteDevice(id)
        #expect(try all().map(\.id) == [other.id])
        try writer.deleteDevice(other.id)
        #expect(try all().isEmpty)
    }

    @Test("Deleting several devices deletes every member of each in one save, once each")
    func deletesSeveralDevices() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.50"), kept = try row("10.0.0.60")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        var saves = 0
        let counting = DeviceGroupWriter(context: context, save: { saves += 1
            try $0.save()
        })
        try counting.deleteDevices([id, bravo.id, charlie.id, UUID()])
        #expect(try all().map(\.id) == [kept.id])
        #expect(saves == 1)
    }

    @Test("A row's user content is listed in the words a confirmation uses")
    func userContentWording() throws {
        let plain = try row("10.0.0.10")
        #expect(DeviceGroups.userContent(of: plain).isEmpty && !DeviceGroups.hasUserContent(plain))
        let noted = try row("10.0.0.40", notes: "desk")
        noted.customName = "Mac"
        noted.identity = DeviceIdentity(
            model: IdentityValue("Mac16,10", source: .userConfirmed), serial: IdentityValue("C02", source: .userConfirmed)
        )
        #expect(DeviceGroups.userContent(of: noted) == ["its custom name", "its notes", "its serial number", "the maker and model you confirmed"])
    }

    @Test("Repair gives a group with a stale primary a member primary, and dissolves a group of one")
    func repairs() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40", firstSeen: 100), lone = try row("10.0.0.50")
        let id = UUID()
        for member in [alpha, bravo] {
            member.deviceGroupID = id
            member.groupPrimaryID = UUID()
        }
        lone.deviceGroupID = UUID()
        lone.groupPrimaryID = lone.id
        try context.save()
        try writer.repair()
        #expect(try fresh(alpha).groupPrimaryID == alpha.id)
        #expect(try fresh(bravo).groupPrimaryID == alpha.id)
        let single = try fresh(lone)
        #expect(single.deviceGroupID == nil && single.groupPrimaryID == nil)
    }

    @Test("A failed save rolls back and throws")
    func failedSave() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        struct SaveFailed: Error {}
        let failing = DeviceGroupWriter(context: context, save: { _ in throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try failing.group([alpha.id, bravo.id], primary: nil, source: .user) }
        #expect(try fresh(alpha).deviceGroupID == nil)
        #expect(try fresh(bravo).deviceGroupID == nil)
    }

    // MARK: Review round (#615)

    @Test("A group needs two rows: one row alone is refused")
    func refusesAGroupOfOne() throws {
        let alpha = try row("10.0.0.10")
        #expect(throws: DeviceGroupWriter.Refusal.tooFewMembers) { try writer.group([alpha.id], primary: nil, source: .user) }
        #expect(try fresh(alpha).deviceGroupID == nil)
    }

    @Test("A refused operation leaves another context's unsaved edit alone")
    func refusalKeepsUnsavedEdits() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        try writer.exclude(alpha.id, bravo.id)
        alpha.customName = "Draft name, not saved yet"
        #expect(throws: DeviceGroupWriter.Refusal.self) { try writer.group([alpha.id, bravo.id], primary: nil, source: .user) }
        #expect(context.hasChanges)
        #expect(alpha.customName == "Draft name, not saved yet")
    }

    @Test("Removing an interface moves its references to the device's primary, only while interfaces remain")
    func removalRepointsReferences() throws {
        let primary = try row("10.0.0.10", notes: "Mac mini"), wifi = try row("10.0.0.40"), other = try row("10.0.0.50")
        let spare = try row("10.0.0.41")
        _ = try writer.group([primary.id, wifi.id, spare.id], primary: primary.id, source: .user)
        let rules = RecordingReferences()
        let referencing = DeviceGroupWriter(container: container, references: [rules])
        try referencing.removeInterface(primary.id)
        let newPrimary = try #require(try fresh(wifi).groupPrimaryID)
        #expect(rules.moves == [Move(from: primary.id, to: newPrimary)])
        try referencing.removeInterface(other.id)
        #expect(rules.moves.count == 1, "a device of one row leaves nothing to point at")
    }

    @Test("Deleting a primary that a rule, a Timeline entry and an open detail name keeps them on the device")
    func deletingThePrimaryKeepsReferences() throws {
        let primary = try row("10.0.0.10", notes: "Mac mini"), wifi = try row("10.0.0.40")
        let id = try writer.group([primary.id, wifi.id], primary: primary.id, source: .user)
        let rules = RecordingReferences(holding: [primary.id])
        let events = NetworkEventService()
        events.log(NetworkEvent(type: .deviceJoined, title: "Device Joined: Mac mini", deviceID: primary.id))
        let openDetail = id
        try DeviceGroupWriter(container: container, references: [rules, events]).removeInterface(primary.id)
        let rows = try all()
        let resolver = DeviceGroupResolver(rows: rows)
        // The rule still names a row of the device, so it still fires for the device.
        #expect(rules.held.allSatisfy { held in resolver.device(for: held)?.contains(wifi.id) == true })
        // The Timeline entry names a row that exists.
        #expect(events.events.first?.deviceID == wifi.id)
        let named = try #require(events.events.first?.deviceID)
        #expect(resolver.device(for: named) != nil)
        // An open detail keyed by the device's ID finds what is left (a device of one row now).
        #expect(resolver.device(for: openDetail) == nil && resolver.device(for: wifi.id)?.members.count == 1)
    }

    @Test("The newest devices: 250 two-interface groups in the newest 500 rows still give 500 devices")
    func recentDevicesCountDevicesNotRows() throws {
        var groups: [[UUID]] = []
        for index in 0..<250 {
            let wired = try row("10.1.\(index / 200).\(index % 200)", firstSeen: 0)
            let wifi = try row("10.2.\(index / 200).\(index % 200)", firstSeen: 0)
            for member in [wired, wifi] {
                member.lastSeen = Date(timeIntervalSince1970: 1_900_000_000 + Double(index))
            }
            groups.append([wired.id, wifi.id])
        }
        for index in 0..<400 {
            let single = try row("10.3.\(index / 200).\(index % 200)")
            single.lastSeen = Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
        }
        try context.save()
        for pair in groups {
            try writer.group(pair, primary: pair[0], source: .user)
        }
        let devices = try DeviceGroups.recentDevices(in: .network(home), limit: 500, in: ModelContext(container))
        #expect(devices.count == 500)
        #expect(devices.prefix(250).allSatisfy { $0.isGroup })
        #expect(devices.dropFirst(250).allSatisfy { !$0.isGroup })
    }

    @Test("A rule device's ports are those measured at its current address only")
    func ruleDevicePortsAreTheCurrentInterfaces() throws {
        let wired = try row("10.0.0.10"), wifi = try row("10.0.0.40")
        wired.openPorts = [22]
        wired.lastSeen = Date(timeIntervalSince1970: 1_800_000_000)
        wifi.lastSeen = Date(timeIntervalSince1970: 1_800_000_600)
        try context.save()
        try writer.group([wired.id, wifi.id], primary: wired.id, source: .user)
        let device = try #require(try DeviceGroups.project(all()).first)
        #expect(device.ipAddress == "10.0.0.40")
        #expect(RuleDevice(device).openPorts.isEmpty, "no Wi-Fi:22 target from the Ethernet port")
    }

    // MARK: Verification round (#615)

    @Test("References move before the save: a failure after the save leaves no rule on a deleted row")
    func repointsBeforeTheSave() throws {
        let primary = try row("10.0.0.10", notes: "Mac mini"), wifi = try row("10.0.0.40")
        try writer.group([primary.id, wifi.id], primary: primary.id, source: .user)
        let rules = RecordingReferences(holding: [primary.id])
        struct CrashAfterSave: Error {}
        let crashing = DeviceGroupWriter(container: container, references: [rules], save: { context in
            try context.save()
            throw CrashAfterSave()
        })
        #expect(throws: CrashAfterSave.self) { try crashing.removeInterface(primary.id) }
        let rows = try all()
        #expect(rows.map(\.id) == [wifi.id], "the removal was saved")
        #expect(rules.held == [wifi.id], "the rule names the live interface, not the deleted row")
    }

    @Test("A scope reads one network, the rows without a network, or every network; never mixed by accident")
    func scopes() throws {
        let other = UUID()
        let mine = try row("10.0.0.10"), theirs = try row("10.0.0.20", network: other)
        let unassigned = LocalDevice(ipAddress: "10.0.0.30", macAddress: "")
        context.insert(unassigned)
        try context.save()
        func ids(_ scope: DeviceScope) throws -> Set<UUID> {
            try Set(DeviceGroups.recentDevices(in: scope, limit: 10, in: ModelContext(container)).map(\.id))
        }
        #expect(try ids(.network(home)) == [mine.id])
        #expect(try ids(.withoutNetwork) == [unassigned.id])
        #expect(try ids(.allNetworks) == [mine.id, theirs.id, unassigned.id])
        #expect(DeviceScope.network(nil, else: .withoutNetwork) == .withoutNetwork)
    }

    @Test("Rows with equal last seen and address page in a stable order, each once")
    func pagingTies() throws {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        var made: [UUID] = []
        for _ in 0..<7 {
            let tie = LocalDevice(ipAddress: "10.0.0.9", macAddress: "", networkProfileID: home)
            tie.lastSeen = seen
            context.insert(tie)
            made.append(tie.id)
        }
        try context.save()
        let first = try DeviceGroups.recentDevices(in: .network(home), limit: 3, in: ModelContext(container)).map(\.id)
        let again = try DeviceGroups.recentDevices(in: .network(home), limit: 3, in: ModelContext(container)).map(\.id)
        #expect(first.count == 3 && Set(first).count == 3)
        #expect(first == again, "the same three every time")
        let all = try DeviceGroups.recentDevices(in: .network(home), limit: 7, in: ModelContext(container)).map(\.id)
        #expect(Set(all) == Set(made), "every row once, across pages of 7")
    }

    @Test("After ungroup and after removing the primary, a refetch in the view's own context shows the new state")
    func viewContextSeesWriterChanges() throws {
        let primary = try row("10.0.0.10", notes: "Mac mini"), wifi = try row("10.0.0.40"), spare = try row("10.0.0.41")
        try writer.group([primary.id, wifi.id, spare.id], primary: primary.id, source: .user)
        func viewDevices() throws -> [DeviceProjection] {
            try DeviceGroups.project(context.fetch(FetchDescriptor<LocalDevice>()))
        }
        #expect(try viewDevices().count == 1)
        try writer.ungroup(spare.id)
        #expect(try viewDevices().count == 2)
        #expect(spare.deviceGroupID == nil, "the view's own object, refetched, has no stale group")
        try writer.removeInterface(primary.id)
        let devices = try viewDevices()
        #expect(devices.count == 2)
        #expect(devices.allSatisfy { !$0.isGroup })
        #expect(wifi.deviceGroupID == nil && wifi.groupPrimaryID == nil)
    }
}

private struct Move: Equatable {
    let from: UUID
    let to: UUID
}

@MainActor
private final class RecordingReferences: DeviceReferenceStore {
    private(set) var moves: [Move] = []
    private(set) var held: [UUID]

    init(holding held: [UUID] = []) {
        self.held = held
    }

    func repoint(from removed: UUID, to device: UUID) {
        moves.append(Move(from: removed, to: device))
        held = held.map { $0 == removed ? device : $0 }
    }
}
