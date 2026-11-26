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
            all += try events(reconciler.reconcile([phoneSees()], networkProfileID: home, scanDate: minutes(Double(step) * 10), now: minutes(Double(step) * 10)))
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
}
