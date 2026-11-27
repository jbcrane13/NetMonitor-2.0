import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #628 PR A: a Mac scan is saved to device rows only if no path update or resume happened since
/// it started; a dropped scan writes nothing and schedules one replacement.
@Suite("DeviceDiscoveryCoordinator join tokens (#628)", .serialized)
@MainActor
struct DeviceDiscoveryCoordinatorJoinTokenTests {
    private let home = UUID()
    private let base = DeviceDiscoveryCoordinatorReconcileTests()

    private func makeJoinClock() -> NetworkJoinClock {
        let (changes, _) = AsyncStream<String>.makeStream()
        let clock = NetworkJoinClock(changes: changes)
        // The monitor's first report: the path the app started on.
        clock.generation.notePathUpdate()
        return clock
    }

    @Test func aScanThatSpansAPathUpdateIsDroppedAndSavesNothing() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let saved = LocalDevice(ipAddress: "10.0.0.20", macAddress: "", hostname: "living-room-tv", notes: "Mounted", networkProfileID: home)
        context.insert(saved)
        try context.save()
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)

        let token = join.token(for: home)
        // The Mac moved while the scan ran: the next site has another device at that address.
        join.generation.notePathUpdate()
        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.20", "kitchen-phone")],
            profileID: home, now: Date(timeIntervalSince1970: 1_790_000_060), token: token
        )

        #expect(commit == .dropped)
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1)
        #expect(rows.first?.hostname == "living-room-tv")
        #expect(rows.first?.notes == "Mounted")
        #expect(coordinator.lastScanTime(for: home) == nil)
        #expect(coordinator.replacementScans.attempts == 1)
    }

    @Test func aScanWithNoPathUpdateIsSavedAndStartsANewChain() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)

        let dropped = join.token(for: home)
        join.generation.notePathUpdate()
        _ = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.21", "nas")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_030), token: dropped
        )
        #expect(coordinator.replacementScans.attempts == 1)

        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.21", "nas")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_060), token: join.token(for: home)
        )
        #expect(commit == .applied)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
        #expect(coordinator.replacementScans.attempts == 0)
    }

    @Test func aResumeDropsTheScan() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)
        let token = join.token(for: home)
        join.noteResume()
        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.22", "printer")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_060), token: token
        )
        #expect(commit == .dropped)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func theSparseMergeLatencyIsClearedWhenTheScanStops() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let mac = "AC:DE:48:00:00:B1"
        let row = LocalDevice(ipAddress: "10.0.0.70", macAddress: mac, hostname: "tv", networkProfileID: home)
        context.insert(row)
        try context.save()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: makeJoinClock())
        coordinator.mergeSparseSnapshot([DeviceDiscoveryCoordinatorReconcileTests.device("10.0.0.70", nil, mac: mac, latency: 7)], profileID: home)
        #expect(coordinator.progressiveLatency[row.id] == 7)
        #expect(row.lastLatency == nil)
        coordinator.stopScan()
        #expect(coordinator.progressiveLatency.isEmpty)
    }
}
