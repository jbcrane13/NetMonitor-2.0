import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #628: device detail writes rows only from a device the current scan lists, under a token still
/// current, and probes save only under the token of the observation that placed the device.
extension DeviceDetailViewModelTests {
    /// #628: ports measured while the path changed may be another network's device, so they
    /// aren't saved; after the device is listed again by a current scan, they are.
    @Test func portsFoundAcrossAPathUpdateAreNotSaved() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let join = NetworkJoinClock.forTests
        let portScanner = MockPortScannerService()
        portScanner.mockResults = [PortScanResult(port: 22, state: .open)]
        let generation = join.generation
        portScanner.duringScan = { generation.advance() }
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevicesToken = join.token(for: nil)
        let viewModel = makeViewModel(portScanner: portScanner, deviceDiscoveryService: discovery, joinClock: join)
        openListed(viewModel, in: discovery, ip: "192.168.1.20", mac: "AA:BB", context: context)

        await viewModel.scanPorts()
        #expect(viewModel.device?.openPorts == nil)

        portScanner.duringScan = nil
        discovery.discoveredDevicesToken = join.token(for: nil)
        viewModel.loadDevice(ipAddress: "192.168.1.20", context: context)
        await viewModel.scanPorts()
        #expect(viewModel.device?.openPorts == [22])
    }

    /// #628 (lead review on #633): a scan started on network A, then a path change. Opening a device
    /// from its list inserts nothing and changes no saved row; the user is told to scan again. A
    /// saved device it names opens read-only, and a user edit to it still saves.
    @Test func aScanInvalidatedByAPathChangeWritesNothingFromDetailButEditsSave() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let saved = LocalDevice(ipAddress: "192.168.1.30", macAddress: "", hostname: "nas", networkProfileID: network)
        context.insert(saved)
        try context.save()
        let join = NetworkJoinClock(changes: AsyncStream<String>.makeStream().stream)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            Self.scanned("192.168.1.30", mac: "00:1B:A9:00:00:30", vendor: "Brother", network: network),
            Self.scanned("192.168.1.31", mac: "00:1B:A9:00:00:31", vendor: "Brother", network: network)
        ]
        discovery.discoveredDevicesToken = join.token(for: network)
        join.noteResume()
        let viewModel = makeViewModel(deviceDiscoveryService: discovery, joinClock: join)

        viewModel.loadDevice(ipAddress: "192.168.1.31", networkID: network, context: context)
        #expect(viewModel.device == nil)
        #expect(viewModel.error == DeviceDetailViewModel.interruptedScanMessage)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)

        viewModel.loadDevice(ipAddress: "192.168.1.30", networkID: network, context: context)
        #expect(viewModel.device?.id == saved.id)
        #expect(saved.macAddress.isEmpty)
        #expect(saved.vendor == nil)

        // A user edit is never blocked.
        viewModel.device?.customName = "Backup NAS"
        viewModel.saveContext()
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<LocalDevice>()).first?.customName == "Backup NAS")
    }

    /// #628 (lead verification on #633): a scan on A, then a path change (same-subnet B). Opening the
    /// device writes no hostname, port or service to A's row: the probes' address comes from a saved
    /// row, not a current observation.
    @Test func probesOfADeviceOpenedAfterAPathChangeWriteNothing() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let saved = LocalDevice(ipAddress: "192.168.1.30", macAddress: "", hostname: "nas", networkProfileID: network)
        context.insert(saved)
        let join = NetworkJoinClock.forTests
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [Self.scanned("192.168.1.30", mac: "00:1B:A9:00:00:30", vendor: "Brother", network: network)]
        discovery.discoveredDevicesToken = join.token(for: network)
        join.noteResume()
        let ports = MockPortScannerService()
        ports.mockResults = [PortScanResult(port: 22, state: .open)]
        let viewModel = makeViewModel(
            nameResolver: MockDeviceNameResolver(hostname: "other-site.local"), portScanner: ports, deviceDiscoveryService: discovery,
            joinClock: join
        )

        viewModel.loadDevice(ipAddress: "192.168.1.30", networkID: network, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        await viewModel.scanPorts()
        #expect(saved.resolvedHostname == nil)
        #expect(saved.openPorts == nil)
    }

    /// Opened while the scan was current, then the path changed: a probe started now measures
    /// wherever that address is now, so its result isn't saved either.
    @Test func probesAfterAPathChangeWriteNothingToARowOpenedBefore() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let join = NetworkJoinClock.forTests
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [Self.scanned("192.168.1.31", mac: "00:1B:A9:00:00:31", vendor: "Brother", network: network)]
        discovery.discoveredDevicesToken = join.token(for: network)
        let ports = MockPortScannerService()
        ports.mockResults = [PortScanResult(port: 22, state: .open)]
        let viewModel = makeViewModel(portScanner: ports, deviceDiscoveryService: discovery, joinClock: join)
        viewModel.loadDevice(ipAddress: "192.168.1.31", networkID: network, context: context)
        let row = try #require(viewModel.device)

        join.noteResume()
        await viewModel.scanPorts()
        #expect(row.openPorts == nil)
    }

    /// #628 (lead verification on #633): the dashboard shows manual network M's cache while a local
    /// scan is current. Tapping an entry the current scan didn't list inserts or moves nothing.
    @Test func anEntryFromAnotherNetworksCacheMakesNoRow() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let local = UUID()
        let manual = UUID()
        let join = NetworkJoinClock.forTests
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [Self.scanned("192.168.1.31", mac: "00:1B:A9:00:00:31", vendor: "Brother", network: local)]
        discovery.discoveredDevicesToken = join.token(for: local)
        let viewModel = makeViewModel(deviceDiscoveryService: discovery, joinClock: join)

        viewModel.loadDevice(ipAddress: "10.9.0.40", networkID: manual, macAddress: "00:1B:A9:00:00:40", context: context)
        #expect(viewModel.device == nil)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    /// #628 (lead verification on #633): a list with no token fails closed.
    @Test func aListWithNoTokenMakesNoRow() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [Self.scanned("192.168.1.31", mac: "00:1B:A9:00:00:31", vendor: "Brother", network: network)]
        discovery.discoveredDevicesToken = nil
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.31", networkID: network, context: context)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    /// The same list while its token is current: detail makes and fills the row as before.
    @Test func aCurrentScanStillMakesTheRow() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let join = NetworkJoinClock.forTests
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [Self.scanned("192.168.1.31", mac: "00:1B:A9:00:00:31", vendor: "Brother", network: network)]
        discovery.discoveredDevicesToken = join.token(for: network)
        let viewModel = makeViewModel(deviceDiscoveryService: discovery, joinClock: join)

        viewModel.loadDevice(ipAddress: "192.168.1.31", networkID: network, context: context)
        #expect(viewModel.device?.vendor == "Brother")
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    /// Stop-time review on #633: a cached entry (listed, but it didn't answer this scan; its address
    /// is an old one) is published under the current scan's token. It makes, moves or probes nothing.
    @Test func aCachedEntryInTheCurrentScanMakesNoRowAndIsNotProbed() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let network = UUID()
        let saved = LocalDevice(ipAddress: "192.168.1.30", macAddress: "", hostname: "nas", networkProfileID: network)
        context.insert(saved)
        let join = NetworkJoinClock.forTests
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(
                ipAddress: "192.168.1.30", hostname: nil, vendor: "Brother", macAddress: "00:1B:A9:00:00:30", latency: nil,
                discoveredAt: Date(), source: .local, networkProfileID: network, isCached: true
            ),
            DiscoveredDevice(
                ipAddress: "192.168.1.31", hostname: nil, vendor: "Brother", macAddress: "00:1B:A9:00:00:31", latency: nil,
                discoveredAt: Date(), source: .local, networkProfileID: network, isCached: true
            )
        ]
        discovery.discoveredDevicesToken = join.token(for: network)
        let viewModel = makeViewModel(deviceDiscoveryService: discovery, joinClock: join)

        viewModel.loadDevice(ipAddress: "192.168.1.31", networkID: network, context: context)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)

        viewModel.loadDevice(ipAddress: "192.168.1.30", networkID: network, context: context)
        #expect(viewModel.device?.id == saved.id)
        #expect(saved.vendor == nil)
        #expect(saved.macAddress.isEmpty)
        #expect(viewModel.probeAddress == nil)
    }

    static func scanned(_ ip: String, mac: String, vendor: String, network: UUID) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: nil, vendor: vendor, macAddress: mac, latency: 3, discoveredAt: Date(), source: .local,
            networkProfileID: network
        )
    }
}
