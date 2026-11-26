import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// #594 PR2: "Same Bonjour name as X: same device?" from stored evidence, within 30 days.
@Suite("Device group suggestions")
struct DeviceGroupSuggestionTests {
    let network = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func row(_ ip: String, host: String?, daysAgo: Double = 1, network: UUID? = nil) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", networkProfileID: network ?? self.network)
        row.bonjourHost = host
        row.bonjourHostSeenAt = host == nil ? nil : now.addingTimeInterval(-daysAgo * 86400)
        return row
    }

    func suggested(_ subject: LocalDevice, _ rows: [LocalDevice]) -> [UUID] {
        DeviceGroups.suggestions(for: DeviceGroups.project([subject])[0], among: rows, now: now).map(\.id)
    }

    @Test("Another device seen for the same host within 30 days is suggested")
    func sameHostSuggested() {
        let wired = row("10.0.0.10", host: "studio.local"), wifi = row("10.0.0.40", host: "studio.local", daysAgo: 29)
        #expect(suggested(wired, [wired, wifi]) == [wifi.id])
    }

    @Test("Not suggested", arguments: ["old", "otherHost", "generic", "excluded", "otherNetwork", "noHost"])
    func notSuggested(reason: String) {
        let wired = row("10.0.0.10", host: reason == "generic" ? "iphone.local" : reason == "noHost" ? nil : "studio.local")
        let wifi = row(
            "10.0.0.40", host: reason == "otherHost" ? "office.local" : reason == "generic" ? "iphone.local" : "studio.local",
            daysAgo: reason == "old" ? 31 : 1, network: reason == "otherNetwork" ? UUID() : nil
        )
        if reason == "excluded" {
            wired.notSameAsIDs = [wifi.id]
        }
        #expect(suggested(wired, [wired, wifi]).isEmpty, "\(reason)")
    }
}
