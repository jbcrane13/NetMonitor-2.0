import Foundation
import NetworkScanKit

/// Which saved device each observation of a scan is, for the saved rows on both platforms (#582,
/// #596): the rule `ScanReconciler`, the Mac's sparse merge and iPhone device detail's list entry
/// share, so all of them open and update the same row.
///
/// - An observation with a real MAC (`DeviceMatcher.normalizedMAC`: placeholders such as
///   `02:00:00:00:00:00` and unreadable values count as none) is matched by `DeviceMatcher`: the
///   same MAC, a rotated private MAC with the same name, or a row without a MAC at the same address.
/// - **A match by address** (a row or an observation without a real MAC) follows Blake's intent
///   (2026-11-24): an address alone never proves identity, because DHCP reuses addresses, and a
///   split beats a wrong merge, so notes never move onto another device. As refined by the lead
///   (2026-11-24), a missing name is *unknown*, not a disagreement:
///   - two different names: a different device, a new row;
///   - the same name: the same device;
///   - a name unknown on either side (or both): the same device only if the row was seen at that
///     address within the grace window, or by the network's previous recorded scan when that
///     scan is at most `previousScanReach` (2 h) earlier (it never missed a scan: hourly
///     auto-scan, relaunch, a short sleep; lead, 2026-11-25); otherwise a new row.
///   When the device's name is known, a row with that name beats a nameless one at any age, the
///   most recently seen of several (no new row), so a duplicate made while the name was missing
///   heals. Recency only decides between rows when no name matches: the one seen there most
///   recently among those that count as recent, else a new row.
///
/// `DeviceMatcher` itself is unchanged: the change detector still matches with it alone.
public enum PresenceMatch {
    /// A saved row as the match sees it.
    public struct Known: Sendable, Equatable {
        public let candidate: DeviceMatchCandidate
        /// When the row last answered, at `candidate.ipAddress`.
        public let lastSeen: Date

        public init(_ candidate: DeviceMatchCandidate, lastSeen: Date) {
            self.candidate = candidate
            self.lastSeen = lastSeen
        }
    }

    /// Two different, non-empty names (ignoring case): two different devices.
    public static func namesDiffer(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = named(lhs), let rhs = named(rhs) else { return false }
        return lhs.caseInsensitiveCompare(rhs) != .orderedSame
    }

    /// Whether an observation is the row at its address: see the type's rules.
    static func matchesByAddress(
        _ row: Known, _ observation: DeviceMatchCandidate, now: Date, window: TimeInterval, previousScan: Date? = nil
    ) -> Bool {
        guard row.candidate.ipAddress == observation.ipAddress, !namesDiffer(row.candidate.name, observation.name) else { return false }
        if named(row.candidate.name) != nil, named(observation.name) != nil {
            return true
        }
        return isRecent(row, now: now, window: window, previousScan: previousScan)
    }

    /// How long before a scan the previous recorded scan may be for a row it saw to count as
    /// recent (lead, 2026-11-25): an hourly auto-scan qualifies; days apart, the address may long
    /// since belong to another device, so only the grace window counts.
    public static let previousScanReach: TimeInterval = 2 * 60 * 60

    /// Seen within the window, or by the previous recorded scan when that scan is within
    /// `previousScanReach` (`lastSeen` is stamped with the time a scan was reconciled, which
    /// `ScanHistory` keeps).
    static func isRecent(_ row: Known, now: Date, window: TimeInterval, previousScan: Date? = nil) -> Bool {
        if now.timeIntervalSince(row.lastSeen) <= window {
            return true
        }
        guard let previousScan, now.timeIntervalSince(previousScan) <= previousScanReach else { return false }
        return row.lastSeen >= previousScan
    }

    private static func named(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// The row a device without a MAC is, among rows at its address whose names don't differ.
    /// When its name is known, a row with that name wins at any age (the most recently seen of
    /// several), so a duplicate made while the name was missing heals once it's back. Otherwise
    /// recency decides: the row seen there most recently within the window, else none.
    private static func choose(
        among candidates: [Int], known: [Known], name: String?, now: Date, window: TimeInterval, previousScan: Date?
    ) -> Int? {
        if named(name) != nil {
            let sameName = candidates.filter { named(known[$0].candidate.name) != nil }
            if let row = sameName.max(by: { known[$0].lastSeen < known[$1].lastSeen }) {
                return row
            }
        }
        return candidates.filter { isRecent(known[$0], now: now, window: window, previousScan: previousScan) }
            .max { known[$0].lastSeen < known[$1].lastSeen }
    }

    /// For each observation, the index of the known row it is, or nil for a new device. A known row
    /// goes to at most one observation.
    /// - Parameters:
    ///   - now: when the scan is being matched.
    ///   - window: the grace window (`DeviceGracePolicy.interval`).
    ///   - previousScan: when the network's previous recorded scan was reconciled
    ///     (`ScanHistory.previousReconciled`); a row it saw counts as recent.
    ///   - answeredElsewhere: real MACs another source proved answering at another address in this
    ///     scan (the Mac's sightings, #585): like a MAC observed here, their rows never match by address.
    public static func assign(
        known: [Known], observed: [DeviceMatchCandidate], now: Date, window: TimeInterval, previousScan: Date? = nil,
        answeredElsewhere: Set<String> = []
    ) -> [Int?] {
        var result = [Int?](repeating: nil, count: observed.count)
        var taken = Set<Int>()
        var matcher = DeviceMatcher(known: known.map(\.candidate), observed: observed)
        let observedMACs = Set(observed.compactMap { DeviceMatcher.normalizedMAC($0.macAddress) }).union(answeredElsewhere)

        // Devices with a MAC first, so a newcomer without one can't take the row of a device that
        // moved to another address in the same scan.
        for index in observed.indices where DeviceMatcher.normalizedMAC(observed[index].macAddress) != nil {
            guard let match = matcher.match(observed[index]), !taken.contains(match.index) else { continue }
            // Its MAC became readable at the address of a row without one: a match by address.
            if DeviceMatcher.normalizedMAC(known[match.index].candidate.macAddress) == nil,
               !matchesByAddress(known[match.index], observed[index], now: now, window: window, previousScan: previousScan) {
                continue
            }
            result[index] = match.index
            taken.insert(match.index)
        }

        for index in observed.indices where DeviceMatcher.normalizedMAC(observed[index].macAddress) == nil {
            let observation = observed[index]
            let candidates = known.indices.filter { row in
                let mac = DeviceMatcher.normalizedMAC(known[row].candidate.macAddress)
                return !taken.contains(row)
                    && known[row].candidate.ipAddress == observation.ipAddress
                    && !namesDiffer(known[row].candidate.name, observation.name)
                    // A row whose MAC answered elsewhere in this scan is that device.
                    && !(mac.map(observedMACs.contains) ?? false)
            }
            let chosen = choose(
                among: candidates, known: known, name: observation.name, now: now, window: window, previousScan: previousScan
            )
            guard let row = chosen else { continue }
            result[index] = row
            taken.insert(row)
        }
        return result
    }

    /// One observation per real MAC, at the position of the MAC's first observation. Which one is
    /// kept doesn't depend on the scan's order (#594 PR2, v3.1 §5): one that answered beats a cached
    /// one; then the one at an address where a row in `known` already has that MAC; then the
    /// numerically lowest IPv4. A MAC seen at two addresses (the ARP cache still lists the old one)
    /// is one device. The kept observation carries every collapsed one's Bonjour claims, so no
    /// evidence (or conflict) is lost (#594). Observations without a real MAC are all kept. The
    /// reconciler and iPhone device detail pass the same rows, so both keep the same observation.
    public static func onePerMAC(_ scan: [DiscoveredDevice], known: [LocalDevice] = []) -> [DiscoveredDevice] {
        var knownAddresses: [String: Set<String>] = [:]
        for row in known {
            if let mac = DeviceMatcher.normalizedMAC(row.macAddress) {
                knownAddresses[mac, default: []].insert(row.ipAddress)
            }
        }
        func rank(_ device: DiscoveredDevice, _ mac: String) -> (Int, Int, UInt32, String) {
            (device.isCached ? 1 : 0, knownAddresses[mac]?.contains(device.ipAddress) == true ? 0 : 1,
             NetworkUtilities.ipv4ToUInt32(device.ipAddress) ?? .max, device.ipAddress)
        }
        var indexByMAC: [String: Int] = [:]
        var kept: [DiscoveredDevice] = []
        for device in scan {
            guard let mac = DeviceMatcher.normalizedMAC(device.macAddress) else {
                kept.append(device)
                continue
            }
            guard let index = indexByMAC[mac] else {
                indexByMAC[mac] = kept.count
                kept.append(device)
                continue
            }
            let claims = kept[index].bonjourClaims + device.bonjourClaims.filter { !kept[index].bonjourClaims.contains($0) }
            if rank(device, mac) < rank(kept[index], mac) {
                kept[index] = device
            }
            kept[index] = kept[index].withBonjourClaims(claims)
        }
        return kept
    }
}
