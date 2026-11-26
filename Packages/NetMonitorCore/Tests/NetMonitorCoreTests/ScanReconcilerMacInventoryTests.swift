import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #585 review 3 (lead decision): while the Mac's inventory is live, its answered devices refresh
/// the phone's **existing** rows (presence only: status, last seen) by the strict `PresenceMatch`
/// rule, and never insert one. So a device only the Mac can reach stays online on the phone with no
/// false "went offline", a device only the Mac knows never becomes a row, and after the link drops
/// the grace policy applies again.
@Suite("ScanReconciler with the Mac's sightings", .serialized)
@MainActor
final class ScanReconcilerMacInventoryTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "ScanReconcilerMacInventoryTests.\(UUID().uuidString)"

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    func makeReconciler(_ context: ModelContext) throws -> ScanReconciler {
        try ScanReconciler(context: context, history: ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName))))
    }

    func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    /// What the phone itself finds every scan.
    func phoneSees(_ ip: String = "192.168.7.5", name: String = "nas") -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: "AA:BB:CC:00:00:05", latency: 3, discoveredAt: start,
            source: .local, networkProfileID: home
        )
    }

    func macSighting(_ ip: String, name: String?, mac: String? = nil, maker: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: maker, macAddress: mac, latency: nil, discoveredAt: start, source: .macCompanion,
            networkProfileID: home
        )
    }

    func rows(_ context: ModelContext) throws -> [LocalDevice] {
        try context.fetch(FetchDescriptor<LocalDevice>(sortBy: [SortDescriptor(\.ipAddress)]))
    }

    func events(_ outcome: ScanReconciler.Outcome) -> [DeviceEvent] {
        if case .applied(_, _, let events) = outcome {
            return events
        }
        return []
    }

    @Test func aRowOnlyTheMacCanReachStaysOnlineWithNoOfflineEvent() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let tv = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "tv", vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), tv], networkProfileID: home, scanDate: start, now: start)
        var all: [DeviceEvent] = []
        // Five phone scans over 50 minutes that miss the TV; the Mac answers for it each time.
        for step in 1...5 {
            let outcome = try reconciler.reconcile(
                [phoneSees()], macSightings: [macSighting("192.168.7.20", name: "tv")], networkProfileID: home,
                scanDate: minutes(Double(step) * 10), now: minutes(Double(step) * 10)
            )
            all += events(outcome)
        }
        let saved = try #require(try rows(context).first { $0.ipAddress == "192.168.7.20" })
        #expect(saved.status == .online)
        #expect(saved.lastSeen == minutes(50))
        #expect(!all.contains {
            if case .wentOffline = $0.kind {
                true
            } else {
                false
            }
        })
    }

    @Test func aDeviceOnlyTheMacKnowsNeverBecomesARow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        for step in 0..<5 {
            try reconciler.reconcile(
                [phoneSees()], macSightings: [macSighting("192.168.7.60", name: "doorbell", mac: "AA:BB:CC:00:00:60")],
                networkProfileID: home, scanDate: minutes(Double(step) * 10), now: minutes(Double(step) * 10)
            )
        }
        #expect(try rows(context).map(\.ipAddress) == ["192.168.7.5"])
    }

    @Test func theMacRefreshesPresenceOnlyNeverNamesOrMakers() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let printer = DiscoveredDevice(
            ipAddress: "192.168.7.30", hostname: "printer", vendor: "Brother", macAddress: "AA:BB:CC:00:00:30", latency: 4,
            discoveredAt: start, source: .local, networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), printer], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile(
            [phoneSees()], macSightings: [macSighting("192.168.7.30", name: "printer", mac: "AA:BB:CC:00:00:30", maker: "Acme")],
            networkProfileID: home, scanDate: minutes(10), now: minutes(10)
        )
        let saved = try #require(try rows(context).first { $0.ipAddress == "192.168.7.30" })
        #expect(saved.vendor == "Brother")
        #expect(saved.lastSeen == minutes(10))
    }

    /// The lead's address rule: an old row and a new device at its address with another name stay
    /// apart, so the Mac's guest TV never keeps Dad's iPad online.
    @Test func aDifferentNameAtTheSameAddressRefreshesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let iPad = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "dads-ipad", vendor: nil, macAddress: nil, latency: 4, discoveredAt: start,
            source: .local, networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), iPad], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile(
            [phoneSees()], macSightings: [macSighting("192.168.7.20", name: "guest-tv")], networkProfileID: home,
            scanDate: minutes(10), now: minutes(10)
        )
        let saved = try #require(try rows(context).first { $0.ipAddress == "192.168.7.20" })
        #expect(saved.lastSeen == start)
        #expect(try rows(context).count == 2)
    }

    @Test func withoutTheMacTheGracePolicyAppliesAgain() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let tv = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "tv", vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), tv], networkProfileID: home, scanDate: start, now: start)
        try reconciler.reconcile(
            [phoneSees()], macSightings: [macSighting("192.168.7.20", name: "tv")], networkProfileID: home,
            scanDate: minutes(10), now: minutes(10)
        )
        // The link drops: no sightings from the Mac. Three missed scans and 15 minutes later, offline.
        var all: [DeviceEvent] = []
        for step in 2...5 {
            let time = minutes(Double(step) * 10)
            all += try events(reconciler.reconcile([phoneSees()], networkProfileID: home, scanDate: time, now: time))
        }
        #expect(try rows(context).first { $0.ipAddress == "192.168.7.20" }?.status == .offline)
        #expect(all.contains {
            if case .wentOffline = $0.kind {
                true
            } else {
                false
            }
        })
    }

    // MARK: - Verification round (#624)

    /// A: a MAC-proven refresh at another address moves the row there, as a phone scan would, so the
    /// old address isn't "seen" for a guest who takes it next.
    @Test func aMACProvenRefreshMovesTheRowToTheMacsAddress() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let iPad = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "ipad", vendor: nil, macAddress: "AA:BB:CC:00:00:AA", latency: 4, discoveredAt: start,
            source: .local, networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), iPad], networkProfileID: home, scanDate: start, now: start)
        let row = try #require(try rows(context).first { $0.hostname == "ipad" })
        row.notes = "Dad's"
        try reconciler.reconcile(
            [phoneSees()], macSightings: [macSighting("192.168.7.30", name: "ipad", mac: "AA:BB:CC:00:00:AA")], networkProfileID: home,
            scanDate: minutes(5), now: minutes(5)
        )
        #expect(row.ipAddress == "192.168.7.30")
        // A nameless guest takes .20: it never gets the iPad's row, name or notes.
        let guest = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: nil, vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), guest], networkProfileID: home, scanDate: minutes(6), now: minutes(6))
        let atTwenty = try #require(try rows(context).first { $0.ipAddress == "192.168.7.20" })
        #expect(atTwenty.id != row.id)
        #expect(atTwenty.notes == nil)
        #expect(row.ipAddress == "192.168.7.30")
    }

    /// E: a row refreshed only by the Mac gets no type inferred: presence only. (A printer's ports
    /// would make the phone's own scan call it a printer.)
    @Test func aMacRefreshInfersNoType() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([phoneSees()], networkProfileID: home, scanDate: start, now: start)
        let printer = LocalDevice(
            ipAddress: "192.168.7.40", macAddress: "AA:BB:CC:00:00:40", hostname: "office-laser", openPorts: [631, 9100],
            networkProfileID: home
        )
        printer.lastSeen = start
        context.insert(printer)
        try context.save()
        try reconciler.reconcile(
            [phoneSees()], macSightings: [macSighting("192.168.7.40", name: "office-laser", mac: "AA:BB:CC:00:00:40")],
            networkProfileID: home, scanDate: minutes(5), now: minutes(5)
        )
        #expect(printer.lastSeen == minutes(5))
        #expect(printer.deviceType == .unknown)
    }

    /// E: a Mac sighting at an address the phone's own scan answered refreshes nothing else. The
    /// laptop moved to .20, where an older nameless row was seen within grace; the phone found the
    /// laptop there, so the Mac's nameless answer at .20 is the laptop's, not the old row's.
    @Test func aMacSightingThePhoneAlreadyAnsweredRefreshesNoOtherRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([phoneSees()], networkProfileID: home, scanDate: start, now: start)
        let old = LocalDevice(ipAddress: "192.168.7.20", macAddress: "", networkProfileID: home)
        old.lastSeen = start
        let laptop = LocalDevice(ipAddress: "192.168.7.25", macAddress: "AA:BB:CC:00:00:20", hostname: "laptop", networkProfileID: home)
        laptop.lastSeen = start
        context.insert(old)
        context.insert(laptop)
        try context.save()
        let found = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "laptop", vendor: nil, macAddress: "AA:BB:CC:00:00:20", latency: 4, discoveredAt: start,
            source: .local, networkProfileID: home
        )
        try reconciler.reconcile(
            [phoneSees(), found], macSightings: [macSighting("192.168.7.20", name: nil)], networkProfileID: home,
            scanDate: minutes(5), now: minutes(5)
        )
        #expect(laptop.ipAddress == "192.168.7.20")
        #expect(laptop.lastSeen == minutes(5))
        #expect(old.lastSeen == start)
    }

    /// E: the Mac stays connected but stops seeing a device: it goes offline under grace, once.
    @Test func aDeviceTheConnectedMacStopsSeeingGoesOfflineOnce() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let tv = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "tv", vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), tv], networkProfileID: home, scanDate: start, now: start)
        var offline = 0
        for step in 1...6 {
            let time = minutes(Double(step) * 10)
            // The Mac still answers for another device, not the TV.
            let outcome = try reconciler.reconcile(
                [phoneSees()], macSightings: [macSighting("192.168.7.60", name: "doorbell")], networkProfileID: home, scanDate: time, now: time
            )
            offline += events(outcome).count {
                if case .wentOffline = $0.kind {
                    true
                } else {
                    false
                }
            }
        }
        #expect(try rows(context).first { $0.ipAddress == "192.168.7.20" }?.status == .offline)
        #expect(offline == 1)
    }

    /// Lead's final check: in ONE reconcile, the iPad (aa) has moved .20 → .30 and a nameless guest
    /// has taken .20. The phone finds only the guest; the Mac saw aa answering at .30. The Mac's proof
    /// keeps the iPad's row out of an address-only match at .20: the guest gets a new row, and the
    /// iPad's row moves to .30 with its notes. Another nameless row seen at .30 within grace is not
    /// stamped by the Mac's answer.
    @Test func theMacsProofOfAMoveKeepsTheOldAddressFromTheGuestInOneReconcile() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        let iPad = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: "ipad", vendor: nil, macAddress: "AA:BB:CC:00:00:AA", latency: 4, discoveredAt: start,
            source: .local, networkProfileID: home
        )
        let other = DiscoveredDevice(
            ipAddress: "192.168.7.30", hostname: nil, vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile([phoneSees(), iPad, other], networkProfileID: home, scanDate: start, now: start)
        let iPadRow = try #require(try rows(context).first { $0.hostname == "ipad" })
        iPadRow.notes = "Dad's"
        let otherRow = try #require(try rows(context).first { $0.ipAddress == "192.168.7.30" })
        let guest = DiscoveredDevice(
            ipAddress: "192.168.7.20", hostname: nil, vendor: nil, macAddress: nil, latency: 4, discoveredAt: start, source: .local,
            networkProfileID: home
        )
        try reconciler.reconcile(
            [phoneSees(), guest], macSightings: [macSighting("192.168.7.30", name: "ipad", mac: "AA:BB:CC:00:00:AA")],
            networkProfileID: home, scanDate: minutes(5), now: minutes(5)
        )
        let atTwenty = try #require(try rows(context).first { $0.ipAddress == "192.168.7.20" })
        #expect(atTwenty.id != iPadRow.id)
        #expect(atTwenty.notes == nil)
        #expect(atTwenty.hostname == nil)
        #expect(iPadRow.ipAddress == "192.168.7.30")
        #expect(iPadRow.notes == "Dad's")
        #expect(iPadRow.lastSeen == minutes(5))
        #expect(otherRow.lastSeen == start)
    }
}
