import Foundation
import NetworkScanKit

/// The phone's own latest completed scan (#585): what "Seen by this iPhone at …" is read from, never
/// a `lastSeen` the Mac's answers may have stamped.
public struct OwnScan: Sendable {
    public let date: Date
    public let devices: [DiscoveredDevice]

    public init(date: Date, devices: [DiscoveredDevice]) {
        self.date = date
        self.devices = devices
    }
}

/// What every iPhone surface reads of the Mac's inventory for one network (#585): computed once per
/// list, link change, store save, scan or presence tick by the app's model, never in a view body.
/// - Each saved device's Mac record (`MacInventory.matches`) and the devices only the Mac knows.
/// - Which saved devices the phone's own latest scan saw, and when.
/// - One online count for the list, the dashboard and the widget.
///
/// `.none` (no live inventory) overlays nothing: every surface shows the phone's own data.
public struct MacInventoryOverlay {
    public let networkID: UUID?
    public let availability: MacInventory.Availability
    public let devices: [DeviceProjection]
    private let matches: MacInventory.Matches
    private let phoneSightings: [UUID: Date]

    public static var none: MacInventoryOverlay {
        MacInventoryOverlay(networkID: nil, availability: .unavailable, devices: [], matches: .none, phoneSightings: [:])
    }

    /// The live inventory, if any.
    public var inventory: MacInventory? {
        if case .live(let inventory) = availability {
            return inventory
        }
        return nil
    }

    /// Devices only the Mac knows: shown, never saved.
    public var macOnly: [MacInventory.Record] {
        matches.macOnly
    }

    /// Whether this overlay is for `network`'s list.
    public func applies(to network: UUID?) -> Bool {
        networkID == network
    }

    public func record(for device: DeviceProjection) -> MacInventory.Record? {
        matches.record(for: device)
    }

    /// When the phone's own latest scan saw `device`, while the inventory is live.
    public func phoneSighting(for device: DeviceProjection) -> Date? {
        phoneSightings[device.id]
    }

    /// Whether a list shows `device`: a past device only when past devices are shown, or when the
    /// Mac has it online now (matched by MAC: a past device never matches by address).
    public func isShown(_ device: DeviceProjection, showPast: Bool, presence: PresenceSnapshot) -> Bool {
        showPast || !presence.isPast(device) || record(for: device)?.state == .online
    }

    /// The state a list shows for `device`: the Mac's while it has a record, else the phone's.
    public func freshness(of device: DeviceProjection, presence: PresenceSnapshot) -> PresenceFreshness {
        record(for: device)?.state ?? presence.freshness(of: device)
    }

    /// Devices online now as the list shows them (past ones hidden): the saved devices by
    /// `freshness(of:presence:)`, plus those only the Mac knows.
    public func onlineCount(presence: PresenceSnapshot) -> Int {
        devices.count { isShown($0, showPast: false, presence: presence) && freshness(of: $0, presence: presence).isOnline }
            + macOnly.count { $0.state.isOnline }
    }

    /// - Parameters:
    ///   - rows: `networkID`'s saved rows (and those saved without a network), complete groups.
    ///   - presence: the phone's presence: its clock, grace and the network's latest scan.
    ///   - ownScan: the phone's own latest completed scan of the network, if any.
    public static func make(
        availability: MacInventory.Availability, networkID: UUID?, rows: [LocalDevice], presence: PresenceSnapshot, ownScan: OwnScan?
    ) -> MacInventoryOverlay {
        let devices = DeviceGroups.project(rows)
        guard case .live(let inventory) = availability else {
            return MacInventoryOverlay(networkID: networkID, availability: availability, devices: devices, matches: .none, phoneSightings: [:])
        }
        let matches = inventory.matches(
            devices, now: presence.now, window: presence.policy.interval, previousScan: presence.lastScan(for: networkID),
            isPast: { presence.isPast($0) }
        )
        return MacInventoryOverlay(
            networkID: networkID, availability: availability, devices: devices, matches: matches,
            phoneSightings: ownScan.map { sightings(of: devices, in: $0, networkID: networkID, window: presence.policy.interval) } ?? [:]
        )
    }

    /// The devices the scan saw by the rule the reconciler saved it by (`PresenceMatch`).
    private static func sightings(of devices: [DeviceProjection], in scan: OwnScan, networkID: UUID?, window: TimeInterval) -> [UUID: Date] {
        var rows: [(device: UUID, row: LocalDevice)] = []
        for device in devices {
            rows += device.members.map { (device.id, $0) }
        }
        let observed = scan.devices.filter { !$0.isCached && ($0.networkProfileID == networkID || $0.networkProfileID == nil) }
        let assignment = PresenceMatch.assign(
            known: rows.map {
                PresenceMatch.Known(
                    DeviceMatchCandidate(ipAddress: $0.row.ipAddress, macAddress: $0.row.macAddress, name: $0.row.matchName),
                    lastSeen: $0.row.lastSeen
                )
            },
            observed: observed.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) },
            now: scan.date, window: window
        )
        var result: [UUID: Date] = [:]
        for assigned in assignment.compactMap(\.self) {
            result[rows[assigned].device] = scan.date
        }
        return result
    }
}
