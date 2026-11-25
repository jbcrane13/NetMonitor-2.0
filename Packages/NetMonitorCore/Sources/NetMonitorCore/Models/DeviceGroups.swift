import Foundation
import NetworkScanKit
import SwiftData

/// How a row joined its device group (#594). Stored as `LocalDevice.groupSource`.
public enum DeviceGroupSource: String, Sendable, CaseIterable {
    /// Its address answered for the same Bonjour host as the group's in one scan.
    case bonjour
    /// The user said it is the same device.
    case user
}

/// One device as every list, count and reader shows it (#594, design v3.1): a row of its own, or
/// the group of rows that are its interfaces. Built by ``DeviceGroups/project(_:)`` from complete
/// groups; never stored.
@MainActor
public struct DeviceProjection: Identifiable {
    /// The group's own ID (`deviceGroupID`), or the row's ID for a device of one row. Stable when
    /// the primary changes.
    public let id: UUID
    /// The member whose name, notes and rules are the device's.
    public let primary: LocalDevice
    /// Every member, the current one first, then by the same order.
    public let members: [LocalDevice]

    /// The member actions use (Ping, Ports, Copy IP): the one that answered most recently.
    public var current: LocalDevice { members[0] }
    public var isGroup: Bool { members.count > 1 }
    public var memberIDs: Set<UUID> { Set(members.map(\.id)) }
    public var displayName: String { primary.displayName }
    /// The latest of the members'.
    public var lastSeen: Date { members.map(\.lastSeen).max() ?? primary.lastSeen }
    /// The current member's address.
    public var ipAddress: String { current.ipAddress }
    /// Every member's real MAC (`DeviceMatcher.normalizedMAC`), in member order, once each.
    public var realMACs: [String] {
        var seen = Set<String>()
        return members.compactMap { DeviceMatcher.normalizedMAC($0.macAddress) }.filter { seen.insert($0).inserted }
    }

    /// Whether `id` is this device's ID or any member's row ID.
    public func contains(_ id: UUID) -> Bool {
        id == self.id || members.contains { $0.id == id }
    }
}

/// Builds ``DeviceProjection``s (#594, design v3.1 §4, §6). Readers scope rows to a network, make
/// groups complete (``completingGroups(_:in:)``), project, and only then search, filter or limit.
@MainActor
public enum DeviceGroups {
    /// One projection per device, at the position of its first row in `rows`. Rows sharing a
    /// `deviceGroupID` on the same network are one device; a group's primary is the member its
    /// `groupPrimaryID` names, else ``preferredPrimary(among:)``.
    public static func project(_ rows: [LocalDevice]) -> [DeviceProjection] {
        var order: [GroupKey] = []
        var membersByKey: [GroupKey: [LocalDevice]] = [:]
        for row in rows {
            let key = GroupKey(row)
            if membersByKey[key] == nil {
                order.append(key)
            }
            membersByKey[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let members = membersByKey[key], !members.isEmpty else { return nil }
            let sorted = members.sorted(by: isMoreCurrent)
            guard let groupID = key.groupID, members.count > 1 else {
                // A row of its own, or a group left with one member (repair clears it).
                return DeviceProjection(id: members[0].id, primary: members[0], members: sorted)
            }
            return DeviceProjection(id: groupID, primary: primary(of: members), members: sorted)
        }
    }

    /// `rows` plus every other member of the groups they belong to, so a bounded fetch (the 500
    /// most recent rows) never projects a group without its primary.
    public static func completingGroups(_ rows: [LocalDevice], in context: ModelContext) throws -> [LocalDevice] {
        let groupIDs = Set(rows.compactMap(\.deviceGroupID))
        guard !groupIDs.isEmpty else { return rows }
        let have = Set(rows.map(\.id))
        let grouped = try context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID != nil }))
        return rows + grouped.filter { member in member.deviceGroupID.map(groupIDs.contains) == true && !have.contains(member.id) }
    }

    /// The primary to use when a group's `groupPrimaryID` names no member, or a member leaves:
    /// one with user content (a custom name, notes, a serial, a user-confirmed value), then the
    /// earliest first seen, then the lower ID.
    public static func preferredPrimary(among members: [LocalDevice]) -> LocalDevice? {
        members.min { lhs, rhs in
            if hasUserContent(lhs) != hasUserContent(rhs) {
                return hasUserContent(lhs)
            }
            if lhs.firstSeen != rhs.firstSeen {
                return lhs.firstSeen < rhs.firstSeen
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// A custom name, notes, a serial or a value the user confirmed.
    public static func hasUserContent(_ row: LocalDevice) -> Bool {
        let identity = row.identity
        return !(row.customName ?? "").isEmpty || !(row.notes ?? "").isEmpty || !(row.serialNumber ?? "").isEmpty
            || [identity.maker, identity.model, identity.serial].contains { $0?.source == .userConfirmed }
    }

    static func primary(of members: [LocalDevice]) -> LocalDevice {
        let named = Set(members.compactMap(\.groupPrimaryID))
        let candidates = members.filter { named.contains($0.id) }
        if candidates.count == 1 {
            return candidates[0]
        }
        return preferredPrimary(among: candidates.isEmpty ? members : candidates) ?? members[0]
    }

    /// The order members are shown in: the latest answer first; on a tie a real MAC, then the
    /// numerically lower IPv4, then the lower ID.
    static func isMoreCurrent(_ lhs: LocalDevice, _ rhs: LocalDevice) -> Bool {
        if lhs.lastSeen != rhs.lastSeen {
            return lhs.lastSeen > rhs.lastSeen
        }
        let lhsMAC = DeviceMatcher.normalizedMAC(lhs.macAddress) != nil
        let rhsMAC = DeviceMatcher.normalizedMAC(rhs.macAddress) != nil
        if lhsMAC != rhsMAC {
            return lhsMAC
        }
        let lhsIP = ipv4Value(lhs.ipAddress), rhsIP = ipv4Value(rhs.ipAddress)
        if lhsIP != rhsIP {
            return (lhsIP ?? .max) < (rhsIP ?? .max)
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func ipv4Value(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        return parts.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private struct GroupKey: Hashable {
        let groupID: UUID?
        let rowID: UUID?
        let network: UUID?

        init(_ row: LocalDevice) {
            groupID = row.deviceGroupID
            rowID = row.deviceGroupID == nil ? row.id : nil
            network = row.networkProfileID
        }
    }
}

/// Finds the device a stored ID names (#594): a group's ID or any member row's ID, as rules,
/// Timeline events, citations and notifications store row IDs.
@MainActor
public struct DeviceGroupResolver {
    public let devices: [DeviceProjection]
    private let indexByID: [UUID: Int]

    /// `rows` must hold complete groups (see ``DeviceGroups/completingGroups(_:in:)``).
    public init(rows: [LocalDevice]) {
        devices = DeviceGroups.project(rows)
        var index: [UUID: Int] = [:]
        for (position, device) in devices.enumerated() {
            index[device.id] = position
            for member in device.members {
                index[member.id] = position
            }
        }
        indexByID = index
    }

    public func device(for id: UUID) -> DeviceProjection? {
        indexByID[id].map { devices[$0] }
    }
}

// MARK: - Presence of a device

@MainActor
public extension PresenceSnapshot {
    /// The best member's state: online > not checked recently > offline (#594).
    func freshness(of device: DeviceProjection) -> PresenceFreshness {
        let states = Set(device.members.map { freshness(of: $0) })
        if states.contains(.online) {
            return .online
        }
        return states.contains(.notCheckedRecently) ? .notCheckedRecently : .offline
    }

    /// Whether any member answered its network's latest scan (#583).
    func answeredLatestScan(_ device: DeviceProjection) -> Bool {
        device.members.contains { answeredLatestScan($0) }
    }

    /// The current member's latency, only while the device is online.
    func currentLatency(_ device: DeviceProjection) -> Double? {
        freshness(of: device).isOnline ? device.members.lazy.compactMap { currentLatency($0) }.first : nil
    }

    func isPast(_ device: DeviceProjection) -> Bool {
        PresenceFreshness.isPast(lastSeen: device.lastSeen, lastScan: lastScan(for: device.primary.networkProfileID), now: now)
    }

    func lastSeenText(_ device: DeviceProjection) -> String {
        PresenceFreshness.lastSeenText(since: device.lastSeen, now: now)
    }

    func relativeLastSeen(_ device: DeviceProjection) -> String {
        PresenceFreshness.relativeText(since: device.lastSeen, now: now)
    }

    func statusText(_ device: DeviceProjection) -> String {
        "\(freshness(of: device).label) · \(lastSeenText(device))"
    }

    func accessibilityText(_ device: DeviceProjection) -> String {
        "\(freshness(of: device).label), last seen \(relativeLastSeen(device))"
    }
}
