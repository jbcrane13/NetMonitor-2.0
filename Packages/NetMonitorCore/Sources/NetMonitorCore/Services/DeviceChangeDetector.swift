import Foundation

// MARK: - Inputs and outputs

/// One device as a scan saw it (#393).
public struct DeviceObservation: Sendable, Equatable {
    public var ipAddress: String
    public var macAddress: String?
    public var name: String?
    /// No answer this scan; only a cache still lists it (#378). Doesn't confirm the device.
    public var isCached: Bool

    public init(ipAddress: String, macAddress: String?, name: String?, isCached: Bool = false) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.name = name
        self.isCached = isCached
    }
}

/// What the detector remembers about a device between scans (#393).
public struct KnownDevice: Codable, Sendable, Equatable {
    /// Normalised hardware address, or nil when the device has none (then it is keyed by IP).
    public var macAddress: String?
    public var ipAddress: String
    public var name: String?
    public var firstSeen: Date
    /// The last time the device answered a scan.
    public var lastSeen: Date
    /// True once the device has answered a scan; a device only ever cached is not confirmed.
    public var isConfirmed: Bool
    /// Consecutive scans the device didn't answer.
    public var missedScans: Int
    /// Reported offline after the grace period; cleared when it answers again.
    public var isOffline: Bool

    public init(
        macAddress: String?,
        ipAddress: String,
        name: String?,
        firstSeen: Date,
        lastSeen: Date,
        isConfirmed: Bool = true,
        missedScans: Int = 0,
        isOffline: Bool = false
    ) {
        self.macAddress = DeviceChangeDetector.normalizedMAC(macAddress)
        self.ipAddress = ipAddress
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isConfirmed = isConfirmed
        self.missedScans = missedScans
        self.isOffline = isOffline
    }

    var key: String { DeviceChangeDetector.key(mac: macAddress, ip: ipAddress) }
}

/// A change found by comparing a scan with the known devices (#393).
public enum DeviceChangeEvent: Sendable, Equatable {
    /// Answered a scan for the first time. Never sent for the first scan of a network.
    case firstSeen(DeviceObservation)
    /// Answered again after being reported offline.
    case cameOnline(DeviceObservation)
    /// Didn't answer for the whole grace period.
    case wentOffline(KnownDevice)
    /// Answered with a different IP address or name.
    case changed(DeviceObservation, previous: KnownDevice)
}

/// How long a device may go unanswered before it counts as offline. Both limits must be
/// reached, so one missed scan is never enough, however far apart scans are.
public struct DeviceGracePolicy: Sendable, Equatable {
    public var missedScans: Int
    public var interval: TimeInterval

    public init(missedScans: Int = 3, interval: TimeInterval = 15 * 60) {
        self.missedScans = max(2, missedScans)
        self.interval = interval
    }
}

// MARK: - Detector

/// Compares a scan with the devices seen before, with a grace period (#393).
///
/// Identity: a device is keyed by its hardware address, or by IP when it has none (the iOS
/// `02:00:00:00:00:00` placeholder counts as none).
///
/// When a scan's key matches no known device, it is reconciled conservatively, only when
/// exactly one known device qualifies and that device wasn't itself seen in this scan:
/// - A private (randomised) address nobody has seen before matches a known device with the
///   same IP and the same non-empty name. An IP match alone isn't enough for a private
///   address, because DHCP reuses addresses.
/// - A device seen without a MAC matches a known device with a MAC at the same IP (its MAC
///   wasn't readable this time).
/// - A public MAC matches a known IP-keyed device at the same IP (its MAC became readable),
///   which is then keyed by the MAC.
///
/// Unconfirmed (only ever cached) devices not sighted for `unconfirmedRetention` are dropped,
/// so the list can't grow without bound. Confirmed devices are kept: they are what stops a
/// returning device from being reported as new.
public enum DeviceChangeDetector {
    public struct Result: Sendable, Equatable {
        public var events: [DeviceChangeEvent]
        public var known: [KnownDevice]
    }

    /// How long an unconfirmed device is kept without being sighted.
    public static let unconfirmedRetention: TimeInterval = 30 * 86400

    public static func detect(
        known: [KnownDevice],
        observed: [DeviceObservation],
        now: Date,
        policy: DeviceGracePolicy = DeviceGracePolicy()
    ) -> Result {
        // The first scan that confirms any device is the baseline: nothing is "new" yet.
        let isBaseline = !known.contains(where: \.isConfirmed)
        var records = known
        var indexByKey: [String: Int] = [:]
        for (index, record) in records.enumerated() where indexByKey[record.key] == nil {
            indexByKey[record.key] = index
        }

        let observations = deduplicated(observed)
        let observedKeys = Set(observations.map { key(mac: normalizedMAC($0.macAddress), ip: $0.ipAddress) })
        var answered = Set<Int>()
        var claimed = Set<Int>()
        var events: [DeviceChangeEvent] = []

        for observation in observations {
            let mac = normalizedMAC(observation.macAddress)
            let observedKey = key(mac: mac, ip: observation.ipAddress)
            var index = indexByKey[observedKey]

            if index == nil,
               let match = reconciledMatch(for: observation, mac: mac, in: records, observedKeys: observedKeys, claimed: claimed) {
                index = match
                // A device that gained a MAC (or rotated a private one) is keyed by it from now on.
                if let mac {
                    indexByKey[records[match].key] = nil
                    records[match].macAddress = mac
                    indexByKey[observedKey] = match
                }
            }
            if let index {
                claimed.insert(index)
            }

            guard let index else {
                records.append(KnownDevice(
                    macAddress: mac,
                    ipAddress: observation.ipAddress,
                    name: nonEmpty(observation.name),
                    firstSeen: now,
                    lastSeen: now,
                    isConfirmed: !observation.isCached
                ))
                indexByKey[observedKey] = records.count - 1
                if !observation.isCached {
                    answered.insert(records.count - 1)
                    if !isBaseline {
                        events.append(.firstSeen(observation))
                    }
                }
                continue
            }

            // A cached sighting doesn't confirm anything; the miss pass below counts it. For a
            // device never confirmed, it still counts as sighted, for retention.
            guard !observation.isCached else {
                if !records[index].isConfirmed {
                    records[index].lastSeen = now
                }
                continue
            }
            answered.insert(index)
            events += answer(&records[index], with: observation, now: now, isBaseline: isBaseline)
        }

        for index in records.indices where !answered.contains(index) {
            guard records[index].isConfirmed, !records[index].isOffline else { continue }
            records[index].missedScans += 1
            if records[index].missedScans >= policy.missedScans,
               now.timeIntervalSince(records[index].lastSeen) >= policy.interval {
                records[index].isOffline = true
                events.append(.wentOffline(records[index]))
            }
        }

        records.removeAll { !$0.isConfirmed && now.timeIntervalSince($0.lastSeen) > unconfirmedRetention }
        return Result(events: events, known: records)
    }

    /// Updates a known device that answered this scan and returns what changed.
    private static func answer(
        _ record: inout KnownDevice,
        with observation: DeviceObservation,
        now: Date,
        isBaseline: Bool
    ) -> [DeviceChangeEvent] {
        let previous = record
        var events: [DeviceChangeEvent] = []
        if previous.isConfirmed, isChanged(previous, observation) {
            events.append(.changed(observation, previous: previous))
        }
        record.ipAddress = observation.ipAddress
        if let name = nonEmpty(observation.name) {
            record.name = name
        }
        if !previous.isConfirmed {
            record.isConfirmed = true
            if !isBaseline {
                events.append(.firstSeen(observation))
            }
        } else if previous.isOffline {
            events.append(.cameOnline(observation))
        }
        record.lastSeen = now
        record.missedScans = 0
        record.isOffline = false
        return events
    }

    // MARK: Helpers

    /// Uppercase `AA:BB:CC:DD:EE:FF`, or nil for empty, invalid or the iOS placeholder.
    static func normalizedMAC(_ mac: String?) -> String? {
        guard let mac, let octets = MACAddress.octets(of: mac), octets != [0x02, 0, 0, 0, 0, 0],
              octets != [0, 0, 0, 0, 0, 0]
        else { return nil }
        return octets.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func key(mac: String?, ip: String) -> String {
        mac.map { "mac:\($0)" } ?? "ip:\(ip)"
    }

    private static func nonEmpty(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// An IP change, or a name changing from one value to another. A name appearing where
    /// there was none is enrichment, not a change.
    private static func isChanged(_ previous: KnownDevice, _ observation: DeviceObservation) -> Bool {
        if previous.ipAddress != observation.ipAddress {
            return true
        }
        if let old = previous.name, let new = nonEmpty(observation.name), old != new {
            return true
        }
        return false
    }

    /// The one known device an unmatched observation should be treated as, or nil. See the
    /// type's documentation for the rules.
    private static func reconciledMatch(
        for observation: DeviceObservation,
        mac: String?,
        in records: [KnownDevice],
        observedKeys: Set<String>,
        claimed: Set<Int>
    ) -> Int? {
        let available = records.indices.filter {
            records[$0].ipAddress == observation.ipAddress
                && !observedKeys.contains(records[$0].key)
                && !claimed.contains($0)
        }
        let candidates: [Int]
        if let mac, MACAddress.isPrivate(mac) {
            guard let name = nonEmpty(observation.name) else { return nil }
            candidates = available.filter { records[$0].name == name }
        } else if mac == nil {
            candidates = available.filter { records[$0].macAddress != nil }
        } else {
            candidates = available.filter { records[$0].macAddress == nil }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// One observation per key, preferring one that answered over a cached one.
    private static func deduplicated(_ observed: [DeviceObservation]) -> [DeviceObservation] {
        var result: [DeviceObservation] = []
        var indexByKey: [String: Int] = [:]
        for observation in observed {
            let observedKey = key(mac: normalizedMAC(observation.macAddress), ip: observation.ipAddress)
            if let index = indexByKey[observedKey] {
                if result[index].isCached, !observation.isCached {
                    result[index] = observation
                }
            } else {
                indexByKey[observedKey] = result.count
                result.append(observation)
            }
        }
        return result
    }
}

// MARK: - Persistence

/// Keeps known devices per network in UserDefaults and runs the detector (#393).
@MainActor
public final class DeviceChangeTracker {
    static let storageKey = "deviceChangeRegistry"

    private let defaults: UserDefaults
    private let policy: DeviceGracePolicy

    public init(defaults: UserDefaults = .standard, policy: DeviceGracePolicy = DeviceGracePolicy()) {
        self.defaults = defaults
        self.policy = policy
    }

    /// Runs the detector for `scope` (a network) and saves the result. When the scope has
    /// never been stored, `seed` supplies devices known from before this tracker existed,
    /// so an app update doesn't report every existing device as new. When `knownScopes` is
    /// given, stored scopes not in it (networks the app no longer knows) are dropped.
    public func record(
        scope: String,
        observed: [DeviceObservation],
        now: Date = Date(),
        knownScopes: Set<String>? = nil,
        seed: () -> [KnownDevice] = { [] }
    ) -> [DeviceChangeEvent] {
        var registry = load()
        if let knownScopes {
            registry = registry.filter { knownScopes.contains($0.key) || $0.key == scope }
        }
        let known = registry[scope] ?? seed()
        let result = DeviceChangeDetector.detect(known: known, observed: observed, now: now, policy: policy)
        registry[scope] = result.known
        save(registry)
        return result.events
    }

    /// Whether `scope` has stored state yet.
    public func hasState(for scope: String) -> Bool {
        load()[scope] != nil
    }

    public func clearAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() -> [String: [KnownDevice]] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let registry = try? JSONDecoder().decode([String: [KnownDevice]].self, from: data)
        else { return [:] }
        return registry
    }

    private func save(_ registry: [String: [KnownDevice]]) {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
