import Foundation
import NetworkScanKit

/// Automatic grouping (#594 PR2, design v3 §3, v3.1 §5 and §8): which saved rows one scan shows to
/// be one device's interfaces. Only same-scan, conflict-free evidence groups; everything else is at
/// most a suggestion (`DeviceGroups.suggestions`).
///
/// A strong Bonjour host (`BonjourHostName.isGeneric` false, full name, conflict suffix kept)
/// groups the rows its addresses were matched to when **all** of these hold:
/// - it was claimed by answering (not cached) observations at two or more addresses this scan, and
///   they were matched to two or more distinct rows;
/// - none of those addresses, and no real MAC among their observations, claimed another strong host;
/// - no pair of those rows, or of the members of a group one of them is in, is excluded
///   (`notSameAsIDs`);
/// - the models and MAC-prefix makers of every row of the resulting group (a quiet member of an
///   existing group included) don't name different devices or companies;
/// - they are in at most one existing group (two groups never merge automatically).
///
/// The plan reads every claim before deciding anything, so it doesn't depend on the scan's order.
public enum DeviceGrouping {
    /// One set of row IDs per host that groups, in host order.
    /// - Parameters:
    ///   - scan: the scan as it came, before `onePerMAC`, so no claim is lost.
    ///   - rowForAddress: the row each answering observation's address was matched to (a collapsed
    ///     duplicate MAC's address maps to its MAC's row).
    ///   - rows: the network's rows, with their groups, exclusions, models and makers.
    public static func plan(scan: [DiscoveredDevice], rowForAddress: [String: UUID], rows: [LocalDevice]) -> [Set<UUID>] {
        let answering = scan.filter { !$0.isCached }
        var addressesByHost: [String: Set<String>] = [:]
        var hostsByAddress: [String: Set<String>] = [:]
        var hostsByMAC: [String: Set<String>] = [:]
        for observation in answering {
            let hosts = Set(observation.bonjourClaims.map(\.host).filter {
                !BonjourHostName.isGeneric($0, maker: observation.maker, model: observation.modelName)
            })
            guard !hosts.isEmpty else { continue }
            hostsByAddress[observation.ipAddress, default: []].formUnion(hosts)
            if let mac = DeviceMatcher.normalizedMAC(observation.macAddress) {
                hostsByMAC[mac, default: []].formUnion(hosts)
            }
            for host in hosts {
                addressesByHost[host, default: []].insert(observation.ipAddress)
            }
        }
        let rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [Set<UUID>] = []
        for host in addressesByHost.keys.sorted() {
            guard let addresses = addressesByHost[host] else { continue }
            let conflicted = addresses.contains { (hostsByAddress[$0]?.count ?? 0) > 1 }
                || answering.contains { observation in
                    addresses.contains(observation.ipAddress)
                        && DeviceMatcher.normalizedMAC(observation.macAddress).map { (hostsByMAC[$0]?.count ?? 0) > 1 } == true
                }
            guard !conflicted else { continue }
            let ids = Set(addresses.compactMap { rowForAddress[$0] })
            let members = ids.compactMap { rowsByID[$0] }
            guard members.count >= 2, isEligible(members, among: rows) else { continue }
            groups.append(ids)
        }
        return groups
    }

    /// Exclusions, conflicting models or makers, or two existing groups stop a group. Every row of
    /// the resulting group counts, answering or not (#619).
    static func isEligible(_ members: [LocalDevice], among rows: [LocalDevice]) -> Bool {
        let result = DeviceGroups.withGroupMembers(members, among: rows)
        return Set(members.compactMap(\.deviceGroupID)).count <= 1
            && DeviceGroups.excludedPair(in: result) == nil
            && !hasConflictingIdentity(result)
    }

    /// Whether `rows` name two different models, or makers from two different companies.
    static func hasConflictingIdentity(_ rows: [LocalDevice]) -> Bool {
        Set(rows.compactMap(\.modelName).filter { !$0.isEmpty }).count > 1
            || Set(rows.compactMap(\.vendor).filter { !$0.isEmpty }.map(firstWord)).count > 1
    }

    /// A maker's first word, lowercased: "Apple, Inc." and "Apple" are one company.
    static func firstWord(_ name: String) -> String {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.first.map(String.init) ?? name.lowercased()
    }
}
