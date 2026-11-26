import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// #594 PR2 (design v3 §3, v3.1): automatic grouping only on same-scan, conflict-free evidence.
@Suite("Device grouping plan")
struct DeviceGroupingPlanTests {
    let network = UUID()

    func row(_ ip: String, model: String? = nil, vendor: String? = nil, group: UUID? = nil, excluding: [UUID]? = nil) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", vendor: vendor, networkProfileID: network)
        row.modelName = model
        row.deviceGroupID = group
        row.groupPrimaryID = group == nil ? nil : row.id
        row.notSameAsIDs = excluding
        return row
    }

    func seen(_ ip: String, mac: String? = nil, hosts: [String], cached: Bool = false, model: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: "Studio", vendor: nil, macAddress: mac, latency: 2, discoveredAt: Date(), source: .bonjour,
            isCached: cached, identity: DeviceIdentity(model: IdentityValue(model, source: .bonjour)),
            bonjourClaims: hosts.map { HostClaim(host: $0, service: "Studio", address: ip) }
        )
    }

    func plan(_ scan: [DiscoveredDevice], _ rows: [LocalDevice]) -> [Set<UUID>] {
        DeviceGrouping.plan(scan: scan, rowForAddress: Dictionary(uniqueKeysWithValues: rows.map { ($0.ipAddress, $0.id) }), rows: rows)
    }

    @Test("One strong host answering on two addresses in this scan groups their rows")
    func groupsTwoAddresses() {
        let wired = row("10.0.0.10"), wifi = row("10.0.0.40")
        let scan = [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])]
        #expect(plan(scan, [wired, wifi]) == [[wired.id, wifi.id]])
    }

    @Test("Three addresses of one host make one group of three")
    func groupsThree() {
        let rows = [row("10.0.0.10"), row("10.0.0.40"), row("10.0.0.41")]
        let scan = rows.map { seen($0.ipAddress, hosts: ["studio.local"]) }
        #expect(plan(scan, rows) == [Set(rows.map(\.id))])
    }

    @Test("No grouping", arguments: [
        "generic", "otherHost", "suffixHost", "addressClaimsTwo", "macClaimsTwo", "excluded", "twoGroups", "models", "makers",
        "historyOnly", "cached", "oneRow"
    ])
    func noGrouping(reason: String) {
        let first = row("10.0.0.10", model: reason == "models" ? "Macmini9,1" : nil, vendor: reason == "makers" ? "Apple, Inc." : nil)
        let second = row(
            "10.0.0.40", model: reason == "models" ? "Mac16,10" : nil, vendor: reason == "makers" ? "Samsung Electronics" : nil,
            group: reason == "twoGroups" ? UUID() : nil, excluding: reason == "excluded" ? [first.id] : nil
        )
        if reason == "twoGroups" {
            first.deviceGroupID = UUID()
        }
        if reason == "excluded" {
            first.notSameAsIDs = [second.id]
        }
        let host = reason == "generic" ? "iphone.local" : "studio.local"
        var scan: [DiscoveredDevice] = switch reason {
        case "otherHost": [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["office.local"])]
        case "suffixHost": [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio-2.local"])]
        case "addressClaimsTwo": [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local", "office.local"])]
        case "macClaimsTwo": [
                seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", mac: "AA:BB:CC:00:00:01", hosts: ["studio.local"]),
                seen("10.0.0.41", mac: "AA:BB:CC:00:00:01", hosts: ["office.local"])
            ]
        case "historyOnly": [seen("10.0.0.10", hosts: ["studio.local"])]
        case "cached": [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"], cached: true)]
        case "oneRow": [seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])]
        default: [seen("10.0.0.10", hosts: [host]), seen("10.0.0.40", hosts: [host])]
        }
        if reason == "historyOnly" {
            second.bonjourHost = "studio.local"
            second.bonjourHostSeenAt = Date()
        }
        var mapping = ["10.0.0.10": first.id, "10.0.0.40": second.id]
        if reason == "oneRow" {
            mapping["10.0.0.40"] = first.id
        }
        if reason == "macClaimsTwo" {
            mapping["10.0.0.41"] = second.id
        }
        scan = scan.map { $0 }
        #expect(DeviceGrouping.plan(scan: scan, rowForAddress: mapping, rows: [first, second]).isEmpty, "\(reason)")
    }

    @Test("Rows two members of one existing group and a new row: the new row joins, user content on both doesn't block")
    func joinsOneExistingGroup() {
        let group = UUID()
        let wired = row("10.0.0.10", group: group), spare = row("10.0.0.11", group: group), wifi = row("10.0.0.40")
        wired.notes = "desk"
        wifi.notes = "undocked"
        let result = plan([seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], [wired, spare, wifi])
        #expect(result == [[wired.id, wifi.id]])
    }

    @Test("A quiet member of the existing group counts: an Apple primary and a Samsung newcomer never group (#619)")
    func identityAcrossTheWholeGroup() {
        let group = UUID()
        let apple = row("10.0.0.10", vendor: "Apple, Inc.", group: group)
        let unidentified = row("10.0.0.11", group: group)
        unidentified.groupPrimaryID = apple.id
        let samsung = row("10.0.0.40", vendor: "Samsung Electronics")
        let scan = [seen("10.0.0.11", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])]
        #expect(plan(scan, [apple, unidentified, samsung]).isEmpty)
        apple.vendor = nil
        apple.modelName = "Macmini9,1"
        samsung.vendor = nil
        samsung.modelName = "SM-G991B"
        #expect(plan(scan, [apple, unidentified, samsung]).isEmpty, "models too")
    }

    @Test("The plan doesn't depend on the scan's order (every permutation, repeated MACs and a conflicting claim)")
    func permutations() {
        let rows = [row("10.0.0.10"), row("10.0.0.40"), row("10.0.0.50"), row("10.0.0.60")]
        var mapping = Dictionary(uniqueKeysWithValues: rows.map { ($0.ipAddress, $0.id) })
        mapping["10.0.0.41"] = rows[1].id
        let scan = [
            seen("10.0.0.10", hosts: ["studio.local"]),
            seen("10.0.0.40", mac: "AA:BB:CC:00:00:02", hosts: ["studio.local"]),
            seen("10.0.0.41", mac: "AA:BB:CC:00:00:02", hosts: ["studio.local"]),
            seen("10.0.0.50", hosts: ["printer-room.local"]),
            seen("10.0.0.60", hosts: ["printer-room.local", "office.local"])
        ]
        let expected = DeviceGrouping.plan(scan: scan, rowForAddress: mapping, rows: rows)
        #expect(expected == [[rows[0].id, rows[1].id]])
        for order in Self.permutations(of: Array(scan.indices)) {
            #expect(DeviceGrouping.plan(scan: order.map { scan[$0] }, rowForAddress: mapping, rows: rows) == expected)
        }
    }

    static func permutations(of items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { index in
            var rest = items
            let first = rest.remove(at: index)
            return permutations(of: rest).map { [first] + $0 }
        }
    }
}
