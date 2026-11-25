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
///     address within the grace window (it never left); otherwise a new row.
///   When the device's name is known, a row with that name beats a nameless one at any age, the
///   most recently seen of several (no new row), so a duplicate made while the name was missing
///   heals. Recency only decides between rows when no name matches: the one seen there most
///   recently within the window, else a new row.
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
    static func matchesByAddress(_ row: Known, _ observation: DeviceMatchCandidate, now: Date, window: TimeInterval) -> Bool {
        guard row.candidate.ipAddress == observation.ipAddress, !namesDiffer(row.candidate.name, observation.name) else { return false }
        if named(row.candidate.name) != nil, named(observation.name) != nil {
            return true
        }
        return isRecent(row, now: now, window: window)
    }

    static func isRecent(_ row: Known, now: Date, window: TimeInterval) -> Bool {
        now.timeIntervalSince(row.lastSeen) <= window
    }

    private static func named(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// The row a device without a MAC is, among rows at its address whose names don't differ.
    /// When its name is known, a row with that name wins at any age (the most recently seen of
    /// several), so a duplicate made while the name was missing heals once it's back. Otherwise
    /// recency decides: the row seen there most recently within the window, else none.
    private static func choose(among candidates: [Int], known: [Known], name: String?, now: Date, window: TimeInterval) -> Int? {
        if named(name) != nil {
            let sameName = candidates.filter { named(known[$0].candidate.name) != nil }
            if let row = sameName.max(by: { known[$0].lastSeen < known[$1].lastSeen }) {
                return row
            }
        }
        return candidates.filter { isRecent(known[$0], now: now, window: window) }
            .max { known[$0].lastSeen < known[$1].lastSeen }
    }

    /// For each observation, the index of the known row it is, or nil for a new device. A known row
    /// goes to at most one observation.
    /// - Parameters:
    ///   - now: when the scan is being matched.
    ///   - window: the grace window (`DeviceGracePolicy.interval`).
    public static func assign(known: [Known], observed: [DeviceMatchCandidate], now: Date, window: TimeInterval) -> [Int?] {
        var result = [Int?](repeating: nil, count: observed.count)
        var taken = Set<Int>()
        var matcher = DeviceMatcher(known: known.map(\.candidate), observed: observed)
        let observedMACs = Set(observed.compactMap { DeviceMatcher.normalizedMAC($0.macAddress) })

        // Devices with a MAC first, so a newcomer without one can't take the row of a device that
        // moved to another address in the same scan.
        for index in observed.indices where DeviceMatcher.normalizedMAC(observed[index].macAddress) != nil {
            guard let match = matcher.match(observed[index]), !taken.contains(match.index) else { continue }
            // Its MAC became readable at the address of a row without one: a match by address.
            if DeviceMatcher.normalizedMAC(known[match.index].candidate.macAddress) == nil,
               !matchesByAddress(known[match.index], observed[index], now: now, window: window) {
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
            let chosen = choose(among: candidates, known: known, name: observation.name, now: now, window: window)
            guard let row = chosen else { continue }
            result[index] = row
            taken.insert(row)
        }
        return result
    }

    /// One observation per real MAC, in scan order: the one that answered, else the first. A MAC
    /// seen at two addresses (the ARP cache still lists the old one) is one device, at the address
    /// it answered from. Observations without a real MAC are all kept.
    public static func onePerMAC(_ scan: [DiscoveredDevice]) -> [DiscoveredDevice] {
        var indexByMAC: [String: Int] = [:]
        var kept: [DiscoveredDevice] = []
        for device in scan {
            guard let mac = DeviceMatcher.normalizedMAC(device.macAddress) else {
                kept.append(device)
                continue
            }
            if let index = indexByMAC[mac] {
                if kept[index].isCached, !device.isCached {
                    kept[index] = device
                }
            } else {
                indexByMAC[mac] = kept.count
                kept.append(device)
            }
        }
        return kept
    }
}
