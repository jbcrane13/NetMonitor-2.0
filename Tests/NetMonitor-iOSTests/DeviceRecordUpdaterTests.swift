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
final class DeviceRecordUpdaterTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// This test's own defaults suite for the scan history, removed when the test ends.
    nonisolated let suiteName = "DeviceRecordUpdaterTests.\(UUID().uuidString)"

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

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

    func makeReconciler(
        _ context: ModelContext,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ScanReconciler {
        try ScanReconciler(context: context, history: ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName))), save: save)
    }

    func makeUpdater(
        _ discovery: MockDeviceDiscoveryService, _ context: ModelContext, clock: Clock,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> DeviceRecordUpdater {
        try DeviceRecordUpdater(
            discoveryService: discovery,
            reconciler: makeReconciler(context, save: save),
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
        let updater = try makeUpdater(discovery, context, clock: clock)

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
        let updater = try makeUpdater(discovery, context, clock: clock)
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
        let updater = try makeUpdater(discovery, context, clock: clock)
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
        let updater = try makeUpdater(discovery, context, clock: clock)
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
        try finishScan([seen, device(1)], on: discovery, updater: makeUpdater(discovery, context, clock: clock), clock: clock)

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
        let updater = try makeUpdater(discovery, context, clock: Clock(start))
        discovery.isScanning = true
        discovery.discoveredDevices = [device(0)]
        discovery.lastScanDate = start
        updater.handleScanChange()
        #expect(try rows(context).isEmpty)
    }

    // MARK: - Review blockers (#589)

    struct SaveFailed: Error {}

    final class Flag {
        var failing = true
    }

    @Test func aScanWhoseSaveFailedIsSavedAtTheNextChange() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let flag = Flag()
        let updater = try makeUpdater(discovery, context, clock: clock) { context in
            if flag.failing {
                throw SaveFailed()
            }
            try context.save()
        }
        finishScan([device(0), device(1)], on: discovery, updater: updater, clock: clock)
        flag.failing = false
        // Nothing new was scanned; the failed scan is tried again.
        updater.handleScanChange()
        let saved = try rows(context)
        #expect(saved.count == 2)
        #expect(saved.allSatisfy { $0.status == .online && $0.lastSeen == self.start })
    }

    /// The phone moved from home to the office; the background scan ran there.
    @Test func aScanOfAnotherNetworkLeavesThisOnesRowsAlone() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let reconciler = try makeReconciler(context)
        DeviceRecordUpdater.reconcile([device(0), device(1)], scanDate: start, network: home, with: reconciler, now: start)
        let office = UUID()
        let desk = DiscoveredDevice(
            ipAddress: "10.1.0.5", hostname: "desk", vendor: nil, macAddress: "AA:00:00:00:10:05",
            latency: 3, discoveredAt: start, source: .local
        )
        for minutes in [10.0, 20, 30, 40] {
            let time = start.addingTimeInterval(minutes * 60)
            DeviceRecordUpdater.reconcile([desk], scanDate: time, network: office, with: reconciler, now: time)
        }
        let saved = try rows(context)
        let homeRows = saved.filter { $0.networkProfileID == home }
        #expect(homeRows.count == 2)
        #expect(homeRows.allSatisfy { $0.status == .online && $0.lastSeen == self.start })
        #expect(saved.filter { $0.networkProfileID == office }.map(\.hostname) == ["desk"])
    }

    @Test func scansStartedWithoutANetworkScanTheCurrentOne() async {
        let subnet = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A8_0900, broadcastAddress: 0xC0A8_09FF, interfaceAddress: 0xC0A8_0902, netmask: 0xFFFF_FF00
        )
        let network = NetworkProfile(
            id: home, interfaceName: "en0", ipAddress: "192.168.9.2", network: subnet, connectionType: .wifi, name: "Home",
            gatewayIP: "192.168.9.1", subnet: "192.168.9.0/24", isLocal: true, discoveryMethod: .auto
        )
        let tools = MockDeviceDiscoveryService()
        await ToolsViewModel(deviceDiscoveryService: tools, currentNetwork: { network }).runNetworkScan()
        #expect(tools.lastScannedProfile?.id == home)
        #expect(tools.lastScannedSubnet == nil)

        let scheduled = MockDeviceDiscoveryService()
        await ScheduledScanViewModel(discovery: scheduled, currentNetwork: { network }).runScanNow()
        #expect(scheduled.lastScannedProfile?.id == home)
    }

    /// The list opens a scanned device with the network the scan stamped; detail finds the row the
    /// scan saved instead of making a second one.
    @Test func detailOpenedFromTheListFindsTheRowTheScanSaved() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        try finishScan([device(0), device(1)], on: discovery, updater: makeUpdater(discovery, context, clock: clock), clock: clock)
        let saved = try rows(context)
        let opened = DeviceDetailViewModel.savedRow(
            ipAddress: "192.168.9.11", scanned: device(1), macAddress: device(1).macAddress, networkID: home,
            scan: discovery.discoveredDevices, in: context
        )
        #expect(opened.id == saved[1].id)
        #expect(try rows(context).count == 2)
    }

    /// DHCP gave Alice's phone's address to Bob's TV; neither reads a MAC. The scan saved Bob as a
    /// new device, and the list opens Bob's row, leaving Alice's name and notes where they were.
    @Test func afterDHCPReuseTheListOpensTheNewDevicesRow() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        func phoneOrTV(_ name: String) -> DiscoveredDevice {
            DiscoveredDevice(ipAddress: "192.168.9.20", hostname: name, vendor: nil, macAddress: nil, latency: 4,
                             discoveredAt: start, source: .local, networkProfileID: home)
        }
        let reconciler = try makeReconciler(context)
        DeviceRecordUpdater.reconcile([phoneOrTV("alice-iphone")], scanDate: start, network: home, with: reconciler, now: start)
        let alice = try #require(try rows(context).first)
        alice.notes = "Alice"
        let later = start.addingTimeInterval(600)
        DeviceRecordUpdater.reconcile([phoneOrTV("bob-tv")], scanDate: later, network: home, with: reconciler, now: later)

        let opened = DeviceDetailViewModel.savedRow(
            ipAddress: "192.168.9.20", scanned: phoneOrTV("bob-tv"), networkID: home, scan: [phoneOrTV("bob-tv")], in: context
        )
        #expect(opened.id != alice.id)
        #expect(opened.hostname == "bob-tv")
        #expect(alice.hostname == "alice-iphone")
        #expect(alice.notes == "Alice")
        #expect(try rows(context).count == 2)
    }

    @Test func deletingTheSavedDataForgetsTheScanHistory() async throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let reconciler = ScanReconciler(context: context, history: ScanHistory(defaults: defaults))
        DeviceRecordUpdater.reconcile([device(0)], scanDate: start, network: home, with: reconciler, now: start)
        #expect(defaults.data(forKey: ScanHistory.storageKey) != nil)

        await SettingsViewModel(scanHistory: ScanHistory(defaults: defaults)).clearAllCachedData(modelContext: context)

        #expect(defaults.data(forKey: ScanHistory.storageKey) == nil)
        #expect(try rows(context).isEmpty)
    }

    /// Codex on #589: scan A's save fails; scan B starts, publishes part of its list and is stopped,
    /// so `lastScanDate` still names A. The retry saves A's own devices, not B's partial list.
    @Test func aRetrySavesTheFailedScansOwnDevicesNotALaterPartialList() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let clock = Clock(start)
        let flag = Flag()
        let updater = try makeUpdater(discovery, context, clock: clock) { context in
            if flag.failing {
                throw SaveFailed()
            }
            try context.save()
        }
        finishScan([device(0)], on: discovery, updater: updater, clock: clock)

        clock.now = start.addingTimeInterval(600)
        discovery.isScanning = true
        updater.handleScanChange()
        let stranger = DiscoveredDevice(
            ipAddress: "192.168.9.99", hostname: "partial", vendor: nil, macAddress: "AA:00:00:00:09:99",
            latency: 1, discoveredAt: start, source: .local, networkProfileID: home
        )
        discovery.discoveredDevices = [stranger]
        discovery.isScanning = false
        flag.failing = false
        updater.handleScanChange()

        let saved = try rows(context)
        #expect(saved.map(\.hostname) == ["host-0"])
        #expect(saved.first?.lastSeen == start)
    }

    /// Codex on #589: a printer answers at .24 while the ARP cache still lists it at .90. Opening
    /// either list entry opens its one saved row, at .24, in either order.
    @Test func bothListEntriesOfADeviceSeenAtTwoAddressesOpenItsOneRow() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        func printer(_ ip: String, cached: Bool) -> DiscoveredDevice {
            DiscoveredDevice(ipAddress: ip, hostname: "printer", vendor: nil, macAddress: "AA:00:00:00:09:24", latency: 2,
                             discoveredAt: start, source: .local, networkProfileID: home, isCached: cached)
        }
        let answered = printer("192.168.9.24", cached: false)
        let stale = printer("192.168.9.90", cached: true)
        try DeviceRecordUpdater.reconcile([answered, stale], scanDate: start, network: home, with: makeReconciler(context), now: start)
        let row = try #require(try rows(context).first)
        for scan in [[answered, stale], [stale, answered]] {
            for entry in scan {
                let opened = DeviceDetailViewModel.savedRow(
                    ipAddress: entry.ipAddress, scanned: entry, macAddress: entry.macAddress, networkID: home, scan: scan, in: context
                )
                #expect(opened.id == row.id)
                #expect(opened.ipAddress == "192.168.9.24")
            }
        }
        #expect(try rows(context).count == 1)
    }

    /// Codex on #589: scan A finished; before the updater saw it, scan B started, published part of
    /// its list and was stopped. A's own devices are saved, not B's progress list.
    @Test func theFinishedScansOwnListIsSavedNotALaterStoppedOnes() throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        let updater = try makeUpdater(discovery, context, clock: Clock(start))
        discovery.completedDevices = [device(0)]
        discovery.discoveredDevices = [device(3)]
        discovery.lastScanDate = start
        updater.handleScanChange()
        #expect(try rows(context).map(\.hostname) == ["host-0"])
    }
}
