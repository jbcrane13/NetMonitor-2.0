import Foundation
import PDFKit
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

/// #583: the PDF report's device table says each device's presence and last seen as of the
/// latest scan, and counts past devices instead of listing them.
@Suite("PDF report presence")
@MainActor
struct PDFReportPresenceTests {
    private let home = UUID()
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func store() -> (devices: [LocalDevice], presence: PresenceSnapshot) {
        let online = LocalDevice(ipAddress: "192.168.1.10", macAddress: "", customName: "Laptop", status: .online, networkProfileID: home)
        online.lastSeen = scan
        let offline = LocalDevice(ipAddress: "192.168.1.11", macAddress: "", customName: "Printer", status: .offline, networkProfileID: home)
        offline.lastSeen = scan - 3600
        let past = LocalDevice(ipAddress: "192.168.1.12", macAddress: "", customName: "Old TV", status: .offline, networkProfileID: home)
        past.lastSeen = scan - 8 * 86400
        return ([online, offline, past], PresenceSnapshot(lastScans: [home: scan], now: scan + 300))
    }

    /// The report's text on one line.
    private func text(_ devices: [LocalDevice], _ presence: PresenceSnapshot) -> String {
        let data = PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: [], speedTests: [], presence: presence)
        return (data.flatMap { PDFDocument(data: $0)?.string } ?? "").replacingOccurrences(of: "\n", with: " ")
    }

    @Test func theDeviceTableShowsEachDevicesPresenceAndLastSeenAsOfTheLatestScan() {
        let (devices, presence) = store()
        let report = text(devices, presence)
        #expect(report.contains("Laptop"))
        #expect(report.contains("Online 5 min ago"), "status and last seen of the online device: \(report)")
        #expect(report.contains("Offline 1 hour ago"))
        // PDF text turns the time's narrow no-break space into a space, so compare without spaces.
        let squeezed = report.filter { !$0.isWhitespace }
        #expect(squeezed.contains(PDFReportGenerator.statusAsOf(devices, presence: presence).filter { !$0.isWhitespace }))
        #expect(report.contains("latest scan at"))
    }

    @Test func pastDevicesAreCountedNotListed() {
        let (devices, presence) = store()
        let report = text(devices, presence)
        #expect(!report.contains("Old TV"), "a past device is not listed")
        #expect(report.contains("1 past device (not seen for 7 days) not listed."))
        #expect(report.contains("Past Devices 1"))
        #expect(report.contains("Discovered Devices (2)"))
    }

    @Test func aStaleScanMakesNoDeviceOnline() {
        let (devices, presence) = store()
        let later = PresenceSnapshot(lastScans: [home: presence.now - 300], now: presence.now + 3600)
        let report = text(devices, later)
        #expect(report.contains("Online 0"))
        #expect(report.contains("Not checked recently"))
    }
}
