import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 (design v3.1 §1, §4): the only code that writes the group fields or deletes rows. Every
/// operation fetches the rows freshly, checks them at commit and saves once, or rolls back.
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

    func all() throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>())
    }

    @Test("Grouping mints a group ID, sets the primary on every member and records the source")
    func groups() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        for member in [alpha, bravo] {
            #expect(member.deviceGroupID == id)
            #expect(member.groupPrimaryID == alpha.id)
            #expect(member.groupSource == "user")
        }
        #expect(!context.hasChanges, "saved")
        #expect(try DeviceGroups.project(all()).count == 1)
    }

    @Test("Joining a row to a grouped row keeps the group's ID and primary")
    func joinsExistingGroup() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40"), charlie = try row("10.0.0.41")
        let id = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        #expect(try writer.group([charlie.id, bravo.id], primary: nil, source: .bonjour) == id)
        #expect(charlie.deviceGroupID == id && charlie.groupPrimaryID == alpha.id && charlie.groupSource == "bonjour")
        #expect(bravo.groupSource == "user", "an existing member's source stays")
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
        #expect(!context.hasChanges)
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
        #expect(Set(alpha.notSameAsIDs ?? []) == [bravo.id, charlie.id])
        #expect(bravo.notSameAsIDs == [alpha.id])
        try writer.include(alpha.id, bravo.id)
        #expect(alpha.notSameAsIDs == [charlie.id])
        #expect(bravo.notSameAsIDs == nil)
    }

    @Test("Ungrouping a member excludes it from the rest; a group of one is cleared")
    func ungroups() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        _ = try writer.group([alpha.id, bravo.id], primary: alpha.id, source: .user)
        try writer.ungroup(bravo.id)
        for member in [alpha, bravo] {
            #expect(member.deviceGroupID == nil && member.groupPrimaryID == nil && member.groupSource == nil)
        }
        #expect(alpha.notSameAsIDs == [bravo.id] && bravo.notSameAsIDs == [alpha.id])
    }

    @Test("Removing the primary interface re-keys the group to user content, then the earliest first seen; the group ID stays")
    func removingPrimaryReKeys() throws {
        let alpha = try row("10.0.0.10", firstSeen: 0)
        let bravo = try row("10.0.0.40", firstSeen: 100)
        let charlie = try row("10.0.0.41", notes: "spare NIC", firstSeen: 200)
        let id = try writer.group([alpha.id, bravo.id, charlie.id], primary: alpha.id, source: .user)
        try writer.removeInterface(alpha.id)
        #expect(try all().count == 2)
        #expect(bravo.deviceGroupID == id && charlie.deviceGroupID == id)
        #expect(bravo.groupPrimaryID == charlie.id && charlie.groupPrimaryID == charlie.id)
        try writer.removeInterface(charlie.id)
        #expect(bravo.deviceGroupID == nil && bravo.groupPrimaryID == nil, "one member left: not a group")
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
        #expect(alpha.groupPrimaryID == alpha.id && bravo.groupPrimaryID == alpha.id)
        #expect(lone.deviceGroupID == nil && lone.groupPrimaryID == nil)
    }

    @Test("A failed save rolls back and throws")
    func failedSave() throws {
        let alpha = try row("10.0.0.10"), bravo = try row("10.0.0.40")
        struct SaveFailed: Error {}
        let failing = DeviceGroupWriter(context: context, save: { _ in throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try failing.group([alpha.id, bravo.id], primary: nil, source: .user) }
        #expect(alpha.deviceGroupID == nil && bravo.deviceGroupID == nil)
        #expect(!context.hasChanges)
    }
}
