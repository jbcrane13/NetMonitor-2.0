import Foundation
import Testing
@testable import NetMonitorCore

/// #594 PR2: the picker, its search and the wording both apps share.
@Suite("Device grouping choices")
struct DeviceGroupingChoicesTests {
    let network = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func row(_ ip: String, name: String, host: String? = nil, network: UUID? = nil, mac: String = "") -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, customName: name, networkProfileID: network ?? self.network)
        row.bonjourHost = host
        row.bonjourHostSeenAt = host == nil ? nil : now
        return row
    }

    @Test("Suggestions first, then the rest by name, on the device's network only; search matches any interface")
    func candidatesOrderAndSearch() {
        let studio = row("10.0.0.10", name: "Studio", host: "studio.local")
        let wifi = row("10.0.0.40", name: "Zeta wifi", host: "studio.local")
        let printer = row("10.0.0.50", name: "Printer", mac: "AA:BB:CC:00:00:50")
        let alpha = row("10.0.0.60", name: "Alpha")
        let elsewhere = row("10.0.0.70", name: "Elsewhere", network: UUID())
        let rows = [studio, wifi, printer, alpha, elsewhere]
        let device = DeviceGroups.project([studio])[0]
        #expect(DeviceGroupingChoices.candidates(for: device, among: rows, now: now).map(\.displayName) == ["Zeta wifi", "Alpha", "Printer"])
        #expect(DeviceGroupingChoices.candidates(for: device, among: rows, now: now, search: "aa:bb").map(\.displayName) == ["Printer"])
        #expect(DeviceGroupingChoices.candidates(for: device, among: rows, now: now, search: "0.60").map(\.displayName) == ["Alpha"])
    }

    @Test("Same device as… groups the shown device's primary with the other's")
    func rowIDs() {
        let studio = DeviceGroups.project([row("10.0.0.10", name: "Studio")])[0]
        let wifi = DeviceGroups.project([row("10.0.0.40", name: "Wifi")])[0]
        #expect(DeviceGroupingChoices.rowIDs(joining: wifi, to: studio) == [studio.primary.id, wifi.primary.id])
    }

    @Test("Only an automatic grouping is labelled")
    func label() {
        let member = row("10.0.0.10", name: "Studio")
        member.groupSource = "bonjour"
        #expect(DeviceGroupingChoices.label(for: member) == "Grouped by Bonjour name")
        member.groupSource = "user"
        #expect(DeviceGroupingChoices.label(for: member) == nil)
    }

    @Test("Repeated controls' IDs: underscores for an address, the device's ID for a banner")
    func accessibilityIDs() {
        #expect(DeviceGroupingChoices.AccessibilityID.sameDeviceAsRow("192.168.1.12") == "sameDeviceAs_row_192_168_1_12")
        let id = UUID()
        #expect(DeviceGroupingChoices.AccessibilityID.suggestionBanner(id) == "deviceDetail_banner_suggestion_\(id.uuidString)")
    }
}
