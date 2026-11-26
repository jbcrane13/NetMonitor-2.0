import Foundation
import NetworkScanKit

/// The companion link's path as the phone sees it (#585): which interface carries it and the
/// Mac's address on it. Fails closed: an unknown path never counts as on-link.
public struct CompanionLinkPath: Sendable, Equatable {
    public enum Interface: Sendable, Equatable {
        case wifi, wiredEthernet, cellular, loopback, other
    }

    /// The Mac's address, as the connection resolved it (an IPv6 address may carry `%scope`).
    public let remoteAddress: String?
    public let interface: Interface

    public init(remoteAddress: String?, interface: Interface) {
        self.remoteAddress = remoteAddress
        self.interface = interface
    }

    /// Whether the Mac is on this link of `network`: over Wi-Fi or Ethernet (not a VPN tunnel,
    /// cellular or loopback), at an IPv4 address inside it or an IPv6 link-local address, which
    /// can't be routed.
    public func isOnLink(in network: NetworkUtilities.IPv4Network) -> Bool {
        guard interface == .wifi || interface == .wiredEthernet, let address = remoteAddress else { return false }
        if network.contains(ipAddress: address) {
            return true
        }
        return address.lowercased().hasPrefix("fe80:")
    }
}

/// The network the phone is on now (#585): its detected, connected local profile and its routed
/// gateway, nil when the route lookup failed (a profile's own `gatewayIP` is a guess, the subnet's
/// first host, so it proves nothing).
public struct PhoneNetwork: Sendable, Equatable {
    public let profile: NetworkProfile
    public let gatewayIP: String?

    public init(profile: NetworkProfile, gatewayIP: String?) {
        self.profile = profile
        self.gatewayIP = gatewayIP
    }
}

/// The connected Mac's device inventory as the phone shows it (#585, the Fing Desktop model): never
/// saved as devices. It is live only when every one of these holds, else the phone shows its own
/// data:
/// - the link is up, and the list arrived on it (#598) and carries `network` (an `inventory.v1`
///   Mac's list; the capability is read from the list itself, so no race with the heartbeat);
/// - the phone is on a network now, and that is the network being viewed;
/// - the list's subnet and routed gateway are that network's;
/// - the link runs on-link over Wi-Fi or Ethernet (`CompanionLinkPath`);
/// - the Mac's latest scan, placed on the phone's clock as `receivedAt - scanAge` (#619), is within
///   the grace interval.
///
/// Records match the phone's devices by the `PresenceMatch` rule (a MAC on both sides decides; two
/// names differ, two devices; an unknown name only for a row seen there within grace or by the
/// previous scan), and a past device never by address. A match never creates or changes a device.
public struct MacInventory: Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        case unavailable
        /// The Mac's list covers another network; its name, when the Mac sent one.
        case otherNetwork(name: String?)
        case live(MacInventory)
    }

    /// One device as the Mac shows it, with its times on the phone's clock.
    public struct Record: Identifiable, Sendable, Equatable {
        public struct Member: Sendable, Equatable {
            public let ipAddress: String
            public let macAddress: String?
            public let isPrimary: Bool
        }

        /// The Mac's device ID: a key into the list, never a row ID on the phone.
        public let id: UUID
        public let name: String
        /// The name the match compares: the Mac's hostname, else friendly name.
        public let matchName: String?
        public let ipAddress: String
        public let members: [Member]
        /// What the Mac app shows (#583's grace rule, lead on #585): Online when the Mac has it online
        /// (it answered the Mac's latest scan, or missed it inside the Mac's grace), shown with its real
        /// last seen; Offline when the Mac has it offline. Only a live list has records, so the Mac's
        /// scan is within grace. Which interfaces answered that scan (and so refresh the phone's rows)
        /// is decided per member, never from this.
        public let state: PresenceFreshness
        public let lastSeen: Date?
        public let lastChanged: Date?
        public let maker: String?
        public let model: String?
        public let deviceType: DeviceType
        /// When the list arrived, on the phone's clock: ages are read from no earlier than this.
        public let receivedAt: Date

        /// "Online · from your Mac · Last seen 2 min ago".
        public func statusText(now: Date) -> String {
            PresenceFreshness.statusText(state, lastSeen: lastSeen, now: max(now, receivedAt), source: Self.source)
        }

        /// "Online, from your Mac, last seen 2 min ago", for VoiceOver.
        public func accessibilityText(now: Date) -> String {
            PresenceFreshness.accessibilityText(state, lastSeen: lastSeen, now: max(now, receivedAt), source: Self.source)
        }

        /// "Last changed 1 hour ago, from your Mac": when it last joined or left, from the Mac's
        /// event log; nil when the log has nothing.
        public func changedText(now: Date) -> String? {
            lastChanged.map { "Last changed \(PresenceFreshness.relativeText(since: $0, now: max(now, receivedAt))), \(Self.source)" }
        }

        public static let source = "from your Mac"
    }

    /// The longest age taken from the wire; a longer, negative or non-finite one is dropped.
    public static let maximumAge: TimeInterval = 10 * 365 * 86400

    /// When the Mac's latest scan was, on the phone's clock.
    public let scanTime: Date
    /// When the list arrived, on the phone's clock.
    public let receivedAt: Date
    public let records: [Record]

    /// - Parameters:
    ///   - link: the current link's path; nil without a link (not connected).
    ///   - presence: the phone's clock and grace policy.
    public static func availability(
        list: DeviceListPayload?, receivedAt: Date?, link: CompanionLinkPath?, phone: PhoneNetwork?, viewing: UUID?,
        presence: PresenceSnapshot
    ) -> Availability {
        guard let link, let list, let receivedAt, let network = list.network,
              let scanAge = validAge(network.scanAge),
              let phone, phone.profile.id == viewing, let subnet = network.subnet, let macGateway = network.gatewayIP,
              let phoneGateway = phone.gatewayIP else { return .unavailable }
        guard subnet == phone.profile.subnetCIDR, macGateway == phoneGateway else { return .otherNetwork(name: network.name) }
        guard link.isOnLink(in: phone.profile.network) else { return .unavailable }
        let scanTime = receivedAt.addingTimeInterval(-scanAge)
        guard PresenceFreshness.isRecent(scanTime, now: presence.now, policy: presence.policy) else { return .unavailable }
        return .live(MacInventory(scanTime: scanTime, receivedAt: receivedAt, records: list.devices.map { record($0, receivedAt: receivedAt) }))
    }

    /// An age from the wire, when it is finite and between 0 and `maximumAge`.
    public static func validAge(_ age: TimeInterval?) -> TimeInterval? {
        guard let age, age.isFinite, age >= 0, age <= maximumAge else { return nil }
        return age
    }

    /// "From your Mac · scanned 2 min ago".
    public func sourceText(now: Date) -> String {
        "From your Mac · scanned \(PresenceFreshness.relativeText(since: scanTime, now: max(now, receivedAt)))"
    }

    /// "Seen by this iPhone at 10:42 AM", or "… on Nov 24 at 10:42 AM" before today: the phone's
    /// own sighting, apart from the Mac's.
    public static func phoneSightingText(
        _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        time.timeZone = calendar.timeZone
        guard !calendar.isDate(date, inSameDayAs: now) else { return "Seen by this iPhone at \(date.formatted(time))" }
        var day = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        day.timeZone = calendar.timeZone
        return "Seen by this iPhone on \(date.formatted(day)) at \(date.formatted(time))"
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

        /// None: nothing matched, nothing the Mac's alone.
        public static let none = Matches(recordByDevice: [:], macOnly: [])

        fileprivate init(recordByDevice: [UUID: Record], macOnly: [Record]) {
            self.recordByDevice = recordByDevice
            self.macOnly = macOnly
        }
    }

    /// Matches `devices` (the phone's, one per device) to the records by `PresenceMatch.assign`, each
    /// Mac interface an observation against every phone row. A record whose interfaces land on two
    /// devices, or a device two records want, gets no match, and such a record isn't the Mac's alone
    /// either. A past device (`isPast`) matches only by a shared MAC.
    /// - Parameters:
    ///   - now, window, previousScan: as the reconciler passes them: the phone's clock, its grace
    ///     interval and its network's latest scan.
    public func matches(
        _ devices: [DeviceProjection], now: Date, window: TimeInterval, previousScan: Date?,
        isPast: (DeviceProjection) -> Bool
    ) -> Matches {
        var rows: [(device: Int, row: LocalDevice)] = []
        for (index, device) in devices.enumerated() {
            rows += device.members.map { (index, $0) }
        }
        var observations: [(record: Int, candidate: DeviceMatchCandidate)] = []
        for (index, record) in records.enumerated() {
            observations += record.members.map {
                (index, DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.isPrimary ? record.matchName : nil))
            }
        }
        let assignment = PresenceMatch.assign(
            known: rows.map {
                PresenceMatch.Known(
                    DeviceMatchCandidate(ipAddress: $0.row.ipAddress, macAddress: $0.row.macAddress, name: $0.row.matchName),
                    lastSeen: $0.row.lastSeen
                )
            },
            observed: observations.map(\.candidate), now: now, window: window, previousScan: previousScan
        )
        var devicesByRecord: [Int: Set<Int>] = [:]
        var touched = Set<Int>()
        for (index, assigned) in assignment.enumerated() {
            guard let assigned else { continue }
            let record = observations[index].record, device = rows[assigned].device
            touched.insert(record)
            let byMAC = DeviceMatcher.normalizedMAC(observations[index].candidate.macAddress)
                .map { $0 == DeviceMatcher.normalizedMAC(rows[assigned].row.macAddress) } ?? false
            guard byMAC || !isPast(devices[device]) else { continue }
            devicesByRecord[record, default: []].insert(device)
        }
        var recordsByDevice: [Int: [Int]] = [:]
        for (record, matched) in devicesByRecord where matched.count == 1 {
            if let device = matched.first {
                recordsByDevice[device, default: []].append(record)
            }
        }
        var recordByDevice: [UUID: Record] = [:]
        for (device, matched) in recordsByDevice where matched.count == 1 {
            recordByDevice[devices[device].id] = records[matched[0]]
        }
        let macOnly = records.indices.filter { !touched.contains($0) }.map { records[$0] }
        return Matches(recordByDevice: recordByDevice, macOnly: macOnly)
    }

    // MARK: - Private

    private static func record(_ device: DeviceInfo, receivedAt: Date) -> Record {
        let identity = device.identity?.deviceIdentity ?? DeviceIdentity()
        let members = device.members.map { members in
            members.map { Record.Member(ipAddress: $0.ipAddress, macAddress: $0.macAddress, isPrimary: $0.isPrimary ?? (members.count == 1)) }
        } ?? [Record.Member(ipAddress: device.ipAddress, macAddress: device.macAddress, isPrimary: true)]
        let matchName = [device.hostname, identity.friendlyName?.value].compactMap { $0 }.first { !$0.isEmpty }
        let state: PresenceFreshness = (device.isDeviceOnline ?? device.isOnline) ? .online : .offline
        return Record(
            id: device.id,
            name: [identity.friendlyName?.value, device.hostname].compactMap { $0 }.first { !$0.isEmpty } ?? device.ipAddress,
            matchName: matchName,
            ipAddress: device.ipAddress,
            members: members,
            state: state,
            lastSeen: validAge(device.lastSeenAge).map { receivedAt.addingTimeInterval(-$0) },
            lastChanged: validAge(device.lastChangedAge).map { receivedAt.addingTimeInterval(-$0) },
            maker: identity.resolvedMaker(macPrefixMaker: device.vendor),
            model: identity.model?.value,
            deviceType: DeviceType(rawValue: device.deviceType) ?? .unknown,
            receivedAt: receivedAt
        )
    }
}
