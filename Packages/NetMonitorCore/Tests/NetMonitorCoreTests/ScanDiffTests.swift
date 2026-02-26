import Foundation
import Testing
import NetworkScanKit
@testable import NetMonitorCore

// MARK: - ScanDiff Computed Property Tests (6D)

@Suite("ScanDiff")
struct ScanDiffTests {

    private func makeDevice(ip: String, mac: String? = nil, hostname: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            id: UUID(),
            ipAddress: ip,
            hostname: hostname,
            vendor: nil,
            macAddress: mac,
            latency: 5.0,
            discoveredAt: Date(),
            source: .local
        )
    }

    // MARK: - hasChanges

    @Test("hasChanges is false when all arrays are empty")
    func hasChangesEmptyDiff() {
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        #expect(!diff.hasChanges)
    }

    @Test("hasChanges is true when newDevices is non-empty")
    func hasChangesWithNewDevices() {
        let device = makeDevice(ip: "192.168.1.10")
        let diff = ScanDiff(newDevices: [device], removedDevices: [], changedDevices: [])
        #expect(diff.hasChanges)
    }

    @Test("hasChanges is true when removedDevices is non-empty")
    func hasChangesWithRemovedDevices() {
        let device = makeDevice(ip: "192.168.1.10")
        let diff = ScanDiff(newDevices: [], removedDevices: [device], changedDevices: [])
        #expect(diff.hasChanges)
    }

    @Test("hasChanges is true when changedDevices is non-empty")
    func hasChangesWithChangedDevices() {
        let device = makeDevice(ip: "192.168.1.10")
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [device])
        #expect(diff.hasChanges)
    }

    // MARK: - totalChanges

    @Test("totalChanges is 0 when no changes")
    func totalChangesZero() {
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        #expect(diff.totalChanges == 0)
    }

    @Test("totalChanges sums all three arrays")
    func totalChangesSumsAll() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let d2 = makeDevice(ip: "192.168.1.2")
        let d3 = makeDevice(ip: "192.168.1.3")
        let d4 = makeDevice(ip: "192.168.1.4")
        let diff = ScanDiff(newDevices: [d1, d2], removedDevices: [d3], changedDevices: [d4])
        #expect(diff.totalChanges == 4)
    }

    // MARK: - summaryText

    @Test("summaryText shows 'No changes' when empty")
    func summaryTextNoChanges() {
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        #expect(diff.summaryText == "No changes")
    }

    @Test("summaryText shows new device count")
    func summaryTextNewDevices() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let d2 = makeDevice(ip: "192.168.1.2")
        let diff = ScanDiff(newDevices: [d1, d2], removedDevices: [], changedDevices: [])
        #expect(diff.summaryText == "2 new")
    }

    @Test("summaryText shows offline device count")
    func summaryTextRemovedDevices() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let diff = ScanDiff(newDevices: [], removedDevices: [d1], changedDevices: [])
        #expect(diff.summaryText == "1 offline")
    }

    @Test("summaryText shows changed device count")
    func summaryTextChangedDevices() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let d2 = makeDevice(ip: "192.168.1.2")
        let d3 = makeDevice(ip: "192.168.1.3")
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [d1, d2, d3])
        #expect(diff.summaryText == "3 changed")
    }

    @Test("summaryText combines all categories with commas")
    func summaryTextCombined() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let d2 = makeDevice(ip: "192.168.1.2")
        let d3 = makeDevice(ip: "192.168.1.3")
        let diff = ScanDiff(newDevices: [d1], removedDevices: [d2], changedDevices: [d3])
        #expect(diff.summaryText == "1 new, 1 offline, 1 changed")
    }

    // MARK: - Empty before → all new

    @Test("All devices are 'new' when no prior baseline")
    func emptyBeforeAllNew() {
        let d1 = makeDevice(ip: "192.168.1.1")
        let d2 = makeDevice(ip: "192.168.1.2")
        let diff = ScanDiff(newDevices: [d1, d2], removedDevices: [], changedDevices: [])
        #expect(diff.newDevices.count == 2)
        #expect(diff.removedDevices.isEmpty)
        #expect(diff.changedDevices.isEmpty)
    }

    // MARK: - Same before/after → no changes

    @Test("Same set yields no changes")
    func sameSetNoChanges() {
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        #expect(!diff.hasChanges)
        #expect(diff.totalChanges == 0)
        #expect(diff.summaryText == "No changes")
    }

    // MARK: - Device removed

    @Test("Device removed appears in removedDevices")
    func deviceRemovedInRemovedDevices() {
        let d1 = makeDevice(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:01")
        let diff = ScanDiff(newDevices: [], removedDevices: [d1], changedDevices: [])
        #expect(diff.removedDevices.count == 1)
        #expect(diff.removedDevices.first?.ipAddress == "192.168.1.1")
    }

    // MARK: - Device added

    @Test("Device added appears in newDevices")
    func deviceAddedInNewDevices() {
        let d1 = makeDevice(ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:50")
        let diff = ScanDiff(newDevices: [d1], removedDevices: [], changedDevices: [])
        #expect(diff.newDevices.count == 1)
        #expect(diff.newDevices.first?.macAddress == "AA:BB:CC:DD:EE:50")
    }

    // MARK: - Device changed

    @Test("Device with changed properties appears in changedDevices")
    func deviceChangedInChangedDevices() {
        let d1 = makeDevice(ip: "192.168.1.10", mac: "AA:BB:CC:DD:EE:10", hostname: "new-hostname.local")
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [d1])
        #expect(diff.changedDevices.count == 1)
        #expect(diff.changedDevices.first?.hostname == "new-hostname.local")
    }

    // MARK: - scannedAt

    @Test("scannedAt stores the scan timestamp")
    func scannedAtTimestamp() {
        let date = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [], scannedAt: date)
        #expect(diff.scannedAt == date)
    }

    @Test("scannedAt defaults to near-now")
    func scannedAtDefaultIsNow() {
        let before = Date()
        let diff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        let after = Date()
        #expect(diff.scannedAt >= before)
        #expect(diff.scannedAt <= after)
    }
}
