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

/// What makes rows one device (#594): the same group on the same network; a row outside a group is
/// a device of its own. The one key projection, repair and the bounded fetch share.
public struct DeviceGroupKey: Hashable, Sendable {
    public let groupID: UUID?
    public let rowID: UUID?
    public let network: UUID?

    public init(_ row: LocalDevice) {
        groupID = row.deviceGroupID
        rowID = row.deviceGroupID == nil ? row.id : nil
        network = row.networkProfileID
    }
}

/// Builds ``DeviceProjection``s (#594, design v3.1 §4, §6). Readers scope rows to a network, make
/// groups complete (``completingGroups(_:in:)``), project, and only then search, filter or limit.
public enum DeviceGroups {
    /// One projection per device, at the position of its first row in `rows`. Rows sharing a
    /// `deviceGroupID` on the same network are one device; a group's primary is the member its
    /// `groupPrimaryID` names, else ``preferredPrimary(among:)``.
    public static func project(_ rows: [LocalDevice]) -> [DeviceProjection] {
        var order: [DeviceGroupKey] = []
        var membersByKey: [DeviceGroupKey: [LocalDevice]] = [:]
        for row in rows {
            let key = DeviceGroupKey(row)
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

    /// `rows` plus every other member of the groups they belong to, on the same network, so a
    /// bounded fetch never projects a group without its primary. Fetches only those groups.
    public static func completingGroups(_ rows: [LocalDevice], in context: ModelContext) throws -> [LocalDevice] {
        let selected = Set(rows.filter { $0.deviceGroupID != nil }.map(DeviceGroupKey.init))
        guard !selected.isEmpty else { return rows }
        let have = Set(rows.map(\.id))
        let members = try self.members(ofGroups: Set(selected.compactMap(\.groupID)), in: context)
        return rows + members.filter { !have.contains($0.id) && selected.contains(DeviceGroupKey($0)) }
    }

    /// Every row of the groups `groupIDs`, by predicate.
    public static func members(ofGroups groupIDs: Set<UUID>, in context: ModelContext) throws -> [LocalDevice] {
        guard !groupIDs.isEmpty else { return [] }
        // SwiftData's SQL can't translate `??` or optional binding here; the unwrap is guarded.
        return try context.fetch(FetchDescriptor<LocalDevice>(
            // swiftlint:disable:next force_unwrapping
            predicate: #Predicate { $0.deviceGroupID != nil && groupIDs.contains($0.deviceGroupID!) }
        ))
    }

    /// The device `row` belongs to: its group's complete membership, projected; the row alone
    /// when it is in no group.
    public static func device(of row: LocalDevice, in context: ModelContext) throws -> DeviceProjection {
        guard let groupID = row.deviceGroupID else { return project([row])[0] }
        let members = try members(ofGroups: [groupID], in: context).filter { $0.networkProfileID == row.networkProfileID }
        return project(members.contains { $0.id == row.id } ? members : members + [row]).first { $0.contains(row.id) }
            ?? project([row])[0]
    }

    /// The `limit` most recently seen devices on `network` (every network's when nil), each with
    /// all its members, most recent first: the bounded fetch every capped reader uses (#594). Pages
    /// through the rows, newest first, until `limit` distinct devices are chosen (a group's
    /// interfaces count once) or the rows run out, then completes their groups.
    public static func recentDevices(network: UUID?, limit: Int, in context: ModelContext) throws -> [DeviceProjection] {
        var selected: [LocalDevice] = []
        var chosen = Set<DeviceGroupKey>()
        var offset = 0
        while chosen.count < limit {
            var descriptor: FetchDescriptor<LocalDevice>
            if let network {
                descriptor = FetchDescriptor(predicate: #Predicate { $0.networkProfileID == network })
            } else {
                descriptor = FetchDescriptor()
            }
            descriptor.sortBy = [SortDescriptor(\.lastSeen, order: .reverse), SortDescriptor(\.ipAddress)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            let page = try context.fetch(descriptor)
            for row in page {
                let key = DeviceGroupKey(row)
                if chosen.contains(key) || chosen.count < limit {
                    chosen.insert(key)
                    selected.append(row)
                }
            }
            offset += page.count
            if page.count < limit {
                break
            }
        }
        return try Array(project(completingGroups(selected, in: context)).prefix(limit))
    }

    /// What deleting an interface takes with it, for the confirmation both apps show (#594):
    /// "This deletes 192.168.1.60 from this device, with its custom name and its notes. The rule
    /// ‘Studio down’ names it and will follow the device's other interfaces." `references` are the
    /// rules and targets naming the row, already worded ("the rule ‘Studio down’").
    public static func removalMessage(for row: LocalDevice, references: [String] = []) -> String {
        let content = userContent(of: row)
        var message = "This deletes \(row.ipAddress) from this device"
        message += content.isEmpty ? "." : ", with \(ListFormatter.localizedString(byJoining: content))."
        guard !references.isEmpty else { return message }
        let named = ListFormatter.localizedString(byJoining: references)
        let verb = references.count == 1 ? "names it and" : "name it and"
        return message + " \(named.prefix(1).uppercased() + named.dropFirst()) \(verb) will follow the device's other interfaces."
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
        !userContent(of: row).isEmpty
    }

    /// What the user entered on a row, worded for a confirmation ("This deletes … with its
    /// custom name and its notes."): the one list both apps show before removing an interface.
    public static func userContent(of row: LocalDevice) -> [String] {
        let identity = row.identity
        var parts: [String] = []
        if !(row.customName ?? "").isEmpty {
            parts.append("its custom name")
        }
        if !(row.notes ?? "").isEmpty {
            parts.append("its notes")
        }
        if !(row.serialNumber ?? "").isEmpty {
            parts.append("its serial number")
        }
        if [identity.maker, identity.model].contains(where: { $0?.source == .userConfirmed }) {
            parts.append("the maker and model you confirmed")
        }
        return parts
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
        let lhsIP = NetworkUtilities.ipv4ToUInt32(lhs.ipAddress), rhsIP = NetworkUtilities.ipv4ToUInt32(rhs.ipAddress)
        if lhsIP != rhsIP {
            return (lhsIP ?? .max) < (rhsIP ?? .max)
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

}

/// Finds the device a stored ID names (#594): a group's ID or any member row's ID, as rules,
/// Timeline events, citations and notifications store row IDs.
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

// MARK: - Rule subjects

public extension AlertRuleSubject {
    /// Marks the subject as `row`, one interface of `device` (#594): rules naming any member match
    /// it, and an outage is one per device.
    mutating func setDevice(_ device: DeviceProjection, row: LocalDevice) {
        deviceID = row.id
        deviceGroupID = device.isGroup ? device.id : nil
        groupMemberIDs = device.isGroup ? device.memberIDs : []
    }
}
