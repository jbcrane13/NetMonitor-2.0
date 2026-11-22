import Foundation
import SwiftData
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

@MainActor
struct DeviceDetailViewModelTests {
    @Test func loadDeviceCreatesRecordWhenNoExistingDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let viewModel = makeViewModel()
        viewModel.loadDevice(ipAddress: "192.168.1.50", context: context)

        #expect(viewModel.device != nil)
        #expect(viewModel.device?.ipAddress == "192.168.1.50")

        let descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate { $0.ipAddress == "192.168.1.50" }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
    }

    /// #426: a fresh detail row used to lose the scan's maker, MAC and name, so the header
    /// showed no manufacturer.
    @Test func loadDeviceFillsMakerMACAndNameFromLatestScan() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }

        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(
                ipAddress: "192.168.1.80", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:00:11:22",
                latency: nil, discoveredAt: Date(), source: .local,
                identity: DeviceIdentity(
                    maker: IdentityValue("Samsung", source: .upnp),
                    model: IdentityValue("Q80", source: .upnp),
                    friendlyName: IdentityValue("Living Room TV", source: .upnp)
                )
            ),
            DiscoveredDevice(
                ipAddress: "192.168.1.81", hostname: "Studio", vendor: "Apple", macAddress: nil,
                latency: nil, discoveredAt: Date(), source: .bonjour,
                identity: DeviceIdentity(model: IdentityValue("Mac16,10", source: .bonjour))
            )
        ]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.80", context: context)
        #expect(viewModel.device?.identity.maker == IdentityValue("Samsung", source: .upnp))
        #expect(viewModel.device?.maker == "Samsung")
        #expect(viewModel.device?.macAddress == "AA:BB:CC:00:11:22")
        // The friendly name is kept apart from the hostname, and names the device (ADR-022).
        #expect(viewModel.device?.hostname == nil)
        #expect(viewModel.device?.displayName == "Living Room TV")

        viewModel.loadDevice(ipAddress: "192.168.1.81", context: context)
        #expect(viewModel.device?.maker == "Apple")
        #expect(viewModel.device?.vendor == "Apple")
        #expect(viewModel.device?.hostname == "Studio")
        #expect(viewModel.device?.macAddress.isEmpty == true)
    }

    @Test func loadDeviceTakesModelFromLatestScan() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(
                ipAddress: "192.168.1.70", hostname: "Studio", vendor: nil, macAddress: nil,
                latency: nil, discoveredAt: Date(), source: .bonjour,
                identity: DeviceIdentity(model: IdentityValue("Mac16,10", source: .bonjour))
            ),
            DiscoveredDevice(
                ipAddress: "192.168.1.71", hostname: nil, vendor: nil, macAddress: nil,
                latency: nil, discoveredAt: Date(), source: .local
            )
        ]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.70", context: context)
        #expect(viewModel.device?.modelName == "Mac16,10")

        viewModel.loadDevice(ipAddress: "192.168.1.71", context: context)
        #expect(viewModel.device?.modelName == nil)
    }

    @Test func loadDeviceReusesExistingDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let existing = LocalDevice(
            ipAddress: "192.168.1.60",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        context.insert(existing)
        try context.save()

        let viewModel = makeViewModel()
        viewModel.loadDevice(ipAddress: "192.168.1.60", context: context)

        #expect(viewModel.device?.id == existing.id)
    }

    @Test func enrichDeviceSetsMACPrefixMakerAndResolvedHostname() async {
        let macLookup = MockMACVendorLookupService(vendor: "Acme Networking")
        let nameResolver = MockDeviceNameResolver(hostname: "router.local")
        let viewModel = makeViewModel(
            macLookupService: macLookup,
            nameResolver: nameResolver
        )

        viewModel.device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "00:11:22:33:44:55"
        )

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(viewModel.device?.vendor == "Acme Networking")
        #expect(viewModel.device?.maker == "Acme Networking")
        #expect(viewModel.device?.resolvedHostname == "router.local")
        #expect(macLookup.lookupCallCount == 1)
        #expect(nameResolver.resolveCallCount == 1)
        #expect(viewModel.isLoading == false)
    }

    @Test func enrichDeviceSkipsManufacturerLookupForEmptyMAC() async {
        let macLookup = MockMACVendorLookupService(vendor: "ShouldNotBeUsed")
        let nameResolver = MockDeviceNameResolver(hostname: "host.local")
        let viewModel = makeViewModel(
            macLookupService: macLookup,
            nameResolver: nameResolver
        )

        viewModel.device = LocalDevice(ipAddress: "192.168.1.10", macAddress: "")

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(viewModel.device?.vendor == nil)
        #expect(viewModel.device?.resolvedHostname == "host.local")
        #expect(macLookup.lookupCallCount == 0)
        #expect(nameResolver.resolveCallCount == 1)
    }

    @Test func scanPortsStoresOnlyOpenPortsSorted() async {
        let portScanner = MockPortScannerService()
        portScanner.mockResults = [
            PortScanResult(port: 443, state: .closed),
            PortScanResult(port: 8080, state: .open),
            PortScanResult(port: 22, state: .open),
            PortScanResult(port: 53, state: .closed),
            PortScanResult(port: 80, state: .open)
        ]

        let viewModel = makeViewModel(portScanner: portScanner)
        viewModel.device = LocalDevice(ipAddress: "192.168.1.20", macAddress: "AA:BB")

        await viewModel.scanPorts()

        #expect(viewModel.device?.openPorts == [22, 80, 8080])
        #expect(viewModel.isScanning == false)
    }

    @Test func discoverServicesStoresOnlyUniqueServicesForMatchingDeviceIP() async {
        let bonjour = MockBonjourDiscoveryService()
        bonjour.mockStreamServices = [
            BonjourService(
                name: "Office Printer",
                type: "_ipp._tcp",
                addresses: ["192.168.1.88"]
            ),
            BonjourService(
                name: "Office Printer",
                type: "_ipp._tcp",
                addresses: ["192.168.1.88"]
            ),
            BonjourService(
                name: "Wrong Device",
                type: "_http._tcp",
                addresses: ["192.168.1.99"]
            ),
            BonjourService(
                name: "Camera",
                type: "_rtsp._tcp",
                hostName: "192.168.1.88"
            )
        ]

        let viewModel = makeViewModel(bonjourService: bonjour)
        viewModel.device = LocalDevice(ipAddress: "192.168.1.88", macAddress: "AA:BB")

        await viewModel.discoverServices()

        let discovered = Set(viewModel.device?.discoveredServices ?? [])
        #expect(discovered == Set(["Office Printer (_ipp._tcp)", "Camera (_rtsp._tcp)"]))
        #expect(viewModel.device?.discoveredServices?.count == 2)
        #expect(viewModel.isDiscovering == false)
    }

    @Test func enrichDeviceWithNilDeviceDoesNothing() async {
        let macLookup = MockMACVendorLookupService(vendor: "ShouldNotBeUsed")
        let viewModel = makeViewModel(macLookupService: macLookup)
        // device is nil — no-op

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(viewModel.isLoading == false)
        #expect(macLookup.lookupCallCount == 0)
    }

    @Test func enrichDeviceSkipsVendorLookupWhenAlreadySet() async {
        let macLookup = MockMACVendorLookupService(vendor: "ShouldNotBeUsed")
        let viewModel = makeViewModel(macLookupService: macLookup)
        viewModel.device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendor: "Apple"
        )

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(macLookup.lookupCallCount == 0)
        #expect(viewModel.device?.vendor == "Apple")
    }

    @Test func enrichDeviceSkipsHostnameWhenAlreadySet() async {
        let nameResolver = MockDeviceNameResolver(hostname: "should.not.appear")
        let viewModel = makeViewModel(nameResolver: nameResolver)
        viewModel.device = LocalDevice(
            ipAddress: "192.168.1.2",
            macAddress: "",
            resolvedHostname: "already.set.local"
        )

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(nameResolver.resolveCallCount == 0)
        #expect(viewModel.device?.resolvedHostname == "already.set.local")
    }

    @Test func scanPortsWithNilDeviceDoesNothing() async {
        let viewModel = makeViewModel()
        // device is nil

        await viewModel.scanPorts()

        #expect(viewModel.isScanning == false)
    }

    @Test func discoverServicesWithNilDeviceDoesNothing() async {
        let viewModel = makeViewModel()
        // device is nil

        await viewModel.discoverServices()

        #expect(viewModel.isDiscovering == false)
    }

    // MARK: - #463: the row is found by device match within its network

    private func scanned(_ ip: String, mac: String?, network: UUID, hostname: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: hostname, vendor: nil, macAddress: mac,
            latency: nil, discoveredAt: Date(), source: .local, networkProfileID: network
        )
    }

    @Test func twoNetworksSharingAnIPKeepSeparateRows() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID(), office = UUID()
        let discovery = MockDeviceDiscoveryService()
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        discovery.discoveredDevices = [scanned("192.168.1.10", mac: nil, network: home)]
        viewModel.loadDevice(ipAddress: "192.168.1.10", context: context)
        viewModel.device?.notes = "home printer"

        discovery.discoveredDevices = [scanned("192.168.1.10", mac: nil, network: office)]
        viewModel.loadDevice(ipAddress: "192.168.1.10", context: context)
        #expect(viewModel.device?.notes == nil)
        #expect(viewModel.device?.networkProfileID == office)

        discovery.discoveredDevices = [scanned("192.168.1.10", mac: nil, network: home)]
        viewModel.loadDevice(ipAddress: "192.168.1.10", context: context)
        #expect(viewModel.device?.notes == "home printer")
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 2)
    }

    @Test func aRowSavedWithoutANetworkIsAdoptedByTheFirstNetworkThatOpensIt() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let legacy = LocalDevice(ipAddress: "192.168.1.20", macAddress: "")
        legacy.customName = "NAS"
        context.insert(legacy)
        let home = UUID()
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scanned("192.168.1.20", mac: nil, network: home)]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.20", context: context)

        #expect(viewModel.device?.customName == "NAS")
        #expect(viewModel.device?.networkProfileID == home)
    }

    @Test func aDeviceThatMovedToAnotherIPKeepsItsRow() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let saved = LocalDevice(ipAddress: "192.168.1.30", macAddress: "3C:22:FB:00:00:30", networkProfileID: home)
        saved.customName = "Studio"
        context.insert(saved)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scanned("192.168.1.31", mac: "3C:22:FB:00:00:30", network: home)]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.31", context: context)

        #expect(viewModel.device?.customName == "Studio")
        #expect(viewModel.device?.ipAddress == "192.168.1.31")
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    @Test func aCachedDeviceOpensItsNetworksRow() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let saved = LocalDevice(ipAddress: "192.168.1.40", macAddress: "", networkProfileID: home)
        saved.notes = "garage"
        context.insert(saved)
        // The list showed a cached result: the live scan array is empty.
        let viewModel = makeViewModel(deviceDiscoveryService: MockDeviceDiscoveryService())

        viewModel.loadDevice(ipAddress: "192.168.1.40", networkID: home, context: context)

        #expect(viewModel.device?.notes == "garage")
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    @Test func aNewcomerAtAMovedDevicesOldAddressGetsItsOwnRow() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let laptop = LocalDevice(ipAddress: "192.168.1.50", macAddress: "3C:22:FB:00:00:50", networkProfileID: home)
        laptop.notes = "Blake's laptop"
        context.insert(laptop)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            scanned("192.168.1.51", mac: "3C:22:FB:00:00:50", network: home), // the laptop moved
            scanned("192.168.1.50", mac: nil, network: home)                  // something new took .50
        ]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.50", networkID: home, context: context)

        #expect(viewModel.device?.notes == nil)
        #expect(laptop.ipAddress == "192.168.1.50")
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 2)
    }

    private func makeViewModel(
        macLookupService: any MACVendorLookupServiceProtocol = MockMACVendorLookupService(vendor: nil),
        nameResolver: any DeviceNameResolverProtocol = MockDeviceNameResolver(hostname: nil),
        portScanner: any PortScannerServiceProtocol = MockPortScannerService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = MockBonjourDiscoveryService(),
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = MockDeviceDiscoveryService()
    ) -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            macLookupService: macLookupService,
            nameResolver: nameResolver,
            portScanner: portScanner,
            bonjourService: bonjourService,
            deviceDiscoveryService: deviceDiscoveryService
        )
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            LocalDevice.self,
            MonitoringTarget.self,
            ToolResult.self,
            SpeedTestResult.self,
            PairedMac.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}

private final class MockMACVendorLookupService: MACVendorLookupServiceProtocol, @unchecked Sendable {
    private let vendor: String?
    private(set) var lookupCallCount = 0

    init(vendor: String?) {
        self.vendor = vendor
    }

    func lookup(macAddress: String) async -> String? {
        lookupCallCount += 1
        return vendor
    }
}

private final class MockDeviceNameResolver: DeviceNameResolverProtocol, @unchecked Sendable {
    private let hostname: String?
    private(set) var resolveCallCount = 0

    init(hostname: String?) {
        self.hostname = hostname
    }

    func resolve(ipAddress: String) async -> String? {
        resolveCallCount += 1
        return hostname
    }
}
