import Foundation

/// One device's change in one scan (#603, #594 PR2): a device, not a row, so a group of
/// interfaces gives at most one event per scan.
public struct DeviceEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A device the network had never seen answered (never on the network's first recorded scan).
        case joined
        /// The device was offline (every interface) and now answers.
        case cameOnline
        /// Every interface went offline under the grace policy; `since` is when it last answered.
        case wentOffline(since: Date)
        /// The same current interface answered at another address (DHCP moved it).
        case addressChanged(from: String)
        /// The primary's name changed from one value to another (a name appearing is not a change).
        case renamed(from: String)
    }

    public let kind: Kind
    /// `DeviceProjection.id`: the group's ID, or the row's for a device of one row.
    public let deviceID: UUID
    /// The primary row, the ID rules, Timeline entries and links name.
    public let rowID: UUID
    public let memberIDs: Set<UUID>
    /// The device's name through the identity seam (`displayName`).
    public let name: String
    /// The primary's match name (hostname, else friendly name).
    public let matchName: String?
    /// The current interface's address and real MAC.
    public let ipAddress: String
    public let macAddress: String?
    public let networkProfileID: UUID?
    public let firstSeen: Date
    public let lastSeen: Date

    public init(
        kind: Kind, deviceID: UUID, rowID: UUID, memberIDs: Set<UUID>, name: String, matchName: String?, ipAddress: String,
        macAddress: String?, networkProfileID: UUID?, firstSeen: Date, lastSeen: Date
    ) {
        self.kind = kind
        self.deviceID = deviceID
        self.rowID = rowID
        self.memberIDs = memberIDs
        self.name = name
        self.matchName = matchName
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.networkProfileID = networkProfileID
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// A reconcile's events, delivered once by the reconcile that applied the scan.
public struct DeviceEventBatch: Sendable, Equatable {
    public let networkProfileID: UUID?
    public let scanDate: Date
    public let events: [DeviceEvent]

    public init(networkProfileID: UUID?, scanDate: Date, events: [DeviceEvent]) {
        self.networkProfileID = networkProfileID
        self.scanDate = scanDate
        self.events = events
    }
}

/// Where device events go (#603): the reconcile that applied a scan delivers; Timeline, alerts and
/// notifications subscribe. ``DeviceEventDispatcher/shared`` is the app's one; tests make their own.
@MainActor
public protocol DeviceEventDispatching: AnyObject {
    /// Calls `handler` with every later batch until `unsubscribe` is called with the returned token.
    @discardableResult
    func subscribe(_ handler: @escaping DeviceEventDispatcher.Handler) -> UUID
    func unsubscribe(_ token: UUID)
    func deliver(_ batch: DeviceEventBatch)
}

/// The one delivery owner for device events (#603): only a reconcile that applied a scan delivers,
/// so a foreground and a background reconcile of the same scan deliver once. Timeline, alerts and
/// notifications subscribe here.
@MainActor
public final class DeviceEventDispatcher: DeviceEventDispatching {
    public static let shared = DeviceEventDispatcher()
    public typealias Handler = @MainActor (DeviceEventBatch) -> Void

    private var handlers: [UUID: Handler] = [:]

    public init() {}

    /// Calls `handler` with every later batch until `unsubscribe` is called with the returned token.
    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> UUID {
        let token = UUID()
        handlers[token] = handler
        return token
    }

    public func unsubscribe(_ token: UUID) {
        handlers[token] = nil
    }

    public func deliver(_ batch: DeviceEventBatch) {
        guard !batch.events.isEmpty else { return }
        for handler in handlers.values {
            handler(batch)
        }
    }
}

/// Reduces a scan to device events (#603, v3.1 §2, §3 and §9).
///
/// - Rows' **saved** states before and after the whole reconcile are compared, never display
///   freshness. A device is offline when every interface is saved offline.
/// - Each device after the scan is judged against its own members' states before: a union of
///   devices that were all offline and now answer is one `cameOnline`; a split device is judged
///   by the members it kept. Membership changes alone are no event.
/// - `addressChanged` only when the same row is the current interface before and after and its
///   address changed; `renamed` only when the same row is the primary and its match name changed
///   from one value to another.
/// - `joined` for a device whose every member was created this scan, except on the network's
///   first recorded scan (the baseline).
public enum DeviceEventReducer {
    /// A row's saved state at one moment, with its device's primary and current interface.
    public struct RowState: Sendable, Equatable {
        public let id: UUID
        public let deviceID: UUID
        public let isPrimary: Bool
        public let isCurrent: Bool
        public let status: DeviceStatus
        public let ipAddress: String
        public let macAddress: String?
        public let matchName: String?
        public let displayName: String
        public let networkProfileID: UUID?
        public let firstSeen: Date
        public let lastSeen: Date
    }

    /// The rows' states now, projected into devices.
    public static func snapshot(_ rows: [LocalDevice]) -> [RowState] {
        DeviceGroups.project(rows).flatMap { device in
            device.members.map { row in
                RowState(
                    id: row.id, deviceID: device.id, isPrimary: row.id == device.primary.id, isCurrent: row.id == device.current.id,
                    status: row.status, ipAddress: row.ipAddress, macAddress: DeviceMatcher.normalizedMAC(row.macAddress),
                    matchName: row.matchName, displayName: device.displayName, networkProfileID: row.networkProfileID,
                    firstSeen: row.firstSeen, lastSeen: row.lastSeen
                )
            }
        }
    }

    public static func reduce(before: [RowState], after: [RowState], isBaseline: Bool) -> [DeviceEvent] {
        let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let devices = Dictionary(grouping: after, by: \.deviceID)
        return devices.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { deviceID in
            guard let members = devices[deviceID], let primary = members.first(where: \.isPrimary) ?? members.first,
                  let current = members.first(where: \.isCurrent) ?? members.first else { return nil }
            let earlier = members.compactMap { beforeByID[$0.id] }
            func event(_ kind: DeviceEvent.Kind) -> DeviceEvent {
                DeviceEvent(
                    kind: kind, deviceID: deviceID, rowID: primary.id, memberIDs: Set(members.map(\.id)), name: primary.displayName,
                    matchName: primary.matchName, ipAddress: current.ipAddress, macAddress: current.macAddress,
                    networkProfileID: primary.networkProfileID, firstSeen: members.map(\.firstSeen).min() ?? primary.firstSeen,
                    lastSeen: members.map(\.lastSeen).max() ?? primary.lastSeen
                )
            }
            guard !earlier.isEmpty else { return isBaseline ? nil : event(.joined) }
            let wasOffline = earlier.allSatisfy { $0.status == .offline }
            let isOffline = members.allSatisfy { $0.status == .offline }
            if wasOffline, !isOffline {
                return event(.cameOnline)
            }
            if !wasOffline, isOffline {
                return event(.wentOffline(since: members.map(\.lastSeen).max() ?? primary.lastSeen))
            }
            if let old = beforeByID[current.id], old.isCurrent, old.ipAddress != current.ipAddress {
                return event(.addressChanged(from: old.ipAddress))
            }
            if let old = beforeByID[primary.id], old.isPrimary, let oldName = old.matchName, let newName = primary.matchName, oldName != newName {
                return event(.renamed(from: oldName))
            }
            return nil
        }
    }
}

// MARK: - The events consumers already read

public extension DeviceEvent {
    /// The event as `DeviceChangeEvent`, the form Timeline, alerts and notifications already read,
    /// carrying the device's primary row ID.
    var change: DeviceChangeEvent {
        let seen = DeviceObservation(ipAddress: ipAddress, macAddress: macAddress, name: matchName, deviceID: rowID)
        func known(ipAddress: String, name: String?, isOffline: Bool) -> KnownDevice {
            var device = KnownDevice(
                macAddress: macAddress, ipAddress: ipAddress, name: name, firstSeen: firstSeen, lastSeen: lastSeen, isOffline: isOffline
            )
            device.deviceID = rowID
            return device
        }
        switch kind {
        case .joined: return .firstSeen(seen)
        case .cameOnline: return .cameOnline(seen)
        case let .wentOffline(since):
            var gone = known(ipAddress: ipAddress, name: matchName, isOffline: true)
            gone.lastSeen = since
            return .wentOffline(gone)
        case let .addressChanged(from): return .changed(seen, previous: known(ipAddress: from, name: matchName, isOffline: false))
        case let .renamed(from): return .changed(seen, previous: known(ipAddress: ipAddress, name: from, isOffline: false))
        }
    }
}
