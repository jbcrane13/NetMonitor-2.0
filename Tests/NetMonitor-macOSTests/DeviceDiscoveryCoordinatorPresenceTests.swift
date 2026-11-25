import Foundation
import SwiftData
import Testing
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// #583: the coordinator's `presence()` reads each network's last reconciled scan, as of the later
/// of its presence clock and the scan clock, so views show online, offline or not checked recently.
@Suite(.serialized)
@MainActor
struct DeviceDiscoveryCoordinatorPresenceTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeCoordinator(
        context: ModelContext, scanClock: @escaping @MainActor () -> Date, presenceClock: @escaping @MainActor () -> Date
    ) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            scanHistory: .forTesting(),
            clock: scanClock,
            presenceClock: presenceClock
        )
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func device(_ ip: String, mac: String) -> DiscoveredDevice {
        DiscoveredDevice(ipAddress: ip, hostname: "host-\(ip)", vendor: nil, macAddress: mac, latency: 3, discoveredAt: start, source: .local)
    }

    @Test func aDeviceThatAnsweredTheLatestScanIsOnlineAsOfThatScan() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        // The scan clock runs ahead of the presence clock, as the UI tests' stepped clock does.
        let coordinator = makeCoordinator(context: context, scanClock: { start + 3600 }, presenceClock: { start })
        coordinator.reconcileScan([device("192.168.1.10", mac: "AA:BB:CC:00:00:10")], profileID: nil)

        let presence = coordinator.presence()
        #expect(presence.now == start + 3600)
        let row = try #require(coordinator.discoveredDevices.first)
        #expect(presence.freshness(of: row) == .online)
        #expect(presence.lastSeenText(row) == "Last seen just now")
    }

    @Test func anHourAfterTheLastScanEveryRowIsNotCheckedRecently() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        var now = start
        let coordinator = makeCoordinator(context: context, scanClock: { start }, presenceClock: { now })
        coordinator.reconcileScan([device("192.168.1.10", mac: "AA:BB:CC:00:00:10")], profileID: nil)
        now = start + 3600

        let presence = coordinator.presence()
        let row = try #require(coordinator.discoveredDevices.first)
        #expect(row.status == DeviceStatus.online)
        #expect(presence.freshness(of: row) == .notCheckedRecently)
        #expect(presence.lastSeenText(row) == "Last seen 1 hour ago")
    }
}
