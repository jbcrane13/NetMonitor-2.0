import Testing
import Foundation
import SwiftData
import NetworkScanKit
@testable import NetMonitorCore

/// A completed iOS scan keeps the saved device rows current (#582): rows for every scanned
/// device, online and last seen for those answering, offline after the grace policy for the rest.
@Suite("ScanReconciler", .serialized)
@MainActor
final class ScanReconcilerTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// This test's own defaults suite for the scan history, removed when the test ends.
    nonisolated let suiteName = "ScanReconcilerTests.\(UUID().uuidString)"

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// The container is returned with the context: a context whose container is released crashes.
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    func makeReconciler(
        _ context: ModelContext,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ScanReconciler {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return ScanReconciler(context: context, history: ScanHistory(defaults: defaults), save: save)
    }

    func device(
        ip: String, mac: String?, name: String?, cached: Bool = false, network: UUID? = nil, seen: Date? = nil
    ) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 5, discoveredAt: seen ?? start,
            source: .local, networkProfileID: network ?? home, isCached: cached
        )
    }

    func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
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
        try makeReconciler(context).reconcile([scanned(0, maker: "Brother"), scanned(1)], networkProfileID: home, scanDate: start, now: start)
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
        try makeReconciler(context).reconcile([printer], networkProfileID: home, scanDate: start, now: start)
        #expect(try rows(context).first?.deviceType == .printer)
    }

    @Test func aLaterScanUpdatesTheSameRowByMACEvenAtANewIP() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        let id = try rows(context)[0].id
        let later = start.addingTimeInterval(600)
        try reconciler.reconcile([scanned(0, ip: "192.168.7.99", latency: 30)], networkProfileID: home, scanDate: later, now: later)
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
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // Three misses are needed, and 15 minutes: 10, 20, 30 minutes later.
        for minutes in [10.0, 20] {
            let time = start.addingTimeInterval(minutes * 60)
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
            #expect(try rows(context)[1].status == .online, "after \(minutes) minutes")
        }
        let third = start.addingTimeInterval(30 * 60)
        try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: third, now: third)
        let gone = try rows(context)[1]
        #expect(gone.status == .offline)
        #expect(gone.lastSeen == start)
        #expect(try rows(context)[0].status == .online)
    }

    @Test func manyQuickMissesAreNotEnoughWithoutTheGraceInterval() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for seconds in [60.0, 120, 180, 240] {
            let time = start.addingTimeInterval(seconds)
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context)[1].status == .online)
    }

    @Test func aDeviceThatAnswersAgainIsOnline() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for minutes in [10.0, 20, 30] {
            let time = start.addingTimeInterval(minutes * 60)
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        let back = start.addingTimeInterval(40 * 60)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: back, now: back)
        #expect(try rows(context)[1].status == .online)
        #expect(try rows(context)[1].lastSeen == back)
    }

    @Test func theSameScanIsReconciledOnce() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // The foreground observer and a background task both see the same finished scan.
        let later = start.addingTimeInterval(20 * 60)
        for _ in 0..<3 {
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: later, now: later)
        }
        #expect(try rows(context)[1].status == .online)
    }

    @Test func otherNetworksRowsAreLeftAlone() throws {
        let (container, context) = try makeContext()
        _ = container
        let elsewhere = LocalDevice(ipAddress: "192.168.7.10", macAddress: "AA:BB:CC:00:00:09", status: .online, networkProfileID: UUID())
        context.insert(elsewhere)
        let reconciler = try makeReconciler(context)
        for minutes in [0.0, 10, 20, 30] {
            let time = start.addingTimeInterval(minutes * 60)
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
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
        try makeReconciler(context).reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
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
        try makeReconciler(context).reconcile([printer], networkProfileID: home, scanDate: start, now: start)
        #expect(old.networkProfileID == home)
        #expect(old.deviceType == .printer)
    }

    /// Most rows an older iPhone build saved have no network and no MAC. One seen at the address
    /// within the grace window is the same device: the scan leaves it for device detail to adopt
    /// rather than saving a second row that would hide its name and notes.
    @Test func aRecentAddressOnlyRowSavedWithoutANetworkIsLeftForDetailToAdopt() throws {
        let (container, context) = try makeContext()
        _ = container
        let nas = LocalDevice(ipAddress: "192.168.7.10", macAddress: "", customName: "NAS")
        nas.notes = "Backups"
        nas.lastSeen = start.addingTimeInterval(-60)
        context.insert(nas)
        let noMAC = device(ip: "192.168.7.10", mac: nil, name: nil)
        try makeReconciler(context).reconcile([noMAC, scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let saved = try rows(context)
        #expect(saved.map(\.ipAddress) == ["192.168.7.10", "192.168.7.11"])
        #expect(saved[0].id == nas.id)
        #expect(saved[0].networkProfileID == nil)
        #expect(saved[0].notes == "Backups")
        #expect(saved[1].networkProfileID == home)
    }

    /// One not seen there within the grace window may be another device now: a split beats a
    /// wrong merge, so the scan saves a new row and leaves the old one, notes and all, untouched.
    @Test func aStaleAddressOnlyRowSavedWithoutANetworkIsLeftAloneAndANewRowSaved() throws {
        let (container, context) = try makeContext()
        _ = container
        let nas = LocalDevice(ipAddress: "192.168.7.10", macAddress: "", customName: "NAS")
        nas.notes = "Backups"
        nas.lastSeen = start.addingTimeInterval(-7 * 86400)
        context.insert(nas)
        try makeReconciler(context).reconcile([device(ip: "192.168.7.10", mac: nil, name: nil)], networkProfileID: home, scanDate: start, now: start)
        let saved = try rows(context)
        #expect(saved.count == 2)
        #expect(nas.networkProfileID == nil)
        #expect(nas.notes == "Backups")
        #expect(saved.contains { $0.networkProfileID == home && $0.id != nas.id })
    }

    /// A printer moved from .90 to .24 and answers there; the ARP cache still lists .90.
    @Test func aCachedOldAddressDoesNotReplaceTheAddressADeviceAnsweredAt() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0, ip: "192.168.7.90")], networkProfileID: home, scanDate: start, now: start)
        let later = start.addingTimeInterval(600)
        let answered = scanned(0, ip: "192.168.7.24")
        let stale = scanned(0, ip: "192.168.7.90").withCached(true)
        try reconciler.reconcile([answered, stale], networkProfileID: home, scanDate: later, now: later)
        var saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].ipAddress == "192.168.7.24")
        #expect(saved[0].status == .online)
        #expect(saved[0].lastSeen == later)

        // In either order.
        let last = later.addingTimeInterval(600)
        try reconciler.reconcile([stale, answered], networkProfileID: home, scanDate: last, now: last)
        saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].ipAddress == "192.168.7.24")
        #expect(saved[0].status == .online)
        #expect(saved[0].lastSeen == last)
    }

    @Test func missesAreCountedOnTheReconcilersClockNotTheScanDate() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        // Scans finish now (real time); the clock under test is a fixed day in the past.
        let realScan = Date()
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: realScan, now: start)
        let next = start.addingTimeInterval(20 * 60)
        try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: realScan.addingTimeInterval(1), now: next)
        // One miss: still online.
        #expect(try rows(context)[1].status == .online)
    }

    @Test func anEmptyScanChangesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        for minutes in [10.0, 20, 30, 40] {
            let time = start.addingTimeInterval(minutes * 60)
            try reconciler.reconcile([], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context)[0].status == .online)
    }

    @Test func aCachedSightingIsNotSeen() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let later = start.addingTimeInterval(600)
        try reconciler.reconcile([scanned(0), scanned(1).withCached(true)], networkProfileID: home, scanDate: later, now: later)
        let cached = try rows(context)[1]
        #expect(cached.status == .cached)
        #expect(cached.lastSeen == start)
    }
}

// MARK: - Review findings on #589

extension ScanReconcilerTests {
    // MARK: - Cached sightings (blocker 1)

    @Test func aDeviceOnlyInTheARPCacheGoesOfflineUnderGrace() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // Device 1 is only listed by the cache from now on, while device 0 keeps answering.
        for time in [10.0, 20].map(minutes) {
            try reconciler.reconcile([scanned(0), scanned(1).withCached(true)], networkProfileID: home, scanDate: time, now: time)
            #expect(try rows(context)[1].status == .cached)
        }
        try reconciler.reconcile([scanned(0), scanned(1).withCached(true)], networkProfileID: home, scanDate: minutes(30), now: minutes(30))
        let gone = try rows(context)[1]
        #expect(gone.status == .offline)
        #expect(gone.lastSeen == start)
        #expect(try rows(context).count == 2)
    }

    @Test func aCachedSightingNeverRevivesAnOfflineRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for time in [10.0, 20, 30].map(minutes) {
            try reconciler.reconcile([scanned(0)], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context)[1].status == .offline)
        try reconciler.reconcile([scanned(0), scanned(1, ip: "192.168.7.50").withCached(true)],
            networkProfileID: home, scanDate: minutes(40), now: minutes(40))
        let row = try rows(context).first { $0.macAddress == "AA:BB:CC:00:00:01" }
        #expect(row?.status == .offline)
        #expect(row?.ipAddress == "192.168.7.11")
        #expect(row?.lastSeen == start)
    }

    @Test func repeatedScansWhereNothingAnsweredChangeNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        // Off this network: the scan returns the previous list, all cached.
        for time in [10.0, 20, 30, 40, 50].map(minutes) {
            let outcome = try reconciler.reconcile(
                [scanned(0).withCached(true), scanned(1).withCached(true)], networkProfileID: home, scanDate: time, now: time
            )
            #expect(outcome == .skipped)
        }
        #expect(try rows(context).allSatisfy { $0.status == .online && $0.lastSeen == self.start })
    }

    @Test func aCachedSightingNeverCreatesARow() throws {
        let (container, context) = try makeContext()
        _ = container
        try makeReconciler(context).reconcile(
            [scanned(0), device(ip: "192.168.7.40", mac: "AA:BB:CC:00:00:40", name: "old", cached: true)],
            networkProfileID: home, scanDate: start, now: start
        )
        #expect(try rows(context).map(\.ipAddress) == ["192.168.7.10"])
    }

    /// Codex on ebceade6: the gateway answers every scan while the ARP cache keeps listing a
    /// nameless entry without a MAC, beyond grace. No scan adds a row for it.
    @Test func aRepeatedNamelessCachedSightingAddsNoRows() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let gateway = device(ip: "192.168.7.1", mac: "AA:BB:CC:00:00:01", name: "router")
        let ghost = device(ip: "192.168.7.99", mac: nil, name: nil, cached: true)
        for time in [0.0, 30, 60, 90, 120].map(minutes) {
            try reconciler.reconcile([gateway, ghost], networkProfileID: home, scanDate: time, now: time)
        }
        #expect(try rows(context).map(\.ipAddress) == ["192.168.7.1"])
    }

    // MARK: - Writes (blocker 2)

    struct SaveFailed: Error {}

    @Test func aFailedSaveIsNotRecordedAndTheScanIsAppliedOnRetry() throws {
        let (container, context) = try makeContext()
        _ = container
        try makeReconciler(context).reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        let failing = try makeReconciler(context) { _ in throw SaveFailed() }
        let later = minutes(10)
        #expect(throws: SaveFailed.self) {
            try failing.reconcile([scanned(0, latency: 40), scanned(5)], networkProfileID: self.home, scanDate: later, now: later)
        }
        // Rolled back: no half-applied scan waits in the context for the next save.
        #expect(!context.hasChanges)
        #expect(try rows(context).count == 2)
        #expect(try rows(context)[0].lastLatency == 12)
        // The same scan again, now saving: applied, not skipped as already reconciled.
        let outcome = try makeReconciler(context).reconcile([scanned(0, latency: 40)], networkProfileID: home, scanDate: later, now: later)
        #expect(outcome == .applied)
        #expect(try rows(context)[0].lastLatency == 40)
        #expect(try makeReconciler(context).reconcile([scanned(0)], networkProfileID: home, scanDate: later, now: later) == .skipped)
    }

    // MARK: - Placeholder MACs (blocker 3)

    @Test func aPlaceholderMACNeverAdoptsARowSavedWithoutANetwork() throws {
        let (container, context) = try makeContext()
        _ = container
        let old = LocalDevice(ipAddress: "10.0.0.5", macAddress: "02:00:00:00:00:00", customName: "Den TV")
        old.notes = "mounted"
        context.insert(old)
        try makeReconciler(context).reconcile(
            [device(ip: "192.168.7.70", mac: "02:00:00:00:00:00", name: "phone")], networkProfileID: home, scanDate: start, now: start
        )
        #expect(old.networkProfileID == nil)
        #expect(old.ipAddress == "10.0.0.5")
        #expect(old.displayName == "Den TV")
        let new = try #require(try rows(context).first { $0.networkProfileID == home })
        #expect(new.macAddress.isEmpty)
        #expect(new.hostname == "phone")
    }

    @Test func aMACTwoUnassignedRowsShareAdoptsNeither() throws {
        let (container, context) = try makeContext()
        _ = container
        let first = LocalDevice(ipAddress: "10.0.0.5", macAddress: "aa:bb:cc:00:00:05")
        let second = LocalDevice(ipAddress: "10.0.1.5", macAddress: "AA-BB-CC-00-00-05")
        context.insert(first)
        context.insert(second)
        try makeReconciler(context).reconcile(
            [device(ip: "192.168.7.5", mac: "AA:BB:CC:00:00:05", name: nil)], networkProfileID: home, scanDate: start, now: start
        )
        #expect(first.networkProfileID == nil)
        #expect(second.networkProfileID == nil)
        #expect(try rows(context).filter { $0.networkProfileID == home }.count == 1)
    }

    @Test func aRealMACAdoptsTheUnassignedRowWrittenDifferently() throws {
        let (container, context) = try makeContext()
        _ = container
        let old = LocalDevice(ipAddress: "10.0.0.5", macAddress: "aa-bb-cc-00-00-05", customName: "Printer")
        context.insert(old)
        try makeReconciler(context).reconcile(
            [device(ip: "192.168.7.5", mac: "AA:BB:CC:00:00:05", name: nil)], networkProfileID: home, scanDate: start, now: start
        )
        #expect(old.networkProfileID == home)
        #expect(try rows(context).count == 1)
    }

    // MARK: - Devices without a MAC (Blake's rule, blocker 7)

    @Test func onlyTwoDifferentNamesDiffer() {
        #expect(PresenceMatch.namesDiffer("Alice-iPhone", "Bob-TV"))
        #expect(!PresenceMatch.namesDiffer("Alice-iPhone", "alice-iphone"))
        #expect(!PresenceMatch.namesDiffer("Alice-iPhone", nil))
        #expect(!PresenceMatch.namesDiffer(nil, "Bob-TV"))
        #expect(!PresenceMatch.namesDiffer("", nil))
    }

    /// The lead's refinement: a TV whose reverse DNS times out for one scan stays on its row.
    @Test func aDeviceWhoseNameIsMissingForOneScanStaysOnItsRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.25", mac: nil, name: "living-room-tv")], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile([device(ip: "192.168.7.25", mac: nil, name: nil)], networkProfileID: home, scanDate: minutes(10), now: minutes(10))
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].hostname == "living-room-tv")
        #expect(saved[0].lastSeen == minutes(10))
    }

    /// A nameless device at an address whose row hasn't been seen for longer than the grace window
    /// is a new device.
    @Test func aNamelessDeviceAtAReusedAddressAfterTheGraceGapGetsANewRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.26", mac: nil, name: "alice-iphone")], networkProfileID: home, scanDate: start, now: start)
        let alice = try #require(try rows(context).first)
        alice.notes = "Alice"
        // Something else answers there 40 minutes later, without a name.
        try reconciler.reconcile([device(ip: "192.168.7.26", mac: nil, name: nil)], networkProfileID: home, scanDate: minutes(40), now: minutes(40))
        let saved = try rows(context)
        #expect(saved.count == 2)
        #expect(alice.lastSeen == start)
        #expect(alice.notes == "Alice")
    }

    @Test func differentNamesAlwaysSplitEvenWithinTheGraceWindow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.27", mac: nil, name: "alice-iphone")], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile([device(ip: "192.168.7.27", mac: nil, name: "bob-tv")],
            networkProfileID: home, scanDate: minutes(1), now: minutes(1))
        #expect(try rows(context).count == 2)
    }

    /// Several nameless rows could take a nameless device without a MAC: the one seen there most
    /// recently within the grace window; with none within it, a new row.
    @Test func severalFittingRowsGoToTheMostRecentWithinGraceElseANewRow() {
        let now = minutes(30)
        let older = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.40", macAddress: nil, name: nil), lastSeen: minutes(20))
        let newer = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.40", macAddress: nil, name: nil), lastSeen: minutes(25))
        let nameless = DeviceMatchCandidate(ipAddress: "192.168.7.40", macAddress: nil, name: nil)
        #expect(PresenceMatch.assign(known: [older, newer], observed: [nameless], now: now, window: 15 * 60) == [1])

        let stale = [
            PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: nil), lastSeen: start),
            PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: nil), lastSeen: minutes(1))
        ]
        let unnamed = DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: nil)
        #expect(PresenceMatch.assign(known: stale, observed: [unnamed], now: now, window: 15 * 60) == [nil])
    }

    /// DHCP gave Alice's phone's address to Bob's TV. Neither reads a MAC.
    @Test func dhcpReuseMakesANewRowAndLeavesTheOldOneToGoOffline() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.20", mac: nil, name: "alice-iphone")], networkProfileID: home, scanDate: start, now: start)
        let alice = try #require(try rows(context).first)
        alice.notes = "Alice"
        for time in [10.0, 20, 30].map(minutes) {
            try reconciler.reconcile([device(ip: "192.168.7.20", mac: nil, name: "bob-tv")], networkProfileID: home, scanDate: time, now: time)
        }
        let saved = try rows(context)
        // Three identical scans after the reuse: still exactly two rows.
        #expect(saved.count == 2)
        #expect(alice.hostname == "alice-iphone")
        #expect(alice.notes == "Alice")
        #expect(alice.status == .offline)
        let bob = try #require(saved.first { $0.id != alice.id })
        #expect(bob.hostname == "bob-tv")
        #expect(bob.status == .online)
        #expect(bob.lastSeen == minutes(30))
    }

    @Test func aDeviceWithoutAMACOrNameKeepsItsRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        for time in [0.0, 10, 20, 30].map(minutes) {
            try reconciler.reconcile([device(ip: "192.168.7.21", mac: nil, name: nil)], networkProfileID: home, scanDate: time, now: time)
        }
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved.first?.status == .online)
    }

    @Test func anObservationWithoutAMACTakesAMACRowByNameOrWithinGrace() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile(
            [device(ip: "192.168.7.30", mac: "AA:BB:CC:00:00:30", name: "printer")], networkProfileID: home, scanDate: start, now: start
        )
        // Its MAC wasn't readable this time, but its name is the printer's.
        try reconciler.reconcile([device(ip: "192.168.7.30", mac: nil, name: "printer")],
            networkProfileID: home, scanDate: minutes(10), now: minutes(10))
        // No MAC and no name, still within the grace window: still the printer.
        try reconciler.reconcile([device(ip: "192.168.7.30", mac: nil, name: nil)], networkProfileID: home, scanDate: minutes(20), now: minutes(20))
        #expect(try rows(context).count == 1)
        #expect(try rows(context).first?.lastSeen == minutes(20))
        // A different name there is another device.
        try reconciler.reconcile([device(ip: "192.168.7.30", mac: nil, name: "phone")],
            networkProfileID: home, scanDate: minutes(25), now: minutes(25))
        let saved = try rows(context)
        #expect(saved.count == 2)
        let printer = try #require(saved.first { $0.macAddress == "AA:BB:CC:00:00:30" })
        #expect(printer.hostname == "printer")
        #expect(printer.lastSeen == minutes(20))
    }

    @Test func aMACBecomingReadableTakesTheRowOnlyWhenTheNameAgrees() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.31", mac: nil, name: "nas")], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile([device(ip: "192.168.7.31", mac: "AA:BB:CC:00:00:31", name: "nas")],
            networkProfileID: home, scanDate: minutes(10), now: minutes(10))
        #expect(try rows(context).count == 1)
        #expect(try rows(context).first?.macAddress == "AA:BB:CC:00:00:31")
        try reconciler.reconcile([device(ip: "192.168.7.32", mac: nil, name: "cam")], networkProfileID: home, scanDate: minutes(20), now: minutes(20))
        try reconciler.reconcile([device(ip: "192.168.7.32", mac: "AA:BB:CC:00:00:32", name: "doorbell")],
            networkProfileID: home, scanDate: minutes(30), now: minutes(30))
        #expect(try rows(context).filter { $0.ipAddress == "192.168.7.32" }.count == 2)
    }

    // MARK: - Networks (blockers 5, 9)

    @Test func scansOfAnotherNetworkNeverTouchThisOnesRows() throws {
        let (container, context) = try makeContext()
        _ = container
        let office = UUID()
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0), scanned(1)], networkProfileID: home, scanDate: start, now: start)
        for time in [10.0, 20, 30, 40].map(minutes) {
            try reconciler.reconcile(
                [device(ip: "10.1.0.5", mac: "AA:BB:CC:10:00:05", name: "desk", network: office)],
                networkProfileID: office, scanDate: time, now: time
            )
        }
        let homeRows = try rows(context).filter { $0.networkProfileID == home }
        #expect(homeRows.count == 2)
        #expect(homeRows.allSatisfy { $0.status == .online && $0.lastSeen == self.start })
    }

    @Test func clearingTheHistoryForgetsEveryNetwork() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let history = ScanHistory(defaults: defaults)
        history.record(scan: start, reconciled: start, for: home)
        history.record(scan: start, reconciled: start, for: UUID())
        history.clearAll()
        #expect(!history.contains(scan: start, for: home))
        #expect(defaults.data(forKey: ScanHistory.storageKey) == nil)
    }

    /// Codex on #589: foreground scan A failed to save; background scan B saved; A's retry must not
    /// put A's older address and presence back.
    @Test func aScanOlderThanOneAlreadySavedIsSkipped() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([scanned(0, ip: "192.168.7.24")], networkProfileID: home, scanDate: minutes(10), now: minutes(10))
        let outcome = try reconciler.reconcile([scanned(0, ip: "192.168.7.90")], networkProfileID: home, scanDate: minutes(5), now: minutes(11))
        #expect(outcome == .skipped)
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved[0].ipAddress == "192.168.7.24")
        #expect(saved[0].lastSeen == minutes(10))
    }

    /// (C) A nameless return makes a second row; when the name comes back, the named row is
    /// chosen, at any age, over the recent nameless one.
    @Test func aNamedRowWinsOnceTheNameIsBack() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.50", mac: nil, name: "nas")], networkProfileID: home, scanDate: start, now: start)
        let nas = try #require(try rows(context).first)
        try reconciler.reconcile([device(ip: "192.168.7.50", mac: nil, name: nil)], networkProfileID: home, scanDate: minutes(40), now: minutes(40))
        #expect(try rows(context).count == 2)
        try reconciler.reconcile([device(ip: "192.168.7.50", mac: nil, name: "nas")], networkProfileID: home, scanDate: minutes(50), now: minutes(50))
        #expect(try rows(context).count == 2)
        #expect(nas.lastSeen == minutes(50))
    }

    /// (C) Two stale rows named "nas": the most recently seen is taken, and no third row is made.
    @Test func ofTwoStaleRowsWithTheNameTheMostRecentIsTaken() {
        let older = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: "nas"), lastSeen: start)
        let newer = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: "nas"), lastSeen: minutes(1))
        let nameless = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: nil), lastSeen: minutes(299))
        let nas = DeviceMatchCandidate(ipAddress: "192.168.7.41", macAddress: nil, name: "nas")
        #expect(PresenceMatch.assign(known: [older, newer, nameless], observed: [nas], now: minutes(300), window: 15 * 60) == [1])
    }
}
