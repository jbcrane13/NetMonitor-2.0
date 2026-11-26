import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #585 review 6 and 11: the app computes the Mac inventory overlay once per change, in a model,
/// never in a view body, and while it is live publishes one online count (the list's) to the
/// dashboard and the widget; when it ends, the phone's own count comes back.
@Suite("MacInventoryModel", .serialized)
@MainActor
struct MacInventoryModelTests {
    static let home = NetworkProfile(
        interfaceName: "en0", ipAddress: "192.168.77.100",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
        ),
        connectionType: .wifi
    )

    struct Fixture {
        let container: ModelContainer
        let connection: MockMacConnectionService
        let summaries: SavedDeviceSummaryModel
        let model: MacInventoryModel
        let defaults: UserDefaults
    }

    func makeFixture() throws -> Fixture {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let tv = LocalDevice(ipAddress: "192.168.77.20", macAddress: "", hostname: "tv", networkProfileID: Self.home.id)
        container.mainContext.insert(tv)
        try container.mainContext.save()
        let connection = MockMacConnectionService()
        connection.connectionState = .connected
        connection.linkPath = CompanionLinkPath(remoteAddress: "192.168.77.2", interface: .wifi, interfaceName: "en0")
        connection.lastDeviceList = DeviceListPayload(
            devices: [
                DeviceInfo(ipAddress: "192.168.77.20", macAddress: "", hostname: "tv", isOnline: true, lastSeenAge: 30),
                DeviceInfo(ipAddress: "192.168.77.60", macAddress: "", hostname: "doorbell", isOnline: true, lastSeenAge: 30)
            ],
            network: InventoryNetwork(subnet: "192.168.77.0/24", gatewayIP: "192.168.77.254", name: "Home", scanAge: 20)
        )
        connection.lastDeviceListReceivedAt = Date()
        let suite = "MacInventoryModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let history = ScanHistory(defaults: defaults)
        let presence = DevicePresenceModel(history: history, clock: { Date() })
        let summaries = SavedDeviceSummaryModel()
        let model = MacInventoryModel(
            connection: connection, discovery: MockDeviceDiscoveryService(), presence: presence, context: container.mainContext,
            summaries: summaries, currentNetwork: { Self.home }, routedGateway: { "192.168.77.254" }, widgetDefaults: defaults,
            reloadsWidget: false
        )
        return Fixture(container: container, connection: connection, summaries: summaries, model: model, defaults: defaults)
    }

    @Test func aLiveInventoryIsComputedOnceAndCountedOnce() throws {
        let fixture = try makeFixture()
        fixture.model.refresh()
        let overlay = fixture.model.overlay
        #expect(overlay.inventory != nil)
        #expect(overlay.applies(to: Self.home.id))
        #expect(overlay.macOnly.map(\.name) == ["doorbell"])
        // The TV and the doorbell: the list's online count, the dashboard's and the widget's.
        #expect(fixture.summaries.count(for: Self.home.id) == 2)
        #expect(fixture.defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 2)
    }

    @Test func whenTheLinkDropsThePhonesOwnCountComesBack() throws {
        let fixture = try makeFixture()
        fixture.model.refresh()
        fixture.connection.lastDeviceListReceivedAt = nil
        fixture.model.refresh()
        #expect(fixture.model.overlay.inventory == nil)
        // The phone has no scan of its own yet: none of its rows answered one.
        #expect(fixture.summaries.count(for: Self.home.id) == 0)
        #expect(fixture.defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 0)
    }
}
