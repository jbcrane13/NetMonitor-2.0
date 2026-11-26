import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 (design v3.1): rows that are one device's interfaces project as one device.
@Suite("Device groups projection", .serialized)
@MainActor
struct DeviceGroupsTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    @discardableResult
    func row(
        _ ip: String, mac: String = "", seen minutes: Double = 0, status: DeviceStatus = .online, name: String? = nil,
        notes: String? = nil, firstSeen: Double = 0, network: UUID? = nil
    ) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, customName: name, status: status, notes: notes, networkProfileID: network ?? home)
        row.lastSeen = start.addingTimeInterval(minutes * 60)
        row.firstSeen = start.addingTimeInterval(firstSeen * 60)
        context.insert(row)
        return row
    }

    func group(_ rows: [LocalDevice], primary: LocalDevice) -> UUID {
        let id = UUID()
        for member in rows {
            member.deviceGroupID = id
            member.groupPrimaryID = primary.id
            member.groupSource = DeviceGroupSource.user.rawValue
        }
        return id
    }

    @Test("Rows without a group are devices of one, in input order, with their own IDs")
    func singletons() {
        let alpha = row("10.0.0.2"), bravo = row("10.0.0.3")
        let devices = DeviceGroups.project([alpha, bravo])
        #expect(devices.map(\.id) == [alpha.id, bravo.id])
        #expect(devices.allSatisfy { !$0.isGroup && $0.members.count == 1 })
        #expect(devices[0].primary === alpha && devices[0].current === alpha)
    }

    @Test("A group is one device: the group's ID, the primary's name, every member, at its first member's position")
    func groupIsOneDevice() {
        let other = row("10.0.0.1")
        let wired = row("10.0.0.10", mac: "AA:BB:CC:00:00:01", seen: 10, name: "Mac mini")
        let wifi = row("10.0.0.40", seen: 20)
        let id = group([wired, wifi], primary: wired)
        let devices = DeviceGroups.project([wifi, other, wired])
        #expect(devices.count == 2)
        #expect(devices[0].id == id)
        #expect(devices[0].displayName == "Mac mini")
        #expect(devices[0].memberIDs == [wired.id, wifi.id])
        #expect(devices[0].contains(wifi.id) && devices[0].contains(wired.id) && devices[0].contains(id))
        #expect(devices[1].primary === other)
    }

    @Test("The current member answered most recently; ties go to a real MAC, then the lower IPv4, then the lower ID")
    func currentMember() {
        let alpha = row("10.0.0.40", seen: 5)
        let bravo = row("10.0.0.9", seen: 9)
        _ = group([alpha, bravo], primary: alpha)
        #expect(DeviceGroups.project([alpha, bravo])[0].current === bravo)
        bravo.lastSeen = alpha.lastSeen
        #expect(DeviceGroups.project([alpha, bravo])[0].current === bravo, "10.0.0.9 < 10.0.0.40 numerically")
        alpha.macAddress = "AA:BB:CC:00:00:02"
        #expect(DeviceGroups.project([alpha, bravo])[0].current === alpha, "a real MAC wins a tie")
        #expect(DeviceGroups.project([bravo, alpha])[0].current === alpha, "independent of input order")
        #expect(DeviceGroups.project([alpha, bravo])[0].members.first === alpha, "the current member comes first")
    }

    @Test("Last seen is the latest member's; real MACs are every member's")
    func aggregates() {
        let alpha = row("10.0.0.10", mac: "AA:BB:CC:00:00:01", seen: 5)
        let bravo = row("10.0.0.40", mac: "02:00:00:00:00:00", seen: 50)
        let charlie = row("10.0.0.41", mac: "AA:BB:CC:00:00:03", seen: 1)
        _ = group([alpha, bravo, charlie], primary: alpha)
        let device = DeviceGroups.project([alpha, bravo, charlie])[0]
        #expect(device.lastSeen == start.addingTimeInterval(50 * 60))
        #expect(device.realMACs == ["AA:BB:CC:00:00:01", "AA:BB:CC:00:00:03"])
    }

    @Test("Presence is the best member's: online > not checked recently > offline")
    func presence() {
        let alpha = row("10.0.0.10", seen: 0, status: .offline)
        let bravo = row("10.0.0.40", seen: 10, status: .online)
        _ = group([alpha, bravo], primary: alpha)
        let snapshot = PresenceSnapshot(lastScans: [home: start.addingTimeInterval(10 * 60)], now: start.addingTimeInterval(11 * 60))
        let device = DeviceGroups.project([alpha, bravo])[0]
        #expect(snapshot.freshness(of: device) == .online)
        #expect(snapshot.answeredLatestScan(device))
        bravo.status = .offline
        #expect(snapshot.freshness(of: device) == .offline)
        #expect(!snapshot.answeredLatestScan(device))
        let stale = PresenceSnapshot(lastScans: [home: start], now: start.addingTimeInterval(86400))
        #expect(stale.freshness(of: device) == .notCheckedRecently)
    }

    @Test("A primary that names no member falls back to user content, then the earliest first seen, then the lower ID")
    func missingPrimary() {
        let plain = row("10.0.0.10", firstSeen: 0)
        let noted = row("10.0.0.40", notes: "under the desk", firstSeen: 30)
        let id = group([plain, noted], primary: plain)
        for member in [plain, noted] {
            member.groupPrimaryID = UUID()
        }
        let device = DeviceGroups.project([plain, noted])[0]
        #expect(device.id == id)
        #expect(device.primary === noted)
        noted.notes = nil
        #expect(DeviceGroups.project([plain, noted])[0].primary === plain)
    }

    @Test("Members on different networks are never joined")
    func networksSplit() {
        let alpha = row("10.0.0.10")
        let bravo = row("10.0.0.40", network: UUID())
        _ = group([alpha, bravo], primary: alpha)
        #expect(DeviceGroups.project([alpha, bravo]).count == 2)
    }

    @Test("The resolver finds a device by its group ID or any member's row ID")
    func resolver() {
        let alpha = row("10.0.0.10"), bravo = row("10.0.0.40"), charlie = row("10.0.0.50")
        let id = group([alpha, bravo], primary: alpha)
        let resolver = DeviceGroupResolver(rows: [alpha, bravo, charlie])
        #expect(resolver.device(for: id)?.id == id)
        #expect(resolver.device(for: bravo.id)?.id == id)
        #expect(resolver.device(for: charlie.id)?.id == charlie.id)
        #expect(resolver.device(for: UUID()) == nil)
    }

    @Test("A bounded fetch is completed with every member of the groups it selected")
    func completesBoundedFetch() throws {
        let primary = row("10.0.0.10", seen: 0, name: "NAS")
        for index in 0..<5 {
            row("10.0.1.\(index)", seen: 100)
        }
        let recent = row("10.0.0.40", seen: 200)
        _ = group([primary, recent], primary: primary)
        try context.save()
        var descriptor = FetchDescriptor<LocalDevice>(sortBy: [SortDescriptor(\.lastSeen, order: .reverse)])
        descriptor.fetchLimit = 3
        let bounded = try context.fetch(descriptor)
        #expect(!bounded.contains { $0 === primary })
        let complete = try DeviceGroups.completingGroups(bounded, in: context)
        let device = try #require(DeviceGroups.project(complete).first { $0.contains(recent.id) })
        #expect(device.primary === primary)
        #expect(device.displayName == "NAS")
    }
}
