import Foundation
import NetworkScanKit

/// The connected Mac's device inventory as the phone shows it (#585, the Fing Desktop model): a
/// read-only overlay, never saved. It is live only while the link is up, the Mac advertised
/// `inventory.v1` on it, the list arrived on it (#598), the list covers the phone's network and
/// the Mac's latest scan, placed on the phone's clock as `receivedAt - scanAge` (#619), is within
/// the grace interval. Otherwise the phone shows its own data.
///
/// Records are matched to the phone's devices by MAC when both have one; otherwise looked up by
/// the device's address. A lookup never creates or changes a device, and the Mac's device ID is
/// only a key into the list.
public struct MacInventory: Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        /// Not connected, no capability, no list on this link, or the Mac's scan is old.
        case unavailable
        /// The Mac's list covers another network; its name, when the Mac sent one.
        case otherNetwork(name: String?)
        case live(MacInventory)
    }

    /// One device as the Mac shows it, with its times on the phone's clock.
    public struct Record: Identifiable, Sendable, Equatable {
        /// The Mac's device ID: a key into the list, never a row ID on the phone.
        public let id: UUID
        public let name: String
        public let ipAddress: String
        public let realMACs: [String]
        public let memberAddresses: [String]
        /// Online or offline, as of the Mac's latest scan.
        public let state: PresenceFreshness
        public let lastSeen: Date?
        public let lastChanged: Date?
        public let maker: String?
        public let model: String?
        public let deviceType: DeviceType
    }

    /// When the Mac's latest scan was, on the phone's clock.
    public let scanTime: Date
    public let records: [Record]

    public static func availability(
        list: DeviceListPayload?, receivedAt: Date?, connected: Bool, offersInventory: Bool, subnet: String?, now: Date,
        policy: DeviceGracePolicy = DeviceGracePolicy()
    ) -> Availability {
        guard connected, offersInventory, let list, let receivedAt, let network = list.network, let scanAge = network.scanAge,
              let subnet else { return .unavailable }
        guard network.subnet == subnet else { return .otherNetwork(name: network.name) }
        let scanTime = receivedAt.addingTimeInterval(-max(scanAge, 0))
        guard PresenceFreshness.isRecent(scanTime, now: now, policy: policy) else { return .unavailable }
        return .live(MacInventory(scanTime: scanTime, records: list.devices.map { record($0, receivedAt: receivedAt) }))
    }

    /// "From your Mac · scanned 2 min ago".
    public func sourceText(now: Date) -> String {
        "From your Mac · scanned \(PresenceFreshness.relativeText(since: scanTime, now: now))"
    }

    // MARK: - Matching

    /// Which record is which phone device's, and the records no phone device has.
    public struct Matches: Sendable {
        private let recordByDevice: [UUID: Record]
        /// Devices only the Mac knows: shown, never saved.
        public let macOnly: [Record]

        public func record(for device: DeviceProjection) -> Record? {
            recordByDevice[device.id]
        }

        fileprivate init(recordByDevice: [UUID: Record], macOnly: [Record]) {
            self.recordByDevice = recordByDevice
            self.macOnly = macOnly
        }
    }

    /// Matches `devices` (the phone's, one per device) to the records: by a shared real MAC, else
    /// by the device's current address when no real MACs disagree. A device with several candidate
    /// records, or a record several devices want, gets no match, and such a record isn't listed as
    /// the Mac's alone either. A MAC match beats address lookups of the same record.
    public func matches(_ devices: [DeviceProjection]) -> Matches {
        var claims: [Int: [(device: UUID, byMAC: Bool)]] = [:]
        var touched = Set<Int>()
        for device in devices {
            let macs = Set(device.realMACs)
            let byMAC = records.indices.filter { !macs.isDisjoint(with: records[$0].realMACs) }
            let candidates = byMAC.isEmpty
                ? records.indices.filter { index in
                    let record = records[index]
                    let disagree = !macs.isEmpty && !record.realMACs.isEmpty && macs.isDisjoint(with: record.realMACs)
                    return !disagree && record.memberAddresses.contains(device.ipAddress)
                }
                : byMAC
            touched.formUnion(candidates)
            if candidates.count == 1 {
                claims[candidates[0], default: []].append((device.id, !byMAC.isEmpty))
            }
        }
        var recordByDevice: [UUID: Record] = [:]
        for (index, wanted) in claims {
            let byMAC = wanted.filter(\.byMAC)
            let winners = byMAC.isEmpty ? wanted : byMAC
            if winners.count == 1 {
                recordByDevice[winners[0].device] = records[index]
            }
        }
        let macOnly = records.indices.filter { !touched.contains($0) }.map { records[$0] }
        return Matches(recordByDevice: recordByDevice, macOnly: macOnly)
    }

    // MARK: - Private

    private static func record(_ device: DeviceInfo, receivedAt: Date) -> Record {
        let identity = device.identity?.deviceIdentity ?? DeviceIdentity()
        let members = device.members ?? []
        var seen = Set<String>()
        let macs = ([device.macAddress] + members.compactMap(\.macAddress))
            .compactMap { DeviceMatcher.normalizedMAC($0) }
            .filter { seen.insert($0).inserted }
        let name = [identity.friendlyName?.value, device.hostname].compactMap { $0 }.first { !$0.isEmpty } ?? device.ipAddress
        return Record(
            id: device.id,
            name: name,
            ipAddress: device.ipAddress,
            realMACs: macs,
            memberAddresses: [device.ipAddress] + members.map(\.ipAddress),
            state: device.isDeviceOnline ?? device.isOnline ? .online : .offline,
            lastSeen: device.lastSeenAge.map { receivedAt.addingTimeInterval(-max($0, 0)) },
            lastChanged: device.lastChangedAge.map { receivedAt.addingTimeInterval(-max($0, 0)) },
            maker: identity.resolvedMaker(macPrefixMaker: device.vendor),
            model: identity.model?.value,
            deviceType: DeviceType(rawValue: device.deviceType) ?? .unknown
        )
    }
}
