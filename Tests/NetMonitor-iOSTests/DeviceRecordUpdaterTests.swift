import Foundation
import PDFKit
import SwiftData
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

/// Every finished iOS scan updates the saved device rows (#582), driven by a fake discovery service.
@Suite("DeviceRecordUpdater", .serialized)
@MainActor
struct DeviceRecordUpdaterTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    func makeStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self, MonitoringTarget.self, ToolResult.self, SpeedTestResult.self, PairedMac.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    func device(_ index: Int) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: "192.168.9.\(10 + index)", hostname: "host-\(index)", vendor: nil, macAddress: "AA:00:00:00:09:0\(index)",
            latency: Double(5 + index), discoveredAt: start, source: .local, networkProfileID: home
        )
    }

    func makeUpdater(_ discovery: MockDeviceDiscoveryService, _ context: ModelContext, clock: Clock) -> DeviceRecordUpdater {
        let defaults = UserDefaults(suiteName: "DeviceRecordUpdaterTests.\(UUID().uuidString)") ?? .standard
        return DeviceRecordUpdater(
            discoveryService: discovery,
            reconciler: ScanReconciler(context: context, history: ScanHistory(defaults: defaults)),
            currentNetworkProfileID: { nil },
            clock: { clock.now }
        )
    }

    /// Finishes a fake scan of `devices` at the clock's time and lets the updater see it.
    func finishScan(_ devices: [DiscoveredDevice], on discovery: MockDeviceDiscoveryService, updater: DeviceRecordUpdater, clock: Clock) {
        discovery.isScanning = true
        updater.handleScanChange()
        discovery.discoveredDevices = devices
        discovery.lastScanDate = clock.now
        discovery.isScanning = false
        updater.handleScanChange()
    }

    func rows(_ context: ModelContext) throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>(sortBy: [SortDescriptor(\.ipAddress)]))
    }

    @Test func aFinishedScanSavesEveryDeviceAsOnlineAndJustSeen() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let updater = makeUpdater(discovery, context, clock: clock)

        finishScan([device(0), device(1), device(2)], on: discovery, updater: updater, clock: clock)

        let saved = try rows(context)
        #expect(saved.count == 3)
        #expect(saved.allSatisfy { $0.status == .online && $0.lastSeen == start && $0.networkProfileID == home })
        #expect(saved.map(\.lastLatency) == [5, 6, 7])
    }

    @Test func aDeviceMissingFromLaterScansGoesOfflineAfterGraceAndExportShowsIt() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let updater = makeUpdater(discovery, context, clock: clock)
        finishScan([device(0), device(1)], on: discovery, updater: updater, clock: clock)

        for minutes in [10.0, 20, 30] {
            clock.now = start.addingTimeInterval(minutes * 60)
            finishScan([device(0)], on: discovery, updater: updater, clock: clock)
        }

        let saved = try rows(context)
        #expect(saved[0].status == .online)
        #expect(saved[0].lastSeen == clock.now)
        #expect(saved[1].status == .offline)
        #expect(saved[1].lastSeen == start)

        // The data export reads the rows, so it shows the latest presence.
        let data = try #require(DataExportService.exportDevices(saved, format: .json))
        let exported = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let statuses = exported.compactMap { $0["status"] as? String }.sorted()
        #expect(statuses == ["offline", "online"])

        // So does the PDF report's summary: two devices, one online.
        let pdf = PDFReportGenerator.generateNetworkReport(devices: saved, toolResults: [], speedTests: [])
        let text = (pdf.flatMap(PDFDocument.init(data:))?.string ?? "").replacingOccurrences(of: "\n", with: " ")
        #expect(text.contains("Total Devices 2"), "\(text.prefix(300))")
        #expect(text.contains("Online 1"), "\(text.prefix(300))")
    }

    @Test func aScanSeenTwiceIsSavedOnce() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let updater = makeUpdater(discovery, context, clock: clock)
        finishScan([device(0)], on: discovery, updater: updater, clock: clock)
        clock.now = start.addingTimeInterval(600)
        updater.handleScanChange()
        updater.handleScanChange()
        #expect(try rows(context).first?.lastSeen == start)
    }

    /// The user stopped the scan, or a Wi-Fi switch cancelled it: its partial list is not a result.
    @Test func aStoppedScanSavesNothing() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let updater = makeUpdater(discovery, context, clock: clock)
        finishScan([device(0)], on: discovery, updater: updater, clock: clock)

        clock.now = start.addingTimeInterval(1800)
        discovery.isScanning = true
        updater.handleScanChange()
        discovery.discoveredDevices = [device(0), device(1)]
        discovery.isScanning = false
        updater.handleScanChange()

        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].lastSeen == start)
    }

    /// Upgrade: a scan is saved before the user opens a device an older build saved without a
    /// network or MAC. Detail still opens that row, with its name and notes.
    @Test func aDeviceSavedByAnOlderBuildStillOpensItsRowAfterAScan() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let legacy = LocalDevice(ipAddress: "192.168.9.10", macAddress: "", customName: "NAS")
        legacy.notes = "Backups"
        context.insert(legacy)
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let seen = DiscoveredDevice(
            ipAddress: "192.168.9.10", hostname: nil, vendor: nil, macAddress: nil,
            latency: 5, discoveredAt: start, source: .local, networkProfileID: home
        )
        finishScan([seen, device(1)], on: discovery, updater: makeUpdater(discovery, context, clock: clock), clock: clock)

        let opened = DeviceDetailViewModel.savedRow(
            ipAddress: "192.168.9.10", scanned: seen, networkID: home, scan: discovery.discoveredDevices, in: context
        )

        #expect(opened.id == legacy.id)
        #expect(opened.customName == "NAS")
        #expect(opened.notes == "Backups")
        #expect(opened.networkProfileID == home)
        #expect(try rows(context).count == 2)
    }

    @Test func nothingIsSavedWhileAScanRuns() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let updater = makeUpdater(discovery, context, clock: Clock(start))
        discovery.isScanning = true
        discovery.discoveredDevices = [device(0)]
        discovery.lastScanDate = start
        updater.handleScanChange()
        #expect(try rows(context).isEmpty)
    }
}
