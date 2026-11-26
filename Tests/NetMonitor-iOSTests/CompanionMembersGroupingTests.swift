import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #594 PR2, the iPhone side of the companion `members` payload: a dual-homed Mac's list gives one
/// sighting per interface that answered a Mac scan newer than the phone's own, and the phone's
/// reconciler groups those interfaces only on its **own** same-scan Bonjour evidence, never on the
/// Mac's membership alone.
@Suite("Companion members on iPhone", .serialized)
@MainActor
final class CompanionMembersGroupingTests {
    let home = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "CompanionMembersGroupingTests.\(UUID().uuidString)"
    let container: ModelContainer

    init() throws {
        let schema = AppModelStore.schema
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// The Mac's list: its studio Mac answered its latest scan on Wi-Fi and on Ethernet.
    func macList(scanTime: Date) -> DeviceListPayload {
        let members = [
            MemberInfo(id: UUID(), ipAddress: "192.168.1.13", macAddress: "00:1B:A9:00:00:13", lastSeen: scanTime, answeredLatestScan: true,
                       scanTime: scanTime),
            MemberInfo(id: UUID(), ipAddress: "192.168.1.60", macAddress: "00:1B:A9:00:00:60", lastSeen: scanTime, answeredLatestScan: true,
                       scanTime: scanTime)
        ]
        return DeviceListPayload(devices: [
            DeviceInfo(ipAddress: "192.168.1.13", macAddress: "00:1B:A9:00:00:13", hostname: "studio-mac", isOnline: true, members: members,
                       isDeviceOnline: true)
        ])
    }

    /// The scan as the phone's discovery builds it: its own observations, then the Mac's fresh
    /// sightings merged into the same accumulator.
    func phoneScan(own: [DiscoveredDevice], macScanTime: Date, ownLastScan: Date?) async -> [DiscoveredDevice] {
        let accumulator = ScanAccumulator()
        for device in own {
            await accumulator.upsert(device)
        }
        let sightings = DeviceDiscoveryService.companionSightings(
            list: macList(scanTime: macScanTime), receivedAt: now.addingTimeInterval(-10), macConnected: true, now: now,
            includes: { _ in true }, profileID: home, ownLastScan: ownLastScan
        )
        #expect(sightings.fresh)
        await DeviceDiscoveryService.mergeCompanion(sightings, into: accumulator)
        return await accumulator.snapshot()
    }

    func reconcile(_ scan: [DiscoveredDevice], at time: Date) throws {
        let history = try ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName)))
        try ScanReconciler(context: ModelContext(container), history: history, dispatcher: DeviceEventDispatcher())
            .reconcile(scan, networkProfileID: home, scanDate: time, now: time)
    }

    func devices() throws -> [DeviceProjection] {
        try DeviceGroups.project(ModelContext(container).fetch(FetchDescriptor<LocalDevice>()))
    }

    func claimed(_ ip: String, mac: String) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: "studio-mac", vendor: nil, macAddress: mac, latency: 2, discoveredAt: now, source: .bonjour,
            networkProfileID: home, bonjourClaims: [HostClaim(host: "studio-mac.local", service: "Studio", address: ip)]
        )
    }

    @Test("The Mac's two interfaces are two sightings, and its membership alone groups nothing")
    func membersAloneNeverGroup() async throws {
        let scan = await phoneScan(own: [], macScanTime: now.addingTimeInterval(-20), ownLastScan: nil)
        #expect(scan.map(\.ipAddress).sorted() == ["192.168.1.13", "192.168.1.60"])
        #expect(scan.allSatisfy { $0.source == .macCompanion && $0.bonjourClaims.isEmpty })

        try reconcile(scan, at: now)
        let saved = try devices()
        #expect(saved.count == 2, "two devices: the Mac's members are not the phone's evidence")
        #expect(saved.allSatisfy { !$0.isGroup })
    }

    @Test("The phone's own Bonjour answers for both interfaces in the same scan group them")
    func ownEvidenceGroups() async throws {
        let first = await phoneScan(own: [], macScanTime: now.addingTimeInterval(-20), ownLastScan: nil)
        try reconcile(first, at: now)
        #expect(try devices().count == 2)

        // The next scan: the phone itself hears the studio Mac's host on both addresses.
        let later = now.addingTimeInterval(600)
        let own = [claimed("192.168.1.13", mac: "00:1B:A9:00:00:13"), claimed("192.168.1.60", mac: "00:1B:A9:00:00:60")]
        let second = await phoneScan(own: own, macScanTime: now.addingTimeInterval(-20), ownLastScan: now)
        #expect(second.map(\.ipAddress).sorted() == ["192.168.1.13", "192.168.1.60"], "the Mac's older scan adds no sightings")
        try reconcile(second, at: later)

        let saved = try devices()
        #expect(saved.count == 1)
        #expect(saved.first?.members.allSatisfy { $0.groupSource == DeviceGroupSource.bonjour.rawValue } == true)
    }

    @Test("A Mac scan older than the phone's own adds no sightings")
    func olderMacScanIsNoSighting() async {
        let scan = await phoneScan(own: [], macScanTime: now.addingTimeInterval(-60), ownLastScan: now.addingTimeInterval(-30))
        #expect(scan.isEmpty)
    }
}
