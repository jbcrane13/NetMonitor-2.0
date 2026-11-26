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

/// The one delivery owner for device events (#603): only a reconcile that applied a scan delivers,
/// so a foreground and a background reconcile of the same scan deliver once. Timeline, alerts and
/// notifications subscribe here.
@MainActor
public final class DeviceEventDispatcher: DeviceEventDispatcherProtocol {
    public static let shared = DeviceEventDispatcher()
    public typealias Handler = @MainActor (DeviceEventBatch) -> Void

    private struct Subscription {
        /// The object the subscription lasts as long as; nil for one ended only by `unsubscribe`.
        weak var owner: AnyObject?
        let isOwned: Bool
        let handler: Handler
    }

    private var subscriptions: [UUID: Subscription] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> UUID {
        add(Subscription(owner: nil, isOwned: false, handler: handler))
    }

    @discardableResult
    public func subscribe(owner: AnyObject, _ handler: @escaping Handler) -> UUID {
        add(Subscription(owner: owner, isOwned: true, handler: handler))
    }

    public func unsubscribe(_ token: UUID) {
        subscriptions[token] = nil
    }

    public func deliver(_ batch: DeviceEventBatch) {
        // An owner that went away ended its subscription; no deinit has to (#619 CI: Swift 6.1).
        subscriptions = subscriptions.filter { !$0.value.isOwned || $0.value.owner != nil }
        guard !batch.events.isEmpty else { return }
        for subscription in subscriptions.values {
            subscription.handler(batch)
        }
    }

    /// The live subscriptions, for tests.
    var count: Int {
        subscriptions.values.count { !$0.isOwned || $0.owner != nil }
    }

    private func add(_ subscription: Subscription) -> UUID {
        let token = UUID()
        subscriptions[token] = subscription
        return token
    }
}

/// Reduces a scan to device events (#603, v3.1 §2, §3 and §9).
///
/// - Rows' **saved** states before and after the whole reconcile are compared, never display
///   freshness. A device is offline when every interface is saved offline.
/// - Each device after the scan is judged against its own members' states before: when any
///   device it came from was offline (every row of that device) and it now answers, that is one
///   `cameOnline`, a union with a device that never left included; a split device is judged by
///   the members it kept. Membership changes alone are no event.
/// - `addressChanged` when a member row's own address changed (a DHCP move), whichever member is
///   current, naming that row's new address; `renamed` only when the same row is the primary and its match name changed
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
        let offlineBefore = Set(Dictionary(grouping: before, by: \.deviceID).filter { $0.value.allSatisfy { $0.status == .offline } }.keys)
        let devices = Dictionary(grouping: after, by: \.deviceID)
        return devices.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { deviceID in
            guard let members = devices[deviceID], let primary = members.first(where: \.isPrimary) ?? members.first,
                  let current = members.first(where: \.isCurrent) ?? members.first else { return nil }
            let earlier = members.compactMap { beforeByID[$0.id] }
            func event(_ kind: DeviceEvent.Kind, interface: RowState? = nil) -> DeviceEvent {
                let interface = interface ?? current
                return DeviceEvent(
                    kind: kind, deviceID: deviceID, rowID: primary.id, memberIDs: Set(members.map(\.id)), name: primary.displayName,
                    matchName: primary.matchName, ipAddress: interface.ipAddress, macAddress: interface.macAddress,
                    networkProfileID: primary.networkProfileID, firstSeen: members.map(\.firstSeen).min() ?? primary.firstSeen,
                    lastSeen: members.map(\.lastSeen).max() ?? primary.lastSeen
                )
            }
            guard !earlier.isEmpty else { return isBaseline ? nil : event(.joined) }
            let wasOffline = earlier.allSatisfy { $0.status == .offline }
            let isOffline = members.allSatisfy { $0.status == .offline }
            // A device that was offline (every row of it before) and is now part of this online
            // device came back, even when it joined one that never left (#619).
            let predecessorWasOffline = earlier.contains { offlineBefore.contains($0.deviceID) }
            if predecessorWasOffline, !isOffline {
                return event(.cameOnline)
            }
            if !wasOffline, isOffline {
                return event(.wentOffline(since: members.map(\.lastSeen).max() ?? primary.lastSeen))
            }
            // A row's own address changing is a real move, whichever member is current (#619).
            // When several moved, the current interface's move is the one reported.
            let moves = members.filter { row in beforeByID[row.id].map { $0.ipAddress != row.ipAddress } == true }
            if let moved = moves.first(where: \.isCurrent) ?? moves.first, let old = beforeByID[moved.id] {
                return event(.addressChanged(from: old.ipAddress), interface: moved)
            }
            if let old = beforeByID[primary.id], old.isPrimary, let oldName = old.matchName, let newName = primary.matchName, oldName != newName {
                return event(.renamed(from: oldName))
            }
            return nil
        }
    }
}

// MARK: - Timeline titles

/// The Timeline's titles for device events, in one place for both apps and the readers that parse
/// them (`ChangeDigestBuilder`, `AskToolbox`) (#619): "Device Joined: name", "Device Back Online:
/// name", "Device Left: name". Address and name changes log nothing.
public enum DeviceTimelineTitle {
    public static let joined = "Device Joined"
    public static let backOnline = "Device Back Online"
    public static let left = "Device Left"

    /// The title's prefix for an event, nil for one the Timeline doesn't log.
    public static func prefix(for kind: DeviceEvent.Kind) -> String? {
        switch kind {
        case .joined: joined
        case .cameOnline: backOnline
        case .wentOffline: left
        case .addressChanged, .renamed: nil
        }
    }

    /// The same for the `DeviceChangeEvent` form.
    public static func prefix(for change: DeviceChangeEvent) -> String? {
        switch change {
        case .firstSeen: joined
        case .cameOnline: backOnline
        case .wentOffline: left
        case .changed: nil
        }
    }

    public static func title(_ prefix: String, name: String) -> String {
        "\(prefix): \(name)"
    }
}

// MARK: - The events consumers already read

public extension DeviceEvent {
    /// The event as `DeviceChangeEvent`, the form Timeline, alerts and notifications already read,
    /// carrying the device's primary row ID.
    var change: DeviceChangeEvent {
        let seen = DeviceObservation(ipAddress: ipAddress, macAddress: macAddress, name: matchName, deviceID: rowID)
        func known(ipAddress: String, name: String?) -> KnownDevice {
            KnownDevice(macAddress: macAddress, ipAddress: ipAddress, name: name, firstSeen: firstSeen, lastSeen: lastSeen, deviceID: rowID)
        }
        switch kind {
        case .joined: return .firstSeen(seen)
        case .cameOnline: return .cameOnline(seen)
        case let .wentOffline(since):
            var gone = known(ipAddress: ipAddress, name: matchName)
            gone.lastSeen = since
            return .wentOffline(gone)
        case let .addressChanged(from): return .changed(seen, previous: known(ipAddress: from, name: matchName))
        case let .renamed(from): return .changed(seen, previous: known(ipAddress: ipAddress, name: from))
        }
    }
}
