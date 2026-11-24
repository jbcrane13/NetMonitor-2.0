import Foundation

/// Which saved device each observation of a scan is, for the iPhone's saved rows (#582): the rule
/// `ScanReconciler` and device detail's list entry share, so both open and update the same row.
///
/// - An observation with a real MAC (`DeviceMatcher.normalizedMAC`: placeholders such as
///   `02:00:00:00:00:00` and unreadable values count as none) is matched by `DeviceMatcher`: the
///   same MAC, a rotated private MAC with the same name, or a row without a MAC at the same address.
/// - Blake's rule for devices without a MAC (2026-11-24): an address alone never proves identity,
///   because DHCP reuses addresses. A row and an observation of which at least one has no MAC are
///   the same device only at the same address **and** with names that agree. Otherwise the
///   observation is a new device, and the old row is left alone (its name and notes never move
///   onto another device) to go offline under the grace policy.
///
/// Names agree when both are missing, or both are present and equal ignoring case. A name on one
/// side only does not agree. `DeviceMatcher` itself is unchanged: the Mac and the change detector
/// share it.
public enum PresenceMatch {
    /// Whether two names say the device could be the same.
    public static func namesAgree(_ lhs: String?, _ rhs: String?) -> Bool {
        let lhs = lhs.flatMap { $0.isEmpty ? nil : $0 }
        let rhs = rhs.flatMap { $0.isEmpty ? nil : $0 }
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default: return false
        }
    }

    /// For each observation, the index of the known device it is, or nil for a new device. A known
    /// device goes to at most one observation. Among several rows that could take an observation
    /// without a MAC, one without a MAC is preferred, then the earliest in `known` (callers list the
    /// most recently seen first).
    public static func assign(known: [DeviceMatchCandidate], observed: [DeviceMatchCandidate]) -> [Int?] {
        var result = [Int?](repeating: nil, count: observed.count)
        var taken = Set<Int>()
        var matcher = DeviceMatcher(known: known, observed: observed)
        let observedMACs = Set(observed.compactMap { DeviceMatcher.normalizedMAC($0.macAddress) })

        // Devices with a MAC first, so a newcomer without one can't take the row of a device that
        // moved to another address in the same scan.
        for index in observed.indices where DeviceMatcher.normalizedMAC(observed[index].macAddress) != nil {
            guard let match = matcher.match(observed[index]), !taken.contains(match.index) else { continue }
            // Its MAC became readable at a row's address: only the same name proves it's that row.
            if DeviceMatcher.normalizedMAC(known[match.index].macAddress) == nil,
               !namesAgree(known[match.index].name, observed[index].name) {
                continue
            }
            result[index] = match.index
            taken.insert(match.index)
        }

        for index in observed.indices where DeviceMatcher.normalizedMAC(observed[index].macAddress) == nil {
            let observation = observed[index]
            let candidates = known.indices.filter { row in
                let mac = DeviceMatcher.normalizedMAC(known[row].macAddress)
                return !taken.contains(row)
                    && known[row].ipAddress == observation.ipAddress
                    && namesAgree(known[row].name, observation.name)
                    // A row whose MAC answered elsewhere in this scan is that device.
                    && !(mac.map(observedMACs.contains) ?? false)
            }
            guard let row = candidates.first(where: { DeviceMatcher.normalizedMAC(known[$0].macAddress) == nil }) ?? candidates.first
            else { continue }
            result[index] = row
            taken.insert(row)
        }
        return result
    }
}
