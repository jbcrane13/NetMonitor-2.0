import Testing
import Foundation
import SwiftData
import NetworkScanKit
@testable import NetMonitorCore

/// A completed iOS scan keeps the saved device rows current (#582): rows for every scanned
/// device, online and last seen for those answering, offline after the grace policy for the rest.
@Suite("ScanReconciler", .serialized)
@MainActor
struct ScanReconcilerTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// The container is returned with the context: a context whose container is released crashes.
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    func makeReconciler(_ context: ModelContext, suite: String = UUID().uuidString) -> ScanReconciler {
        ScanReconciler(context: context, history: ScanHistory(defaults: UserDefaults(suiteName: suite) ?? .standard))
    }

    func scanned(_ index: Int, ip: String? = nil, mac: String? = nil, latency: Double = 12, maker: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip ?? "192.168.7.\(10 + index)", hostname: "host-\(index)", vendor: "Vendor \(index)",
            macAddress: mac ?? "AA:BB:CC:00:00:0\(index)", latency: latency, discoveredAt: start, source: .local,
            networkProfileID: home, identity: DeviceIdentity(maker: IdentityValue(maker, source: .upnp))
        )
    }

    func rows(_ context: ModelContext) throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>(sortBy: [SortDescriptor(\.ipAddress)]))
    }

    @Test func aScanCreatesARowForEveryDeviceThroughTheIdentitySeam() throws {
        let (container, context) = try makeContext()
        _ = container
        makeReconciler(context).reconcile([scanned(0, maker: "Brother"), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let saved = try rows(context)
        #expect(saved.map(\.ipAddress) == ["192.168.7.10", "192.168.7.11"])
        #expect(saved.allSatisfy { $0.status == .online && $0.lastSeen == start && $0.networkProfileID == home })
        #expect(saved[0].lastLatency == 12)
        #expect(saved[0].maker == "Brother")
        #expect(saved[0].hostname == "host-0")
    }

    @Test func aScannedPrinterIsSavedAsAPrinter() throws {
        let (container, context) = try makeContext()
        _ = container
        let printer = DiscoveredDevice(
            ipAddress: "192.168.7.30", hostname: "office-laser", vendor: nil, macAddress: "AA:BB:CC:00:00:30", latency: 3,
            discoveredAt: start, source: .local, networkProfileID: home, openPorts: [631, 9100]
        )
        makeReconciler(context).reconcile([printer], networkProfileID: home, scanDate: start, now: start)
        #expect(try rows(context).first?.deviceType == .printer)
    }

    @Test func aLaterScanUpdatesTheSameRowByMACEvenAtANewIP() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        let id = try rows(context)[0].id
        let later = start.addingTimeInterval(600)
        reconciler.reconcile([scanned(0, ip: "192.168.7.99", latency: 30)], networkProfileID: home, scanDate: later, now: later)
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].id == id)
        #expect(saved[0].ipAddress == "192.168.7.99")
        #expect(saved[0].lastSeen == later)
        #expect(saved[0].lastLatency == 30)
    }

    @Test func anUnseenDeviceStaysOnlineUntilTheGracePolicyIsMet() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // Three misses are needed, and 15 minutes: 10, 20, 30 minutes later.
        for minutes in [10.0, 20] {
            let time = start.addingTimeInterval(minutes * 60)
            reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
            #expect(try rows(context)[1].status == .online, "after \(minutes) minutes")
        }
        let third = start.addingTimeInterval(30 * 60)
        reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: third, now: third)
        let gone = try rows(context)[1]
        #expect(gone.status == .offline)
        #expect(gone.lastSeen == start)
        #expect(try rows(context)[0].status == .online)
    }

    @Test func manyQuickMissesAreNotEnoughWithoutTheGraceInterval() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for seconds in [60.0, 120, 180, 240] {
            let time = start.addingTimeInterval(seconds)
            reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context)[1].status == .online)
    }

    @Test func aDeviceThatAnswersAgainIsOnline() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for minutes in [10.0, 20, 30] {
            let time = start.addingTimeInterval(minutes * 60)
            reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        let back = start.addingTimeInterval(40 * 60)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: back, now: back)
        #expect(try rows(context)[1].status == .online)
        #expect(try rows(context)[1].lastSeen == back)
    }

    @Test func theSameScanIsReconciledOnce() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // The foreground observer and a background task both see the same finished scan.
        let later = start.addingTimeInterval(20 * 60)
        for _ in 0..<3 {
            reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: later, now: later)
        }
        #expect(try rows(context)[1].status == .online)
    }

    @Test func otherNetworksRowsAreLeftAlone() throws {
        let (container, context) = try makeContext()
        _ = container
        let elsewhere = LocalDevice(ipAddress: "192.168.7.10", macAddress: "AA:BB:CC:00:00:09", status: .online, networkProfileID: UUID())
        context.insert(elsewhere)
        let reconciler = makeReconciler(context)
        for minutes in [0.0, 10, 20, 30] {
            let time = start.addingTimeInterval(minutes * 60)
            reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(elsewhere.status == .online)
        #expect(elsewhere.ipAddress == "192.168.7.10")
        #expect(try rows(context).filter { $0.networkProfileID == home }.count == 1)
    }

    @Test func aRowSavedWithoutANetworkIsAdoptedByItsMAC() throws {
        let (container, context) = try makeContext()
        _ = container
        let old = LocalDevice(ipAddress: "10.0.0.5", macAddress: "AA:BB:CC:00:00:00", customName: "Printer")
        context.insert(old)
        makeReconciler(context).reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].id == old.id)
        #expect(saved[0].networkProfileID == home)
        #expect(saved[0].displayName == "Printer")
    }

    @Test func aRowAdoptedByItsMACGetsATypeFromTheScan() throws {
        let (container, context) = try makeContext()
        _ = container
        let old = LocalDevice(ipAddress: "10.0.0.5", macAddress: "AA:BB:CC:00:00:30")
        context.insert(old)
        let printer = DiscoveredDevice(
            ipAddress: "192.168.7.30", hostname: "office-laser", vendor: nil, macAddress: "AA:BB:CC:00:00:30", latency: 3,
            discoveredAt: start, source: .local, networkProfileID: home, openPorts: [631, 9100]
        )
        makeReconciler(context).reconcile([printer], networkProfileID: home, scanDate: start, now: start)
        #expect(old.networkProfileID == home)
        #expect(old.deviceType == .printer)
    }

    /// Most rows an older iPhone build saved have no network and no MAC. A scan must not save a
    /// second row at that address: device detail would open it and hide the name and notes.
    @Test func aScanLeavesAnAddressOnlyRowSavedWithoutANetworkForDetailToAdopt() throws {
        let (container, context) = try makeContext()
        _ = container
        let nas = LocalDevice(ipAddress: "192.168.7.10", macAddress: "", customName: "NAS")
        nas.notes = "Backups"
        context.insert(nas)
        let noMAC = DiscoveredDevice(
            ipAddress: "192.168.7.10", hostname: nil, vendor: nil, macAddress: nil, latency: 4,
            discoveredAt: start, source: .local, networkProfileID: home
        )
        makeReconciler(context).reconcile([noMAC, scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let saved = try rows(context)
        #expect(saved.map(\.ipAddress) == ["192.168.7.10", "192.168.7.11"])
        #expect(saved[0].id == nas.id)
        #expect(saved[0].networkProfileID == nil)
        #expect(saved[0].notes == "Backups")
        #expect(saved[1].networkProfileID == home)
    }

    /// A printer moved from .90 to .24 and answers there; the ARP cache still lists .90.
    @Test func aCachedOldAddressDoesNotReplaceTheAddressADeviceAnsweredAt() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0, ip: "192.168.7.90")], networkProfileID: home, scanDate: start, now: start)
        let later = start.addingTimeInterval(600)
        let answered = scanned(0, ip: "192.168.7.24")
        let stale = scanned(0, ip: "192.168.7.90").withCached(true)
        reconciler.reconcile([answered, stale], networkProfileID: home, scanDate: later, now: later)
        var saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].ipAddress == "192.168.7.24")
        #expect(saved[0].status == .online)
        #expect(saved[0].lastSeen == later)

        // In either order.
        let last = later.addingTimeInterval(600)
        reconciler.reconcile([stale, answered], networkProfileID: home, scanDate: last, now: last)
        saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].ipAddress == "192.168.7.24")
        #expect(saved[0].status == .online)
        #expect(saved[0].lastSeen == last)
    }

    @Test func missesAreCountedOnTheReconcilersClockNotTheScanDate() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        // Scans finish now (real time); the clock under test is a fixed day in the past.
        let realScan = Date()
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: realScan, now: start)
        let next = start.addingTimeInterval(20 * 60)
        reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: realScan.addingTimeInterval(1), now: next)
        // One miss: still online.
        #expect(try rows(context)[1].status == .online)
    }

    @Test func anEmptyScanChangesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        for minutes in [10.0, 20, 30, 40] {
            let time = start.addingTimeInterval(minutes * 60)
            reconciler.reconcile([], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context)[0].status == .online)
    }

    @Test func aCachedSightingIsNotSeen() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = makeReconciler(context)
        reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let later = start.addingTimeInterval(600)
        reconciler.reconcile([scanned(0), scanned(1).withCached(true)], networkProfileID: home, scanDate: later, now: later)
        let cached = try rows(context)[1]
        #expect(cached.status == .cached)
        #expect(cached.lastSeen == start)
    }
}
