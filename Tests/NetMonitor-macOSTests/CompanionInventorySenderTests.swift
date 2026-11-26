import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// The Mac's side of #585: its heartbeat always advertises `inventory.v1`, its device list says
/// which network it covers and how old its scan is, carries each device's last-seen and
/// last-changed ages and its identity with sources (#427), and goes to the phones after each scan.
@Suite("Companion inventory sender", .serialized)
@MainActor
struct CompanionInventorySenderTests {
    private final class Events: NetworkEventServiceProtocol, @unchecked Sendable {
        var stored: [NetworkEvent] = []
        var events: [NetworkEvent] { stored }
        func log(_ event: NetworkEvent) { stored.insert(event, at: 0) }
        func events(ofType type: NetworkEventType) -> [NetworkEvent] { stored.filter { $0.type == type } }
        func events(from start: Date, to end: Date) -> [NetworkEvent] { stored.filter { $0.timestamp >= start && $0.timestamp <= end } }
        func removeEvents(olderThan cutoff: Date) { stored.removeAll { $0.timestamp < cutoff } }
        func clearAll() { stored.removeAll() }
    }

    private struct Fixture {
        let container: ModelContainer
        let handler: CompanionMessageHandler
        let discovery: DeviceDiscoveryCoordinator
        let profile: NetworkProfile
        let events: Events
    }

    private static let profile = NetworkProfile(
        interfaceName: "en0",
        ipAddress: "192.168.77.100",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A84D00, broadcastAddress: 0xC0A84DFF, interfaceAddress: 0xC0A84D64, netmask: 0xFFFFFF00
        ),
        connectionType: .ethernet,
        displayName: "Test Network"
    )

    private func makeFixture(
        profiles: [NetworkProfile] = [Self.profile], gateway: String? = "192.168.77.254"
    ) throws -> Fixture {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self, LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let profile = Self.profile
        let manager = NetworkProfileManager(userDefaults: InMemoryDefaults(), activeProfilesProvider: { profiles })
        let discovery = DeviceDiscoveryCoordinator(
            modelContext: context, bonjourScanner: BonjourDiscoveryService(), networkProfileManager: manager,
            scanHistory: .forTesting(), dispatcher: DeviceEventDispatcher()
        )
        let events = Events()
        let handler = CompanionMessageHandler(
            modelContext: context, monitoringSession: MonitoringSession(modelContext: context), deviceDiscovery: discovery,
            wakeOnLanService: WakeOnLANService(), icmpService: ICMPMonitorService(), networkProfileManager: manager,
            insightService: UnavailableInsightService(), eventService: events, routedGateway: { _ in gateway }
        )
        return Fixture(container: container, handler: handler, discovery: discovery, profile: profile, events: events)
    }

    private func deviceList(_ handler: CompanionMessageHandler) throws -> DeviceListPayload {
        guard case .deviceList(let payload) = handler.generateDeviceList() else { throw Missing() }
        return payload
    }

    private struct Missing: Error {}

    @Test func heartbeatAdvertisesInventoryWithInsightOff() throws {
        let fixture = try makeFixture()
        #expect(fixture.handler.heartbeat().offersInventory)
        #expect(!fixture.handler.heartbeat().offersInsight)
    }

    @Test func deviceListSaysWhichNetworkAndHowOldItsScanIs() throws {
        let fixture = try makeFixture()
        let scanTime = Date().addingTimeInterval(-90)
        fixture.discovery.reconcileScan(
            [LocalDiscoveredDevice(ipAddress: "192.168.77.20", macAddress: "02:00:00:77:00:20", hostname: "speaker.local")],
            profileID: fixture.profile.id, now: scanTime
        )
        let network = try #require(try deviceList(fixture.handler).network)
        #expect(network.subnet == "192.168.77.0/24")
        #expect(network.name == "Test Network")
        let age = try #require(network.scanAge)
        #expect(age >= 89 && age < 120)
    }

    /// #585 review: the phone tells the network by the routed gateway, not the profile's first-host
    /// guess, and reads an inventory Mac from the list's `network`, so it is always sent.
    @Test func theListCarriesTheRoutedGatewayAndAlwaysANetwork() throws {
        let fixture = try makeFixture()
        #expect(try deviceList(fixture.handler).network?.gatewayIP == "192.168.77.254")
        let unknown = try makeFixture(gateway: nil)
        #expect(try deviceList(unknown.handler).network?.gatewayIP == nil)
        let noNetwork = try makeFixture(profiles: [])
        let network = try #require(try deviceList(noNetwork.handler).network)
        #expect(network.subnet == nil)
    }

    /// #585 review 12: a large store still fits one frame, most recently seen devices first.
    @Test func aLargeInventoryFitsOneFrame() throws {
        let fixture = try makeFixture()
        let scan = (0..<1500).map { index in
            LocalDiscoveredDevice(
                ipAddress: "10.\(index / 250).\(index % 250).1", macAddress: String(format: "02:00:00:00:%02X:%02X", index / 256, index % 256),
                hostname: "device-\(index)-" + String(repeating: "x", count: 600)
            )
        }
        fixture.discovery.reconcileScan(scan, profileID: fixture.profile.id, now: Date().addingTimeInterval(-60))
        let message = fixture.handler.generateDeviceList()
        let frame = try message.encodeLengthPrefixed()
        #expect(frame.count <= CompanionFrameDecoder.defaultMaximumFrameSize)
        guard case .deviceList(let list) = message else { throw Missing() }
        #expect(!list.devices.isEmpty)
        #expect(list.devices.count < 1500)
    }

    @Test func eachDeviceCarriesItsAgesAndIdentity() throws {
        let fixture = try makeFixture()
        let seen = Date().addingTimeInterval(-300)
        fixture.discovery.reconcileScan([
            LocalDiscoveredDevice(
                ipAddress: "192.168.77.20", macAddress: "02:00:00:77:00:20", hostname: "speaker.local",
                identity: DeviceIdentity(maker: IdentityValue("Sonos", source: .upnp), model: IdentityValue("Era 100", source: .bonjour))
            )
        ], profileID: fixture.profile.id, now: seen)
        let row = try #require(fixture.discovery.discoveredDevices.first)
        // The device's log: it left two hours ago and came back an hour ago; the newest entry counts.
        fixture.events.log(NetworkEvent(type: .deviceLeft, timestamp: Date().addingTimeInterval(-7200), title: "Left", deviceID: row.id))
        fixture.events.log(NetworkEvent(type: .deviceJoined, timestamp: Date().addingTimeInterval(-3600), title: "Joined", deviceID: row.id))
        fixture.events.log(NetworkEvent(type: .scanComplete, timestamp: Date(), title: "Scan"))

        let device = try #require(try deviceList(fixture.handler).devices.first)
        let lastSeenAge = try #require(device.lastSeenAge)
        #expect(lastSeenAge >= 299 && lastSeenAge < 330)
        let lastChangedAge = try #require(device.lastChangedAge)
        #expect(lastChangedAge >= 3599 && lastChangedAge < 3630)
        #expect(device.identity?.deviceIdentity.maker == IdentityValue("Sonos", source: .upnp))
        #expect(device.identity?.deviceIdentity.model == IdentityValue("Era 100", source: .bonjour))
    }

    @Test func aDeviceWithoutLoggedChangesHasNoLastChanged() throws {
        let fixture = try makeFixture()
        fixture.discovery.reconcileScan(
            [LocalDiscoveredDevice(ipAddress: "192.168.77.21", macAddress: "02:00:00:77:00:21", hostname: "tv.local")],
            profileID: fixture.profile.id
        )
        #expect(try deviceList(fixture.handler).devices.first?.lastChangedAge == nil)
    }

    @Test func theListGoesToPhonesAfterEachScan() throws {
        let fixture = try makeFixture()
        var sent: [CompanionMessage] = []
        fixture.handler.onScanCompleted { sent.append($0) }
        fixture.discovery.reconcileScan(
            [LocalDiscoveredDevice(ipAddress: "192.168.77.22", macAddress: "02:00:00:77:00:22", hostname: "nas.local")],
            profileID: fixture.profile.id
        )
        for completed in fixture.discovery.scanCompletedHandlers {
            completed(fixture.profile.id, 1)
        }
        guard case .deviceList(let payload)? = sent.last else {
            Issue.record("Expected the device list to be sent: \(sent.map(\.logName))")
            return
        }
        #expect(payload.devices.map(\.ipAddress) == ["192.168.77.22"])
    }
}
