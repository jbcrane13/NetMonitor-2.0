import Foundation

/// A device as the device match sees it: a scan observation or a saved device.
public struct DeviceMatchCandidate: Sendable, Equatable {
    public var ipAddress: String
    public var macAddress: String?
    /// The device's hostname, when it has one. Only private-MAC rotation compares it.
    public var name: String?

    public init(ipAddress: String, macAddress: String?, name: String?) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.name = name
    }
}

/// Decides which known device each observation from a scan is (the device match, #461).
///
/// A device is keyed by its normalized MAC, or by IP when it has none. Placeholder MACs
/// (`00:00:00:00:00:00`, iOS's `02:00:00:00:00:00`) and unreadable ones count as none.
///
/// An observation whose key matches no known device is reconciled conservatively, only when
/// exactly one known device qualifies, that device wasn't itself seen under its own key this
/// scan, and no earlier observation claimed it:
/// - A private (randomized) MAC matches a known device with the same IP and the same
///   non-empty name. An IP match alone isn't enough, because DHCP reuses addresses.
/// - An observation without a MAC matches a known device with a MAC at the same IP (its MAC
///   wasn't readable this time).
/// - A public MAC matches a known device without a MAC at the same IP (its MAC became
///   readable). That device is keyed by the MAC from then on.
///
/// The caller decides whether an unmatched observation becomes a device; when it does, it
/// calls ``add(_:)`` so later observations with the same key match it.
public struct DeviceMatcher: Sendable {
    /// A known device an observation matched.
    public struct Match: Sendable, Equatable {
        /// Index into the known devices (including ones added with ``add(_:)``).
        public var index: Int
        /// The normalized MAC the device is keyed by from now on, when the match gave it one
        /// it didn't have (it gained a MAC, or rotated a private one). Callers store it.
        public var adoptedMAC: String?
    }

    private var known: [DeviceMatchCandidate]
    private var indexByKey: [String: Int] = [:]
    private let observedKeys: Set<String>
    private var claimed: Set<Int> = []

    /// - Parameters:
    ///   - known: The saved devices, in the caller's order; ``Match/index`` refers to it.
    ///   - observed: Every observation of this scan, so a known device seen under its own key
    ///     is never reconciled away to a different observation.
    public init(known: [DeviceMatchCandidate], observed: [DeviceMatchCandidate]) {
        self.known = known.map {
            DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: Self.normalizedMAC($0.macAddress), name: $0.name)
        }
        observedKeys = Set(observed.map { Self.key(mac: Self.normalizedMAC($0.macAddress), ip: $0.ipAddress) })
        for (index, device) in self.known.enumerated() {
            let key = Self.key(mac: device.macAddress, ip: device.ipAddress)
            if indexByKey[key] == nil {
                indexByKey[key] = index
            }
        }
    }

    /// The known device `observation` is, or nil when it is a new device. A known device is
    /// reconciled to at most one observation; an exact key match always matches.
    public mutating func match(_ observation: DeviceMatchCandidate) -> Match? {
        let mac = Self.normalizedMAC(observation.macAddress)
        let observedKey = Self.key(mac: mac, ip: observation.ipAddress)
        if let index = indexByKey[observedKey] {
            claimed.insert(index)
            return Match(index: index, adoptedMAC: nil)
        }
        guard let index = reconciledMatch(for: observation, mac: mac, observedKey: observedKey) else { return nil }
        claimed.insert(index)
        guard let mac else { return Match(index: index, adoptedMAC: nil) }
        indexByKey[Self.key(mac: known[index].macAddress, ip: known[index].ipAddress)] = nil
        known[index].macAddress = mac
        indexByKey[observedKey] = index
        return Match(index: index, adoptedMAC: mac)
    }

    /// Registers `observation` as a new known device and returns its index.
    @discardableResult
    public mutating func add(_ observation: DeviceMatchCandidate) -> Int {
        let mac = Self.normalizedMAC(observation.macAddress)
        known.append(DeviceMatchCandidate(ipAddress: observation.ipAddress, macAddress: mac, name: observation.name))
        let index = known.count - 1
        indexByKey[Self.key(mac: mac, ip: observation.ipAddress)] = index
        claimed.insert(index)
        return index
    }

    // MARK: Keys

    /// Uppercase `AA:BB:CC:DD:EE:FF`, or nil for empty, invalid or placeholder addresses.
    public static func normalizedMAC(_ mac: String?) -> String? {
        guard let mac, let octets = MACAddress.octets(of: mac), octets != [0x02, 0, 0, 0, 0, 0],
              octets != [0, 0, 0, 0, 0, 0]
        else { return nil }
        return octets.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func key(mac: String?, ip: String) -> String {
        mac.map { "mac:\($0)" } ?? "ip:\(ip)"
    }

    // MARK: Reconciliation

    /// Two different non-empty names: a different device took the address (DHCP reuse).
    static func namesConflict(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.caseInsensitiveCompare(rhs) != .orderedSame
    }

    private func reconciledMatch(for observation: DeviceMatchCandidate, mac: String?, observedKey: String) -> Int? {
        let available = known.indices.filter {
            known[$0].ipAddress == observation.ipAddress
                && !observedKeys.contains(Self.key(mac: known[$0].macAddress, ip: known[$0].ipAddress))
                && !claimed.contains($0)
        }
        let candidates: [Int]
        if let mac, MACAddress.isPrivate(mac) {
            guard let name = observation.name, !name.isEmpty else { return nil }
            candidates = available.filter { known[$0].name == name }
        } else if mac == nil {
            candidates = available.filter { known[$0].macAddress != nil && !Self.namesConflict(known[$0].name, observation.name) }
        } else {
            candidates = available.filter { known[$0].macAddress == nil && !Self.namesConflict(known[$0].name, observation.name) }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
