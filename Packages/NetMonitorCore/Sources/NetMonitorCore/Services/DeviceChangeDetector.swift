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
/// Which known device each observation is comes from ``DeviceMatcher`` (the device match),
/// the same rule the macOS device list uses.
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
        let observations = deduplicated(observed)
        var matcher = DeviceMatcher(known: records.map(\.matchCandidate), observed: observations.map(\.matchCandidate))
        var answered = Set<Int>()
        var events: [DeviceChangeEvent] = []

        for observation in observations {
            let match = matcher.match(observation.matchCandidate)
            // A device that gained a MAC (or rotated a private one) is keyed by it from now on.
            if let match, let mac = match.adoptedMAC {
                records[match.index].macAddress = mac
            }

            guard let index = match?.index else {
                let mac = normalizedMAC(observation.macAddress)
                records.append(newRecord(for: observation, mac: mac, now: now))
                matcher.add(observation.matchCandidate)
                if !observation.isCached {
                    answered.insert(records.count - 1)
                }
                if !observation.isCached, !isBaseline {
                    events.append(.firstSeen(observation))
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

        events += countMisses(&records, answered: answered, now: now, policy: policy)

        records.removeAll { !$0.isConfirmed && now.timeIntervalSince($0.lastSeen) > unconfirmedRetention }
        return Result(events: events, known: records)
    }

    /// Counts a miss for each confirmed device that didn't answer, and reports any that
    /// reach the grace period.
    private static func countMisses(
        _ records: inout [KnownDevice],
        answered: Set<Int>,
        now: Date,
        policy: DeviceGracePolicy
    ) -> [DeviceChangeEvent] {
        var events: [DeviceChangeEvent] = []
        for index in records.indices where !answered.contains(index) {
            guard records[index].isConfirmed, !records[index].isOffline else { continue }
            records[index].missedScans += 1
            if records[index].missedScans >= policy.missedScans,
               now.timeIntervalSince(records[index].lastSeen) >= policy.interval {
                records[index].isOffline = true
                events.append(.wentOffline(records[index]))
            }
        }
        return events
    }

    private static func newRecord(for observation: DeviceObservation, mac: String?, now: Date) -> KnownDevice {
        KnownDevice(
            macAddress: mac,
            ipAddress: observation.ipAddress,
            name: nonEmpty(observation.name),
            firstSeen: now,
            lastSeen: now,
            isConfirmed: !observation.isCached
        )
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

    static func normalizedMAC(_ mac: String?) -> String? {
        DeviceMatcher.normalizedMAC(mac)
    }

    static func key(mac: String?, ip: String) -> String {
        DeviceMatcher.key(mac: mac, ip: ip)
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

extension DeviceObservation {
    var matchCandidate: DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: ipAddress, macAddress: macAddress, name: name.flatMap { $0.isEmpty ? nil : $0 })
    }
}

extension KnownDevice {
    var matchCandidate: DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: ipAddress, macAddress: macAddress, name: name)
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

    /// Forgets the scans `scope`'s devices have missed, keeping who they are and whether they
    /// went offline: for a new owner of the grace count (the Mac's `ScanHistory` after an update,
    /// #596), so "went offline" waits for the same misses the saved rows count.
    public func forgetMisses(for scope: String) {
        var registry = load()
        guard var known = registry[scope] else { return }
        for index in known.indices where !known[index].isOffline {
            known[index].missedScans = 0
        }
        registry[scope] = known
        save(registry)
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
